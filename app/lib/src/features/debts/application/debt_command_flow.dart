import '../../daily_ledger/application/pending_financial_command.dart';
import 'debt_contract.dart';
import 'debt_gateway.dart';

sealed class DebtSubmitResult {
  const DebtSubmitResult();
}

final class DebtSaved extends DebtSubmitResult {
  const DebtSaved(this.committed);
  final DebtRpcCommitted committed;
}

final class DebtFailed extends DebtSubmitResult {
  const DebtFailed(this.code);
  final String code;
}

/// Stored locally and not a confirmed debt command yet.
final class DebtUnconfirmed extends DebtSubmitResult {
  const DebtUnconfirmed(this.command, {required this.statusUnknown});
  final PendingFinancialCommand command;
  final bool statusUnknown;
}

final class DebtNotSent extends DebtSubmitResult {
  const DebtNotSent(this.code);
  final String code;
}

class DebtCommandFlow {
  const DebtCommandFlow({required this.gateway, required this.store});

  final DebtGateway gateway;
  final FinancialCommandLocker store;

  Future<DebtSubmitResult> submit({
    required String userId,
    required String shopId,
    required String idempotencyKey,
    required String kind,
    required Map<String, Object?> payload,
    required bool readOnly,
  }) async {
    if (readOnly) return const DebtNotSent('shop_not_active');
    final pending = PendingFinancialCommand(
      key: idempotencyKey,
      kind: kind,
      body: {'p_idempotency_key': idempotencyKey, 'p_payload': payload},
    );
    if (!ownsDebtCommand(pending.key, pending.kind, pending.body)) {
      return const DebtNotSent('invalid_input');
    }
    try {
      await store.save(userId, shopId, pending);
    } on StateError catch (error) {
      return DebtNotSent(
        const {
              'pending_financial_exists',
              'pending_financial_payload_mismatch',
            }.contains(error.message)
            ? 'other_pending'
            : 'storage',
      );
    } catch (_) {
      return const DebtNotSent('storage');
    }
    return _send(userId, shopId, pending);
  }

  /// Uses the debt registry. Opening status does not prove a debt command.
  Future<DebtSubmitResult> reconcile({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
    required bool retry,
  }) async {
    if (!ownsDebtCommand(command.key, command.kind, command.body)) {
      return const DebtNotSent('invalid_input');
    }
    final status = await _status(userId, command);
    if (status is DebtRemoteCompleted) {
      return _savedFromStatus(userId, shopId, command, status);
    }
    if (status is! DebtRemoteAbsent) {
      return DebtUnconfirmed(command, statusUnknown: true);
    }
    if (!retry) return DebtUnconfirmed(command, statusUnknown: false);
    return _send(userId, shopId, command);
  }

  Future<DebtSubmitResult> _send(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    final DebtRpcResult result;
    try {
      result = await gateway.submitCommand(
        callerUserId: userId,
        command: command,
      );
    } catch (_) {
      return DebtUnconfirmed(command, statusUnknown: true);
    }
    if (result is DebtRpcCommitted) {
      if (!_matchesCommand(
        command,
        result.commandKind,
        result.sourceKind,
        result.sourceId,
      )) {
        return DebtUnconfirmed(command, statusUnknown: true);
      }
      await _clear(userId, shopId, command.key);
      return DebtSaved(result);
    }
    if (result is DebtRpcRejected) {
      await _clear(userId, shopId, command.key);
      return DebtFailed(result.code);
    }
    final status = await _status(userId, command);
    if (status is DebtRemoteCompleted) {
      return _savedFromStatus(userId, shopId, command, status);
    }
    return DebtUnconfirmed(command, statusUnknown: status is! DebtRemoteAbsent);
  }

  Future<DebtRemoteStatus> _status(
    String userId,
    PendingFinancialCommand command,
  ) async {
    try {
      final status = await gateway.readCommandStatus(
        callerUserId: userId,
        idempotencyKey: command.key,
      );
      if (status is DebtRemoteRejected) return const DebtRemoteUnknown();
      if (status is DebtRemoteCompleted &&
          !_matchesCommand(
            command,
            status.kind,
            status.sourceKind,
            status.sourceId,
          )) {
        return const DebtRemoteUnknown();
      }
      return status;
    } catch (_) {
      return const DebtRemoteUnknown();
    }
  }

  bool _matchesCommand(
    PendingFinancialCommand command,
    String kind,
    String sourceKind,
    String sourceId,
  ) {
    if (kind != command.kind) return false;
    final payload = command.body['p_payload'];
    if (payload is! Map) return false;
    final expected = payload['source_id'];
    if (expected == null) {
      return command.kind == 'debt_declare' && sourceKind == 'standalone';
    }
    return expected == sourceId && payload['source_kind'] == sourceKind;
  }

  Future<DebtSubmitResult> _savedFromStatus(
    String userId,
    String shopId,
    PendingFinancialCommand command,
    DebtRemoteCompleted status,
  ) async {
    await _clear(userId, shopId, command.key);
    return DebtSaved(status.committed);
  }

  Future<void> _clear(String userId, String shopId, String key) async {
    try {
      await store.clear(userId, shopId, key);
    } catch (_) {}
  }
}

import '../../daily_ledger/application/pending_financial_command.dart';
import 'repair_contract.dart';
import 'repair_gateway.dart';

sealed class RepairSubmitResult {
  const RepairSubmitResult();
}

final class RepairSaved extends RepairSubmitResult {
  const RepairSaved(this.repairId, {required this.replayed});
  final String repairId;
  final bool replayed;
}

final class RepairFailed extends RepairSubmitResult {
  const RepairFailed(this.code);
  final String code;
}

/// Stored locally and not a confirmed repair yet.
final class RepairUnconfirmed extends RepairSubmitResult {
  const RepairUnconfirmed(this.command, {required this.statusUnknown});
  final PendingFinancialCommand command;
  final bool statusUnknown;
}

final class RepairNotSent extends RepairSubmitResult {
  const RepairNotSent(this.code);
  final String code;
}

class RepairCommandFlow {
  const RepairCommandFlow({required this.gateway, required this.store});

  final RepairGateway gateway;
  final FinancialCommandLocker store;

  Future<RepairSubmitResult> submit({
    required String userId,
    required String shopId,
    required String idempotencyKey,
    required String kind,
    required Map<String, Object?> payload,
    required bool readOnly,
  }) async {
    if (readOnly) return const RepairNotSent('shop_not_active');
    final pending = PendingFinancialCommand(
      key: idempotencyKey,
      kind: kind,
      body: {'p_idempotency_key': idempotencyKey, 'p_payload': payload},
    );
    if (!ownsRepairCommand(pending.key, pending.kind, pending.body)) {
      return const RepairNotSent('invalid_input');
    }
    try {
      await store.save(userId, shopId, pending);
    } on StateError catch (error) {
      return RepairNotSent(
        const {
              'pending_financial_exists',
              'pending_financial_payload_mismatch',
            }.contains(error.message)
            ? 'other_pending'
            : 'storage',
      );
    } catch (_) {
      return const RepairNotSent('storage');
    }
    return _send(userId, shopId, pending);
  }

  /// Uses the repair registry. Opening status does not prove custody commands.
  Future<RepairSubmitResult> reconcile({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
    required bool retry,
  }) async {
    if (!ownsRepairCommand(command.key, command.kind, command.body)) {
      return const RepairNotSent('invalid_input');
    }
    final status = await _status(userId, command);
    if (status is RepairRemoteCompleted) {
      await _clear(userId, shopId, command.key);
      return RepairSaved(status.repairId, replayed: true);
    }
    if (status is! RepairRemoteAbsent) {
      return RepairUnconfirmed(command, statusUnknown: true);
    }
    if (!retry) return RepairUnconfirmed(command, statusUnknown: false);
    return _send(userId, shopId, command);
  }

  Future<RepairSubmitResult> _send(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    final RepairRpcResult result;
    try {
      result = await gateway.post(callerUserId: userId, command: command);
    } catch (_) {
      return RepairUnconfirmed(command, statusUnknown: true);
    }
    if (result is RepairRpcCommitted) {
      final expectedId = (command.body['p_payload'] as Map)['repair_id'];
      if (expectedId != null && expectedId != result.repairId) {
        return RepairUnconfirmed(command, statusUnknown: true);
      }
      await _clear(userId, shopId, command.key);
      return RepairSaved(result.repairId, replayed: result.replayed);
    }
    if (result is RepairRpcRejected) {
      await _clear(userId, shopId, command.key);
      return RepairFailed(result.code);
    }
    final status = await _status(userId, command);
    if (status is RepairRemoteCompleted) {
      await _clear(userId, shopId, command.key);
      return RepairSaved(status.repairId, replayed: true);
    }
    return RepairUnconfirmed(
      command,
      statusUnknown: status is! RepairRemoteAbsent,
    );
  }

  Future<RepairRemoteStatus> _status(
    String userId,
    PendingFinancialCommand command,
  ) async {
    try {
      final status = await gateway.commandStatus(
        callerUserId: userId,
        idempotencyKey: command.key,
      );
      // A read failure says nothing about whether the original write committed.
      if (status is RepairRemoteRejected) return const RepairRemoteUnknown();
      if (status is RepairRemoteCompleted) {
        final expectedId = (command.body['p_payload'] as Map)['repair_id'];
        if (status.kind != command.kind ||
            (expectedId != null && expectedId != status.repairId)) {
          return const RepairRemoteUnknown();
        }
      }
      return status;
    } catch (_) {
      return const RepairRemoteUnknown();
    }
  }

  /// A cleanup failure keeps the known command so the next reconcile is safe.
  Future<void> _clear(String userId, String shopId, String key) async {
    try {
      await store.clear(userId, shopId, key);
    } catch (_) {}
  }
}

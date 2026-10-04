import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../domain/inventory_models.dart';
import 'inventory_contract.dart';
import 'inventory_gateway.dart';

sealed class InventorySubmitResult {
  const InventorySubmitResult();
}

final class InventorySaved extends InventorySubmitResult {
  const InventorySaved(this.id, {required this.replayed});
  final String id;
  final bool replayed;
}

final class InventoryFailed extends InventorySubmitResult {
  const InventoryFailed(this.code, {required this.rereview});
  final String code;
  final bool rereview;
}

/// The command is stored and is not a confirmed balance yet.
final class InventoryUnconfirmed extends InventorySubmitResult {
  const InventoryUnconfirmed(this.command, {required this.statusUnknown});
  final PendingFinancialCommand command;
  final bool statusUnknown;
}

final class InventoryNotSent extends InventorySubmitResult {
  const InventoryNotSent(this.code);
  final String code;
}

class InventoryCommandFlow {
  const InventoryCommandFlow({
    required this.gateway,
    required this.statusGateway,
    required this.store,
  });

  final InventoryGateway gateway;
  final OpeningGateway statusGateway;
  final FinancialCommandLocker store;

  Future<InventorySubmitResult> submit({
    required String userId,
    required String shopId,
    required String idempotencyKey,
    required ReviewedCommand command,
    required bool readOnly,
  }) async {
    if (readOnly) return const InventoryNotSent('shop_not_active');
    final pending = PendingFinancialCommand(
      key: idempotencyKey,
      kind: command.kind,
      body: command.envelope(idempotencyKey),
    );
    if (!ownsInventoryCommand(pending.key, pending.kind, pending.body)) {
      return const InventoryNotSent('invalid_input');
    }
    try {
      await store.save(userId, shopId, pending);
    } on StateError {
      return const InventoryNotSent('other_pending');
    } catch (_) {
      return const InventoryNotSent('storage');
    }
    return _send(userId, shopId, pending);
  }

  /// Checks server status before any retry of the original envelope.
  Future<InventorySubmitResult> reconcile({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
    required bool retry,
  }) async {
    if (!ownsInventoryCommand(command.key, command.kind, command.body)) {
      return const InventoryNotSent('invalid_input');
    }
    final status = await _status(userId, command);
    if (status is StatusCompleted) {
      await store.clear(userId, shopId, command.key);
      return InventorySaved(status.operationId, replayed: true);
    }
    if (status is StatusRejected) {
      await store.clear(userId, shopId, command.key);
      return InventoryFailed(status.code, rereview: status.code == 'stale_day');
    }
    if (status is! StatusAbsent) {
      return InventoryUnconfirmed(command, statusUnknown: true);
    }
    if (!retry) return InventoryUnconfirmed(command, statusUnknown: false);
    return _send(userId, shopId, command);
  }

  Future<InventorySubmitResult> _send(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    final result = await gateway.postStored(
      callerUserId: userId,
      command: command,
    );
    if (result is FinancialCommitted) {
      await store.clear(userId, shopId, command.key);
      return InventorySaved(result.operationId, replayed: result.replayed);
    }
    if (result is FinancialRejected) {
      await store.clear(userId, shopId, command.key);
      return InventoryFailed(result.code, rereview: result.code == 'stale_day');
    }
    final status = await _status(userId, command);
    if (status is StatusCompleted) {
      await store.clear(userId, shopId, command.key);
      return InventorySaved(status.operationId, replayed: true);
    }
    if (status is StatusRejected) {
      await store.clear(userId, shopId, command.key);
      return InventoryFailed(status.code, rereview: status.code == 'stale_day');
    }
    return InventoryUnconfirmed(
      command,
      statusUnknown: status is! StatusAbsent,
    );
  }

  /// Financial commands are visible to get_opening_status.
  /// Catalog rows are not, so absence there must not be read as proof.
  Future<StatusResult> _status(
    String userId,
    PendingFinancialCommand command,
  ) async {
    try {
      if (catalogCommandKinds.contains(command.kind)) {
        return await gateway.catalogStatus(
          callerUserId: userId,
          idempotencyKey: command.key,
        );
      }
      return await statusGateway.status(
        callerUserId: userId,
        idempotencyKey: command.key,
      );
    } catch (_) {
      return const StatusUnknown();
    }
  }
}

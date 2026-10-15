import 'dart:convert';
import '../../daily_ledger/application/pending_financial_command.dart';
import 'debt_due_contract.dart';
import 'debt_due_gateway.dart';

final class DebtDueOutcome {
  const DebtDueOutcome({this.receipt, this.pending, this.error});
  final DebtDueReceipt? receipt;
  final PendingFinancialCommand? pending;
  final String? error;
}

final class DebtDueFlow {
  const DebtDueFlow(this.gateway, this.store);
  final DebtDueGateway gateway;
  final FinancialCommandLocker store;
  Future<DebtDueOutcome> submit(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload, {
    required bool canWrite,
  }) async {
    if (!canWrite) return const DebtDueOutcome(error: 'shop_not_active');
    final session = gateway.dueSession(user);
    if (session == null) return const DebtDueOutcome(error: 'session_expired');
    final command = PendingFinancialCommand(
      key: key,
      kind: debtDueKind,
      body: {
        'p_idempotency_key': key,
        'p_payload': jsonDecode(jsonEncode(payload)),
      },
    );
    if (!matchesDebtDueEnvelope(key, command.kind, command.body)) {
      return const DebtDueOutcome(error: 'invalid_input');
    }
    try {
      await store.save(user, shop, command);
    } catch (_) {
      return const DebtDueOutcome(error: 'other_pending');
    }
    if (gateway.dueSession(user) != session) {
      return DebtDueOutcome(pending: command, error: 'discarded');
    }
    return reconcile(
      user,
      shop,
      command,
      first: true,
      retry: true,
      canWrite: canWrite,
    );
  }

  Future<DebtDueOutcome> reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    bool first = false,
    bool retry = false,
    required bool canWrite,
  }) async {
    if (!matchesDebtDueEnvelope(command.key, command.kind, command.body)) {
      return DebtDueOutcome(pending: command, error: 'invalid_input');
    }
    final session = gateway.dueSession(user);
    if (session == null) {
      return DebtDueOutcome(pending: command, error: 'session_expired');
    }
    DebtDueTransport t;
    var definiteSendRejection = false;
    try {
      t = first
          ? await gateway.sendDue(userId: user, shopId: shop, command: command)
          : await gateway.dueStatus(
              userId: user,
              shopId: shop,
              command: command,
            );
      if (gateway.dueSession(user) != session) {
        return DebtDueOutcome(pending: command, error: 'discarded');
      }
      definiteSendRejection = first && t.error != null;
      if (first && t.receipt == null && t.error == null) {
        t = await gateway.dueStatus(
          userId: user,
          shopId: shop,
          command: command,
        );
        if (gateway.dueSession(user) != session) {
          return DebtDueOutcome(pending: command, error: 'discarded');
        }
        definiteSendRejection = false;
      }
      if (t.absent && retry && !first && canWrite) {
        t = await gateway.sendDue(userId: user, shopId: shop, command: command);
        definiteSendRejection = t.error != null;
      }
    } catch (_) {
      return DebtDueOutcome(pending: command);
    }
    if (gateway.dueSession(user) != session) {
      return DebtDueOutcome(pending: command, error: 'discarded');
    }
    final receipt = t.receipt;
    final p = Map<String, Object?>.from(command.body['p_payload'] as Map);
    if (receipt != null &&
        (receipt.shopId != shop ||
            receipt.actorId != user ||
            receipt.key != command.key ||
            receipt.sourceId != p['source_id'] ||
            receipt.sourceKind != p['source_kind'] ||
            receipt.version !=
                BigInt.parse(p['expected_due_version'] as String) +
                    BigInt.one ||
            receipt.date?.wire != p['due_date'] ||
            canonicalDueJson(receipt.payload) != canonicalDueJson(p))) {
      return DebtDueOutcome(pending: command);
    }
    // Reconciliation errors never prove rejection of the original mutation.
    if (receipt != null ||
        definiteSendRejection &&
            t.error != null &&
            !const {
              'discarded',
              'session_expired',
              'unauthenticated',
              'forbidden',
              'shop_unavailable',
              'payload_mismatch',
            }.contains(t.error)) {
      try {
        await store.clear(user, shop, command.key);
      } catch (_) {
        return DebtDueOutcome(
          receipt: receipt,
          pending: command,
          error: 'storage',
        );
      }
      return DebtDueOutcome(receipt: receipt, error: t.error);
    }
    return DebtDueOutcome(pending: command, error: t.error);
  }
}

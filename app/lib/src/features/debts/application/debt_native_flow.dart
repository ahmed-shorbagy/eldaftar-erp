import 'dart:convert';
import '../../daily_ledger/application/pending_financial_command.dart';
import 'debt_native_contract.dart';
import 'debt_due_contract.dart';
import 'debt_native_gateway.dart';

final class DebtNativeOutcome {
  const DebtNativeOutcome({this.receipt, this.pending, this.error});
  final DebtNativeReceipt? receipt;
  final PendingFinancialCommand? pending;
  final String? error;
}

final class DebtNativeFlow {
  const DebtNativeFlow(this.gateway, this.store);
  final DebtNativeGateway gateway;
  final FinancialCommandLocker store;
  Future<DebtNativeOutcome> submit(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload, {
    required bool canWrite,
  }) async {
    if (!canWrite) return const DebtNativeOutcome(error: 'shop_not_active');
    final session = gateway.nativeSession(user);
    if (session == null) {
      return const DebtNativeOutcome(error: 'session_expired');
    }
    final command = PendingFinancialCommand(
      key: key,
      kind: debtNativeKind,
      body: {
        'p_idempotency_key': key,
        'p_payload': jsonDecode(jsonEncode(payload)),
      },
    );
    if (!matchesDebtNativeEnvelope(key, command.kind, command.body)) {
      return const DebtNativeOutcome(error: 'invalid_input');
    }
    try {
      await store.save(user, shop, command);
    } catch (_) {
      return const DebtNativeOutcome(error: 'other_pending');
    }
    if (gateway.nativeSession(user) != session) {
      return DebtNativeOutcome(pending: command, error: 'discarded');
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

  Future<DebtNativeOutcome> reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    bool first = false,
    bool retry = false,
    required bool canWrite,
  }) async {
    if (!matchesDebtNativeEnvelope(command.key, command.kind, command.body)) {
      return DebtNativeOutcome(pending: command, error: 'invalid_input');
    }
    final session = gateway.nativeSession(user);
    if (session == null) {
      return DebtNativeOutcome(pending: command, error: 'session_expired');
    }
    DebtNativeTransport t;
    var definiteSendRejection = false;
    try {
      t = first
          ? await gateway.sendNative(
              userId: user,
              shopId: shop,
              command: command,
            )
          : await gateway.nativeStatus(
              userId: user,
              shopId: shop,
              command: command,
            );
      if (gateway.nativeSession(user) != session) {
        return DebtNativeOutcome(pending: command, error: 'discarded');
      }
      definiteSendRejection = first && t.error != null;
      if (first && t.receipt == null && t.error == null) {
        t = await gateway.nativeStatus(
          userId: user,
          shopId: shop,
          command: command,
        );
        if (gateway.nativeSession(user) != session) {
          return DebtNativeOutcome(pending: command, error: 'discarded');
        }
        definiteSendRejection = false;
      }
      if (t.absent && retry && !first && canWrite) {
        t = await gateway.sendNative(
          userId: user,
          shopId: shop,
          command: command,
        );
        definiteSendRejection = t.error != null;
      }
    } catch (_) {
      return DebtNativeOutcome(pending: command);
    }
    if (gateway.nativeSession(user) != session) {
      return DebtNativeOutcome(pending: command, error: 'discarded');
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
                BigInt.parse(p['expected_native_version'] as String) +
                    BigInt.one ||
            receipt.time != p['reminder_time'] ||
            canonicalDueJson(receipt.payload) != canonicalDueJson(p))) {
      return DebtNativeOutcome(pending: command);
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
        return DebtNativeOutcome(
          receipt: receipt,
          pending: command,
          error: 'storage',
        );
      }
      return DebtNativeOutcome(receipt: receipt, error: t.error);
    }
    return DebtNativeOutcome(pending: command, error: t.error);
  }
}

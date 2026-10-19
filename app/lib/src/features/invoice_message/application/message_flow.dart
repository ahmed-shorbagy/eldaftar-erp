import 'dart:convert';
import '../../daily_ledger/application/pending_financial_command.dart';
import 'message_contract.dart';
import 'message_gateway.dart';

final class MessageOutcome {
  const MessageOutcome({this.receipt, this.pending, this.error});
  final MessageReceipt? receipt;
  final PendingFinancialCommand? pending;
  final String? error;
}

/// Durable original-envelope save; status never invents a replacement command.
final class InvoiceMessageFlow {
  const InvoiceMessageFlow(this.gateway, this.store);
  final InvoiceMessageGateway gateway;
  final FinancialCommandLocker store;
  Future<MessageOutcome> submit(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload, {
    required bool canWrite,
  }) async {
    if (!canWrite) return const MessageOutcome(error: 'shop_not_active');
    final session = gateway.messageSession(user);
    if (session == null) return const MessageOutcome(error: 'session_expired');
    final command = PendingFinancialCommand(
      key: key,
      kind: invoiceMessageKind,
      body: {
        'p_idempotency_key': key,
        'p_payload': jsonDecode(jsonEncode(payload)),
      },
    );
    if (!matchesInvoiceMessageEnvelope(key, command.kind, command.body)) {
      return const MessageOutcome(error: 'invalid_input');
    }
    try {
      await store.save(user, shop, command);
    } catch (_) {
      return const MessageOutcome(error: 'other_pending');
    }
    if (gateway.messageSession(user) != session) {
      return MessageOutcome(pending: command, error: 'discarded');
    }
    return _run(
      user,
      shop,
      command,
      first: true,
      retry: true,
      canWrite: canWrite,
    );
  }

  Future<MessageOutcome> reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    required bool canWrite,
    bool retry = false,
  }) =>
      _run(user, shop, command, first: false, retry: retry, canWrite: canWrite);

  Future<MessageOutcome> _run(
    String user,
    String shop,
    PendingFinancialCommand command, {
    required bool first,
    required bool retry,
    required bool canWrite,
  }) async {
    if (!matchesInvoiceMessageEnvelope(
      command.key,
      command.kind,
      command.body,
    )) {
      return MessageOutcome(pending: command, error: 'invalid_input');
    }
    final session = gateway.messageSession(user);
    if (session == null) {
      return MessageOutcome(pending: command, error: 'session_expired');
    }
    bool alive() => gateway.messageSession(user) == session;
    MessageTransport reply;
    var rejected = false;
    try {
      reply = first
          ? await gateway.sendMessage(user, shop, command.body)
          : await gateway.messageStatus(user, shop, command.body);
      if (!alive()) return MessageOutcome(pending: command, error: 'discarded');
      rejected = first && reply.error != null;
      if (first && reply.receipt == null && reply.error == null) {
        reply = await gateway.messageStatus(user, shop, command.body);
        rejected = false;
      }
      if (!alive()) return MessageOutcome(pending: command, error: 'discarded');
      if (!first && reply.absent && retry && canWrite) {
        reply = await gateway.sendMessage(user, shop, command.body);
        rejected = reply.error != null;
      }
    } catch (_) {
      return MessageOutcome(pending: command);
    }
    if (!alive()) return MessageOutcome(pending: command, error: 'discarded');
    final receipt = reply.receipt;
    final payload = command.body['p_payload'] as Map;
    if (receipt != null &&
        (receipt.shop != shop ||
            receipt.actor != user ||
            receipt.key != command.key ||
            receipt.revision !=
                BigInt.parse(payload['expected_revision'] as String).toInt() +
                    1 ||
            canonicalMessageJson(receipt.payload) !=
                canonicalMessageJson(payload))) {
      return MessageOutcome(pending: command);
    }
    if (receipt != null ||
        rejected &&
            const {
              'invalid_input',
              'stale_message',
              'shop_not_active',
            }.contains(reply.error)) {
      try {
        await store.clear(user, shop, command.key);
      } catch (_) {
        return MessageOutcome(
          receipt: receipt,
          pending: command,
          error: 'storage',
        );
      }
      return MessageOutcome(receipt: receipt, error: reply.error);
    }
    return MessageOutcome(pending: command, error: reply.error);
  }
}

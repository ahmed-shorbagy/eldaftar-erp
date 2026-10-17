import 'dart:convert';

import '../../daily_ledger/application/pending_financial_command.dart';
import 'invoice_appearance_contract.dart';
import 'invoice_appearance_gateway.dart';

final class InvoiceCommandOutcome {
  const InvoiceCommandOutcome({this.receipt, this.pending, this.error});
  final AppearanceReceipt? receipt;
  final PendingFinancialCommand? pending;
  final String? error;
}

final class InvoiceAppearanceFlow {
  const InvoiceAppearanceFlow(this.gateway, this.store);
  final InvoiceAppearanceGateway gateway;
  final FinancialCommandLocker store;

  Future<InvoiceCommandOutcome> submitAppearance(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload, {
    required bool canWrite,
  }) => _submit(
    user,
    shop,
    key,
    invoiceAppearanceKind,
    payload,
    canWrite: canWrite,
    matches: matchesInvoiceAppearanceEnvelope,
    send: gateway.sendAppearance,
    status: gateway.appearanceStatus,
  );

  Future<InvoiceCommandOutcome> submitPresentation(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload, {
    required bool canWrite,
  }) => _submit(
    user,
    shop,
    key,
    invoicePresentationKind,
    payload,
    canWrite: canWrite,
    matches: matchesInvoicePresentationEnvelope,
    send: gateway.sendPresentation,
    status: gateway.presentationStatus,
  );

  Future<InvoiceCommandOutcome> reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    bool retry = false,
    required bool canWrite,
  }) {
    final appearance = command.kind == invoiceAppearanceKind;
    if (!appearance && command.kind != invoicePresentationKind) {
      return Future.value(
        InvoiceCommandOutcome(pending: command, error: 'invalid_input'),
      );
    }
    return _reconcile(
      user,
      shop,
      command,
      first: false,
      retry: retry,
      canWrite: canWrite,
      matches: appearance
          ? matchesInvoiceAppearanceEnvelope
          : matchesInvoicePresentationEnvelope,
      send: appearance ? gateway.sendAppearance : gateway.sendPresentation,
      status: appearance
          ? gateway.appearanceStatus
          : gateway.presentationStatus,
    );
  }

  Future<InvoiceCommandOutcome> _submit(
    String user,
    String shop,
    String key,
    String kind,
    Map<String, Object?> payload, {
    required bool canWrite,
    required bool Function(String, String, Map<String, Object?>) matches,
    required Future<AppearanceTransport> Function({
      required String userId,
      required String shopId,
      required String key,
      required Map<String, Object?> body,
    })
    send,
    required Future<AppearanceTransport> Function({
      required String userId,
      required String shopId,
      required String key,
      required Map<String, Object?> body,
    })
    status,
  }) async {
    if (!canWrite) {
      return const InvoiceCommandOutcome(error: 'shop_not_active');
    }
    final session = gateway.appearanceSession(user);
    if (session == null) {
      return const InvoiceCommandOutcome(error: 'session_expired');
    }
    final command = PendingFinancialCommand(
      key: key,
      kind: kind,
      body: {
        'p_idempotency_key': key,
        'p_payload': jsonDecode(jsonEncode(payload)),
      },
    );
    if (!matches(key, command.kind, command.body)) {
      return const InvoiceCommandOutcome(error: 'invalid_input');
    }
    try {
      await store.save(user, shop, command);
    } catch (_) {
      return const InvoiceCommandOutcome(error: 'other_pending');
    }
    if (gateway.appearanceSession(user) != session) {
      return InvoiceCommandOutcome(pending: command, error: 'discarded');
    }
    return _reconcile(
      user,
      shop,
      command,
      first: true,
      retry: true,
      canWrite: canWrite,
      matches: matches,
      send: send,
      status: status,
    );
  }

  Future<InvoiceCommandOutcome> _reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    required bool first,
    required bool retry,
    required bool canWrite,
    required bool Function(String, String, Map<String, Object?>) matches,
    required Future<AppearanceTransport> Function({
      required String userId,
      required String shopId,
      required String key,
      required Map<String, Object?> body,
    })
    send,
    required Future<AppearanceTransport> Function({
      required String userId,
      required String shopId,
      required String key,
      required Map<String, Object?> body,
    })
    status,
  }) async {
    if (!matches(command.key, command.kind, command.body)) {
      return InvoiceCommandOutcome(pending: command, error: 'invalid_input');
    }
    final session = gateway.appearanceSession(user);
    if (session == null) {
      return InvoiceCommandOutcome(pending: command, error: 'session_expired');
    }
    AppearanceTransport transport;
    var definiteSendRejection = false;
    try {
      transport = first
          ? await send(
              userId: user,
              shopId: shop,
              key: command.key,
              body: command.body,
            )
          : await status(
              userId: user,
              shopId: shop,
              key: command.key,
              body: command.body,
            );
      if (gateway.appearanceSession(user) != session) {
        return InvoiceCommandOutcome(pending: command, error: 'discarded');
      }
      definiteSendRejection = first && transport.error != null;
      if (first && transport.receipt == null && transport.error == null) {
        transport = await status(
          userId: user,
          shopId: shop,
          key: command.key,
          body: command.body,
        );
        definiteSendRejection = false;
      }
      if (transport.absent && retry && !first && canWrite) {
        transport = await send(
          userId: user,
          shopId: shop,
          key: command.key,
          body: command.body,
        );
        definiteSendRejection = transport.error != null;
      }
    } catch (_) {
      return InvoiceCommandOutcome(pending: command);
    }
    if (gateway.appearanceSession(user) != session) {
      return InvoiceCommandOutcome(pending: command, error: 'discarded');
    }
    final receipt = transport.receipt;
    final payload = Map<String, Object?>.from(command.body['p_payload'] as Map);
    if (receipt != null &&
        !_receiptMatches(receipt, shop, user, command, payload)) {
      return InvoiceCommandOutcome(pending: command);
    }
    if (receipt != null ||
        definiteSendRejection &&
            transport.error != null &&
            !const {
              'discarded',
              'session_expired',
              'unauthenticated',
              'forbidden',
              'shop_unavailable',
              'payload_mismatch',
            }.contains(transport.error)) {
      try {
        await store.clear(user, shop, command.key);
      } catch (_) {
        return InvoiceCommandOutcome(
          receipt: receipt,
          pending: command,
          error: 'storage',
        );
      }
      return InvoiceCommandOutcome(receipt: receipt, error: transport.error);
    }
    return InvoiceCommandOutcome(pending: command, error: transport.error);
  }

  bool _receiptMatches(
    AppearanceReceipt receipt,
    String shop,
    String user,
    PendingFinancialCommand command,
    Map<String, Object?> payload,
  ) {
    if (receipt.shopId != shop ||
        receipt.actorId != user ||
        receipt.key != command.key ||
        receipt.kind != command.kind ||
        canonicalInvoiceJson(receipt.payload) !=
            canonicalInvoiceJson(payload)) {
      return false;
    }
    if (command.kind == invoiceAppearanceKind) {
      final expected = BigInt.parse(payload['expected_revision'] as String);
      return receipt.revision == expected.toInt() + 1;
    }
    final edition = BigInt.parse(payload['expected_latest_edition'] as String);
    final appearance = BigInt.parse(
      payload['expected_appearance_revision'] as String,
    );
    return receipt.edition == edition.toInt() + 1 &&
        receipt.operationId == payload['operation_id'] &&
        receipt.contentSha256 == payload['expected_content_sha256'] &&
        receipt.appearanceRevision == appearance.toInt();
  }
}

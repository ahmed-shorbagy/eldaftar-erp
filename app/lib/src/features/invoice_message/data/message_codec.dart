import 'dart:convert';
import '../../daily_ledger/application/idempotency_key.dart';
import '../application/message_contract.dart';
import '../application/message_gateway.dart';
import '../domain/message_template.dart';

Map<String, Object?> _object(Object? raw) {
  if (raw is! Map) throw const FormatException('invoice_message');
  return Map<String, Object?>.from(raw);
}

int _revision(Object? raw) {
  if (!messageRevision(raw)) throw const FormatException('invoice_message');
  return int.parse(raw as String);
}

MessageProfile parseMessageProfile(Object? raw, String shop) {
  final row = _object(raw);
  if (row['version'] != 1 ||
      row['shop_id'] != shop ||
      row['can_write'] is! bool ||
      row['time_zone'] is! String ||
      (row['time_zone'] as String).isEmpty ||
      (row['template'] != null && row['template'] is! String)) {
    throw const FormatException('invoice_message');
  }
  final revision = _revision(row['revision']);
  final template = row['template'] as String?;
  if (MessageTemplate.parse(template).custom != template ||
      revision == 0 && template != null) {
    throw const FormatException('invoice_message');
  }
  final at = row['created_at'];
  final local = row['created_at_shop'];
  if (revision > 0 &&
      (at is! String ||
          local is! String ||
          DateTime.tryParse(at)?.isUtc != true)) {
    throw const FormatException('invoice_message');
  }
  return MessageProfile(
    shop: shop,
    revision: revision,
    template: template,
    canWrite: row['can_write'] as bool,
    zone: row['time_zone'] as String,
    atUtc: at as String?,
    atShop: local as String?,
  );
}

MessageReview parseMessageReview(Object? raw) {
  final row = _object(raw);
  if (!const {'ready', 'stale', 'expired'}.contains(row['status']) ||
      row['can_write'] is! bool) {
    throw const FormatException('invoice_message');
  }
  return MessageReview(
    row['status'] as String,
    _revision(row['current_revision']),
    row['can_write'] as bool,
  );
}

MessageReceipt parseMessageReceipt(Object? raw) {
  final row = _object(raw);
  if (row['version'] != 1 ||
      row['kind'] != invoiceMessageKind ||
      row['shop_id'] is! String ||
      !isUuid(row['shop_id'] as String) ||
      row['key'] is! String ||
      !isUuid(row['key'] as String) ||
      row['actor_user_id'] is! String ||
      !isUuid(row['actor_user_id'] as String) ||
      row['at'] is! String ||
      DateTime.tryParse(row['at'] as String)?.isUtc != true ||
      row['replayed'] is! bool ||
      row['cash_piastres'] != '0' ||
      row['gold_milligrams'] != '0' ||
      row['stock_milligrams'] != '0' ||
      row['invoice_effect'] != false ||
      row['dispatch_effect'] != false) {
    throw const FormatException('invoice_message');
  }
  final payload = _object(row['payload']);
  if (!matchesInvoiceMessageEnvelope(row['key'] as String, invoiceMessageKind, {
    'p_idempotency_key': row['key'],
    'p_payload': payload,
  })) {
    throw const FormatException('invoice_message');
  }
  return MessageReceipt(
    shop: row['shop_id'] as String,
    key: row['key'] as String,
    actor: row['actor_user_id'] as String,
    payload: payload,
    revision: _revision(row['revision']),
    at: row['at'] as String,
  );
}

MessageTransport parseMessageStatus(Object? raw) {
  final row = _object(raw);
  if (row['status'] == 'absent') return const MessageTransport(absent: true);
  if (row['status'] != 'completed') {
    throw const FormatException('invoice_message');
  }
  return MessageTransport(receipt: parseMessageReceipt(row['result']));
}

MessageSource parseMessageSource(Object? raw, String shop, String operation) {
  final row = _object(raw);
  if (row['version'] != 1 ||
      row['shop_id'] != shop ||
      row['operation_id'] != operation ||
      row['content_sha256'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['content_sha256'] as String)) {
    throw const FormatException('invoice_message');
  }
  final profile = parseMessageProfile(row['message'], shop);
  if (profile.zone != row['time_zone']) {
    throw const FormatException('invoice_message');
  }
  // Deep detached immutable facts; exclude unrelated metadata from freshness.
  final facts = <String, Object?>{
    for (final key in [
      'operation_id',
      'kind',
      'shop_sequence',
      'shop_name',
      'time_zone',
      'occurred_at',
      'occurred_at_shop',
      'payload',
      'content_sha256',
    ])
      key: row[key],
  };
  messageValues(facts);
  return MessageSource(
    profile,
    Map.unmodifiable(jsonDecode(jsonEncode(facts)) as Map<String, dynamic>),
  );
}

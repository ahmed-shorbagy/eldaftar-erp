import 'dart:convert';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../domain/message_template.dart';

const invoiceMessageKind = 'invoice_message';
bool messageRevision(Object? raw) =>
    raw is String &&
    RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(raw) &&
    PostgresInteger.fits(BigInt.parse(raw));

Map<String, Object?> messagePayload(int revision, String? input) => {
  'version': 1,
  'kind': invoiceMessageKind,
  'expected_revision': '$revision',
  'template': MessageTemplate.parse(input).custom,
};

bool matchesInvoiceMessageEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != invoiceMessageKind ||
      !isUuid(key) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key) {
    return false;
  }
  final payload = body['p_payload'];
  if (payload is! Map ||
      payload.length != 4 ||
      payload['version'] != 1 ||
      payload['kind'] != invoiceMessageKind ||
      !messageRevision(payload['expected_revision']) ||
      (payload['template'] != null && payload['template'] is! String)) {
    return false;
  }
  try {
    MessageTemplate.parse(payload['template'] as String?);
    return true;
  } on MessageValidation {
    return false;
  }
}

String canonicalMessageJson(Object? value) {
  Object? sort(Object? node) {
    if (node is Map) {
      final keys = node.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(node[key])};
    }
    if (node is List) return node.map(sort).toList();
    return node;
  }

  return jsonEncode(sort(value));
}

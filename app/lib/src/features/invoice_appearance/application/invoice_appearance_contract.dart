import 'dart:convert';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../domain/appearance_rules.dart';

const invoiceAppearanceKind = 'invoice_appearance';
const invoicePresentationKind = 'invoice_presentation';

const invoiceLogoBucket = 'eldafttar-private-invoice-logos';

bool matchesInvoiceAppearanceEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != invoiceAppearanceKind ||
      !isUuid(key) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key) {
    return false;
  }
  final raw = body['p_payload'];
  if (raw is! Map) return false;
  final payload = Map<String, Object?>.from(raw);
  if (payload.length != 8 ||
      payload['version'] != 1 ||
      payload['kind'] != invoiceAppearanceKind ||
      payload['template'] is! String ||
      InvoiceTemplate.parse(payload['template']) == null ||
      payload['accent'] is! String ||
      InvoiceAccent.parse(payload['accent']) == null ||
      !_revision(payload['expected_revision']) ||
      !_optionalAppearanceText(
        payload['slogan'],
        invoiceSloganMax,
        invoiceSloganMax,
      ) ||
      !_optionalAppearanceText(
        payload['address'],
        invoiceAddressMax,
        invoiceAddressMaxLines,
      )) {
    return false;
  }
  final logo = payload['logo_asset_id'];
  return logo == null || (logo is String && isUuid(logo));
}

bool matchesInvoicePresentationEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != invoicePresentationKind ||
      !isUuid(key) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key) {
    return false;
  }
  final raw = body['p_payload'];
  if (raw is! Map) return false;
  final payload = Map<String, Object?>.from(raw);
  final hash = payload['expected_content_sha256'];
  final operation = payload['operation_id'];
  return payload.length == 6 &&
      payload['version'] == 1 &&
      payload['kind'] == invoicePresentationKind &&
      operation is String &&
      isUuid(operation) &&
      hash is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) &&
      _revision(payload['expected_appearance_revision']) &&
      _revision(payload['expected_latest_edition']);
}

bool _revision(Object? value) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value)) {
    return false;
  }
  return PostgresInteger.fits(BigInt.parse(value));
}

bool _optionalAppearanceText(Object? value, int maxChars, int maxLines) {
  if (value == null) return true;
  try {
    normalizeInvoiceText(value, maxChars: maxChars, maxLines: maxLines);
    return true;
  } on FormatException {
    return false;
  }
}

String canonicalInvoiceJson(Object? value) {
  Object? sorted(Object? node) {
    if (node is Map) {
      final keys = node.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: sorted(node[key])};
    }
    if (node is List) return node.map(sorted).toList();
    return node;
  }

  return jsonEncode(sorted(value));
}

Map<String, Object?> appearanceCommandPayload({
  required int expectedRevision,
  required InvoiceTemplate template,
  required InvoiceAccent accent,
  String? slogan,
  String? address,
  String? logoAssetId,
}) => {
  'version': 1,
  'kind': invoiceAppearanceKind,
  'expected_revision': '$expectedRevision',
  'slogan': normalizeSlogan(slogan),
  'address': normalizeAddress(address),
  'template': template.wire,
  'accent': accent.wire,
  'logo_asset_id': logoAssetId,
};

Map<String, Object?> presentationCommandPayload({
  required String operationId,
  required String contentSha256,
  required int expectedAppearanceRevision,
  required int expectedLatestEdition,
}) => {
  'version': 1,
  'kind': invoicePresentationKind,
  'operation_id': operationId,
  'expected_content_sha256': contentSha256,
  'expected_appearance_revision': '$expectedAppearanceRevision',
  'expected_latest_edition': '$expectedLatestEdition',
};

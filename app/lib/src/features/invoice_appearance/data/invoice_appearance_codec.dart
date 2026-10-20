import 'dart:convert';
import 'dart:typed_data';

import '../../daily_ledger/application/idempotency_key.dart';
import '../application/invoice_appearance_gateway.dart';
import '../domain/appearance_rules.dart';

InvoiceAppearanceSnapshot parseInvoiceAppearance(
  Object? raw, {
  required String shopId,
}) {
  final json = _object(raw);
  _version(json);
  if (json['shop_id'] != shopId) {
    throw const FormatException('invoice_appearance');
  }
  return InvoiceAppearanceSnapshot(
    shopId: shopId,
    value: _appearance(json, revisionKey: 'revision'),
    canWrite: _bool(json['can_write']),
    timeZone: _text(json['time_zone']),
  );
}

InvoiceAppearanceReview parseInvoiceAppearanceReview(Object? raw) {
  final json = _object(raw);
  final status = json['status'];
  if (status is! String ||
      !const {'ready', 'stale', 'expired'}.contains(status)) {
    throw const FormatException('invoice_appearance');
  }
  Map<String, Object?>? normalized;
  if (status == 'ready') {
    final fields = json['normalized'];
    if (fields is! Map) throw const FormatException('invoice_appearance');
    normalized = Map<String, Object?>.from(fields);
  }
  return InvoiceAppearanceReview(
    status: status,
    currentRevision: _revision(json['current_revision']),
    canWrite: _bool(json['can_write']),
    normalized: normalized,
  );
}

AppearanceTransport parseAppearanceStatus(Object? raw, {required String kind}) {
  final json = _object(raw);
  final status = json['status'];
  if (status == 'absent') return const AppearanceTransport(absent: true);
  if (status != 'completed') throw const FormatException('invoice_appearance');
  return AppearanceTransport(
    receipt: parseAppearanceReceipt(json['result'], kind: kind),
  );
}

AppearanceReceipt parseAppearanceReceipt(Object? raw, {required String kind}) {
  final json = _object(raw);
  _version(json);
  if (json['kind'] != kind ||
      json['shop_id'] is! String ||
      !isUuid(json['shop_id'] as String) ||
      json['key'] is! String ||
      !isUuid(json['key'] as String) ||
      json['actor_user_id'] is! String ||
      !isUuid(json['actor_user_id'] as String) ||
      json['at'] is! String ||
      json['payload'] is! Map ||
      json['replayed'] is! bool ||
      json['cash_piastres'] != '0' ||
      json['gold_milligrams'] != '0' ||
      json['stock_milligrams'] != '0' ||
      json['invoice_effect'] != false ||
      json['dispatch_effect'] != false) {
    throw const FormatException('invoice_appearance');
  }
  return AppearanceReceipt(
    shopId: json['shop_id'] as String,
    key: json['key'] as String,
    kind: kind,
    payload: Map<String, Object?>.from(json['payload'] as Map),
    actorId: json['actor_user_id'] as String,
    atUtc: json['at'] as String,
    replayed: json['replayed'] as bool,
    revision: kind == 'invoice_appearance' ? _revision(json['revision']) : null,
    edition: kind == 'invoice_presentation' ? _revision(json['edition']) : null,
    operationId: json['operation_id'] as String?,
    contentSha256: json['content_sha256'] as String?,
    appearanceRevision: json['appearance_revision'] == null
        ? null
        : _revision(json['appearance_revision']),
  );
}

LogoConfirmation parseLogoConfirmation(
  Object? raw, {
  required String shopId,
  required String sha256,
}) {
  final json = _object(raw);
  _version(json);
  if (json['shop_id'] != shopId ||
      json['sha256'] != sha256 ||
      json['confirmed'] != true ||
      json['asset_id'] is! String ||
      !isUuid(json['asset_id'] as String) ||
      json['mime'] is! String ||
      json['cash_piastres'] != '0' ||
      json['gold_milligrams'] != '0' ||
      json['stock_milligrams'] != '0' ||
      json['invoice_effect'] != false ||
      json['dispatch_effect'] != false) {
    throw const FormatException('invoice_appearance');
  }
  final width = json['width'];
  final height = json['height'];
  if (width is! int || height is! int || width < 1 || height < 1) {
    throw const FormatException('invoice_appearance');
  }
  return LogoConfirmation(
    shopId: shopId,
    assetId: json['asset_id'] as String,
    sha256: sha256,
    mime: json['mime'] as String,
    width: width,
    height: height,
  );
}

InvoiceBrandSource parseInvoiceBrandSource(
  Object? raw, {
  required String shopId,
  required String operationId,
}) {
  final json = _object(raw);
  _version(json);
  final appearance = json['appearance'];
  if (json['shop_id'] != null && json['shop_id'] != shopId) {
    throw const FormatException('invoice_appearance');
  }
  if (json['operation_id'] != operationId ||
      appearance is! Map ||
      json['payload'] is! Map ||
      json['content_sha256'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(json['content_sha256'] as String)) {
    throw const FormatException('invoice_appearance');
  }
  return InvoiceBrandSource(
    shopId: shopId,
    operationId: operationId,
    kind: _kind(json['kind']),
    shopName: _text(json['shop_name']),
    shopSequence: _text(json['shop_sequence']),
    timeZone: _text(json['time_zone']),
    occurredAtUtc: _text(json['occurred_at']),
    occurredAtShop: _text(json['occurred_at_shop']),
    payload: Map<String, Object?>.from(json['payload'] as Map),
    contentSha256: json['content_sha256'] as String,
    appearance: _appearance(
      Map<String, Object?>.from(appearance),
      revisionKey: 'revision',
    ),
    latestEdition: _revision(json['latest_edition']),
    canWrite: _bool(json['can_write']),
  );
}

InvoicePresentationList parseInvoicePresentationList(
  Object? raw, {
  required String shopId,
  required String operationId,
}) {
  final json = _object(raw);
  _version(json);
  final items = json['items'];
  if (json['shop_id'] != shopId ||
      json['operation_id'] != operationId ||
      items is! List) {
    throw const FormatException('invoice_appearance');
  }
  return InvoicePresentationList(
    shopId: shopId,
    operationId: operationId,
    canWrite: _bool(json['can_write']),
    items: [
      for (final item in items)
        if (item is Map)
          InvoicePresentationSummary(
            edition: _revision(item['edition']),
            contentSha256: _hash(item['content_sha256']),
            appearanceRevision: _revision(item['appearance_revision']),
            template: _template(item['template']).wire,
            accent: _accent(item['accent']).wire,
            renderVersion:
                const [1, 2].contains(item['render_version']) &&
                    item['render_version'] is int
                ? item['render_version'] as int
                : throw const FormatException('invoice_appearance'),
            createdAtUtc: _text(item['created_at']),
            createdAtShop: _text(item['created_at_shop']),
            hasLogo: _bool(item['has_logo']),
          )
        else
          throw const FormatException('invoice_appearance'),
    ],
  );
}

InvoicePresentationCopy parseInvoicePresentationCopy(
  Object? raw, {
  required String shopId,
  required String operationId,
  required int edition,
}) {
  final json = _object(raw);
  _version(json);
  if (json['shop_id'] != shopId ||
      json['operation_id'] != operationId ||
      _revision(json['edition']) != edition ||
      json['payload'] is! Map ||
      !const [1, 2].contains(json['render_version']) ||
      json['render_version'] is! int) {
    throw const FormatException('invoice_appearance');
  }
  final logoState = json['logo_state'];
  if (logoState is! String ||
      !const {'absent', 'verified', 'unverified'}.contains(logoState)) {
    throw const FormatException('invoice_appearance');
  }
  Uint8List? bytes;
  if (logoState == 'verified') {
    final encoded = json['logo_bytes'];
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('invoice_appearance');
    }
    bytes = base64Decode(encoded);
  } else if (json['logo_bytes'] != null) {
    throw const FormatException('invoice_appearance');
  }
  final appearance = InvoiceAppearanceValue(
    revision: _revision(json['appearance_revision']),
    template: _template(json['template']),
    accent: _accent(json['accent']),
    slogan: json['slogan'] as String?,
    address: json['address'] as String?,
    logoAssetId: json['logo_asset_id'] as String?,
    logoSha256: json['logo_sha256'] as String?,
  );
  if (logoState == 'absent' && appearance.logoAssetId != null) {
    throw const FormatException('invoice_appearance');
  }
  if (logoState != 'absent' && appearance.logoAssetId == null) {
    throw const FormatException('invoice_appearance');
  }
  return InvoicePresentationCopy(
    shopId: shopId,
    operationId: operationId,
    edition: edition,
    contentSha256: _hash(json['content_sha256']),
    contentMatches: _bool(json['content_matches']),
    appearance: appearance,
    logoState: logoState,
    renderVersion: json['render_version'] as int,
    actorId: _text(json['actor_user_id']),
    createdAtUtc: _text(json['created_at']),
    createdAtShop: _text(json['created_at_shop']),
    shopName: _text(json['shop_name']),
    shopSequence: _text(json['shop_sequence']),
    kind: _kind(json['kind']),
    timeZone: _text(json['time_zone']),
    occurredAtUtc: _text(json['occurred_at']),
    occurredAtShop: _text(json['occurred_at_shop']),
    payload: Map<String, Object?>.from(json['payload'] as Map),
    canWrite: _bool(json['can_write']),
    logoBytes: bytes,
  );
}

Map<String, Object?> _object(Object? raw) {
  if (raw is! Map) throw const FormatException('invoice_appearance');
  return Map<String, Object?>.from(raw);
}

void _version(Map<String, Object?> json) {
  if (json['version'] != 1) throw const FormatException('invoice_appearance');
}

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('invoice_appearance');
  return value;
}

String _text(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('invoice_appearance');
  }
  return value;
}

String _kind(Object? value) {
  if (value != 'sale' && value != 'purchase') {
    throw const FormatException('invoice_appearance');
  }
  return value as String;
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('invoice_appearance');
  }
  return value;
}

int _revision(Object? value) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value)) {
    throw const FormatException('invoice_appearance');
  }
  return int.parse(value);
}

InvoiceTemplate _template(Object? value) =>
    InvoiceTemplate.parse(value) ??
    (throw const FormatException('invoice_appearance'));

InvoiceAccent _accent(Object? value) =>
    InvoiceAccent.parse(value) ??
    (throw const FormatException('invoice_appearance'));

InvoiceAppearanceValue _appearance(
  Map<String, Object?> json, {
  required String revisionKey,
}) => InvoiceAppearanceValue(
  revision: _revision(json[revisionKey]),
  template: _template(json['template']),
  accent: _accent(json['accent']),
  slogan: json['slogan'] as String?,
  address: json['address'] as String?,
  logoAssetId: json['logo_asset_id'] as String?,
  logoSha256: json['logo_sha256'] as String?,
);

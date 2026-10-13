import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/opening_catalog.dart';

/// Versioned debt RPCs. They are not opening-status rows.
const debtRpcs = <String, String>{
  'debt_declare': 'post_debt_declare_v1',
  'debt_settle': 'post_debt_settle_v1',
  'debt_cancel': 'post_debt_cancel_v1',
  'debt_archive': 'post_debt_archive_v1',
};

final _versionWire = RegExp(r'^[1-9][0-9]{0,18}$');
final _moneyWire = RegExp(r'^(0|[1-9][0-9]{0,18})$');

bool ownsDebtCommand(String key, String kind, Map<String, Object?> body) =>
    matchesDebtEnvelope(key, kind, body);

/// True when a stored retry body is still the original debt envelope.
bool matchesDebtEnvelope(String key, String kind, Map<String, Object?> body) {
  if (!debtRpcs.containsKey(kind) || body.length != 2) return false;
  if (body['p_idempotency_key'] != key || !isUuid(key)) return false;
  final payload = body['p_payload'];
  if (payload is! Map) return false;
  final map = Map<String, Object?>.from(payload);
  if (map['version'] != 1 || map['kind'] != kind) return false;
  return switch (kind) {
    'debt_declare' => _declare(map),
    'debt_settle' => _settle(map),
    'debt_cancel' => _cancel(map, standaloneOnly: true),
    'debt_archive' => _cancel(map, standaloneOnly: false),
    _ => false,
  };
}

bool _wire(Object? value, {bool allowZero = false}) =>
    value is String && (allowZero ? _moneyWire : _versionWire).hasMatch(value);

bool _declare(Map<String, Object?> map) {
  if (map.length != 10) return false;
  final direction = map['direction'];
  final unit = map['unit'];
  final phone = map['contact_phone'];
  final party = map['party_name'];
  final reason = map['reason'];
  final external = map['external_reference'];
  if (direction is! String ||
      !const {'shop_owes', 'owed_to_shop'}.contains(direction) ||
      unit is! String ||
      !const {'money', 'gold'}.contains(unit) ||
      party is! String ||
      party.trim().isEmpty ||
      phone is! String ||
      reason is! String ||
      reason.trim().isEmpty ||
      !_wire(map['amount'])) {
    return false;
  }
  if (external != null && external is! String) return false;
  if (unit == 'money') return map['karat'] == null;
  return map['karat'] is int &&
      ScrapKarats.allowed.contains(map['karat'] as int);
}

bool _settle(Map<String, Object?> map) {
  if (map.length != 18 ||
      !_wire(map['amount']) ||
      !_wire(map['expected_remaining'], allowZero: true) ||
      map['reason'] is! String ||
      (map['reason'] as String).trim().isEmpty ||
      !isUuid('${map['source_id']}') ||
      !isUuid('${map['settlement_reference']}') ||
      !const {
        'standalone',
        'purchase_cash_payable',
        'gold_obligation',
      }.contains(map['source_kind']) ||
      !const {'shop_owes', 'owed_to_shop'}.contains(map['direction']) ||
      !const {'money', 'gold'}.contains(map['unit']) ||
      !const {'move', 'none'}.contains(map['ledger_effect'])) {
    return false;
  }
  final source = map['source_kind'];
  final version = map['expected_version'];
  if (source == 'standalone') {
    if (!_wire(version)) return false;
  } else if (version != null || map['direction'] != 'shop_owes') {
    return false;
  }
  if (map['unit'] == 'money') {
    if (map['karat'] != null) return false;
  } else if (map['karat'] is! int ||
      !ScrapKarats.allowed.contains(map['karat'] as int)) {
    return false;
  }
  final effect = map['ledger_effect'];
  if (effect == 'none') {
    return source == 'standalone' &&
        map['expected_day_id'] == null &&
        map['expected_day_version'] == null &&
        map['tenders'] == null &&
        map['deliveries'] == null &&
        map['receipt'] == null;
  }
  if (!isUuid('${map['expected_day_id']}') ||
      !_wire(map['expected_day_version'])) {
    return false;
  }
  if (map['unit'] == 'money') {
    return map['tenders'] is List &&
        map['deliveries'] == null &&
        map['receipt'] == null;
  }
  if (map['direction'] == 'shop_owes') {
    return map['deliveries'] is List &&
        map['tenders'] == null &&
        map['receipt'] == null;
  }
  return map['receipt'] is Map &&
      map['tenders'] == null &&
      map['deliveries'] == null;
}

bool _cancel(Map<String, Object?> map, {required bool standaloneOnly}) {
  if (map.length != 7 ||
      !_wire(map['expected_remaining'], allowZero: true) ||
      map['reason'] is! String ||
      (map['reason'] as String).trim().isEmpty ||
      !isUuid('${map['source_id']}')) {
    return false;
  }
  final source = map['source_kind'];
  if (standaloneOnly) {
    return source == 'standalone' && _wire(map['expected_version']);
  }
  if (source == 'standalone') return _wire(map['expected_version']);
  return const {'purchase_cash_payable', 'gold_obligation'}.contains(source) &&
      map['expected_version'] == null;
}

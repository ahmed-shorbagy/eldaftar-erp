import '../../daily_ledger/application/idempotency_key.dart';

/// Versioned repair RPCs. Custody commands are not opening-status rows.
const repairRpcs = <String, String>{
  'repair_intake': 'post_repair_intake_v1',
  'repair_status': 'post_repair_status_v1',
  'repair_handover': 'post_repair_handover_v1',
  'repair_cancel': 'post_repair_cancel_v1',
  'repair_archive': 'post_repair_archive_v1',
};

final _versionWire = RegExp(r'^[1-9][0-9]{0,18}$');
final _moneyWire = RegExp(r'^(0|[1-9][0-9]{0,18})$');

bool ownsRepairCommand(String key, String kind, Map<String, Object?> body) =>
    matchesRepairEnvelope(key, kind, body);

/// True when a stored retry body is still the original repair envelope.
bool matchesRepairEnvelope(String key, String kind, Map<String, Object?> body) {
  if (!repairRpcs.containsKey(kind) || body.length != 2) return false;
  if (body['p_idempotency_key'] != key || !isUuid(key)) return false;
  final payload = body['p_payload'];
  if (payload is! Map) return false;
  final map = Map<String, Object?>.from(payload);
  if (map['version'] != 1 || map['kind'] != kind) return false;
  return switch (kind) {
    'repair_intake' => _intake(map),
    'repair_status' => _status(map),
    'repair_handover' => _handover(map),
    'repair_cancel' => _cancel(map),
    'repair_archive' => _archive(map),
    _ => false,
  };
}

bool _wire(Object? value, {bool allowZero = false}) =>
    value is String && (allowZero ? _moneyWire : _versionWire).hasMatch(value);

bool _intake(Map<String, Object?> map) {
  if (map.length != 10) return false;
  final phone = map['customer_phone'];
  final notes = map['intake_notes'];
  final estimate = map['estimated_fee_piastres'];
  return map['customer_name'] is String &&
      (map['customer_name'] as String).trim().isNotEmpty &&
      phone is String &&
      notes is String &&
      map['item_description'] is String &&
      map['issue'] is String &&
      _wire(map['measured_milligrams']) &&
      repairKarat(map['karat']) &&
      (estimate == null || _wire(estimate, allowZero: true));
}

bool repairKarat(Object? value) =>
    value is int && const {14, 18, 21, 22, 24}.contains(value);

bool _status(Map<String, Object?> map) =>
    map.length == 5 &&
    isUuid('${map['repair_id']}') &&
    _wire(map['expected_version']) &&
    const {'in_progress', 'ready'}.contains(map['status']);

bool _handover(Map<String, Object?> map) {
  final collected = map['collected_piastres'];
  final tenders = map['tenders'];
  if (collected is! String ||
      !_moneyWire.hasMatch(collected) ||
      tenders is! List ||
      !isUuid('${map['repair_id']}') ||
      !_wire(map['expected_version']) ||
      !_wire(map['final_fee_piastres'], allowZero: true) ||
      !const {'all', 'part', 'none'}.contains(map['collection'])) {
    return false;
  }
  final paid = BigInt.parse(collected) > BigInt.zero;
  final dayId = map['expected_day_id'];
  final dayVersion = map['expected_day_version'];
  final keys = map.length;
  if (paid) {
    if (keys != 10 ||
        dayId is! String ||
        !isUuid(dayId) ||
        !_wire(dayVersion)) {
      return false;
    }
  } else if (keys != 8 || map.containsKey('expected_day_id')) {
    return false;
  }
  return true;
}

bool _cancel(Map<String, Object?> map) =>
    map.length == 6 &&
    map['confirm_return'] == true &&
    isUuid('${map['repair_id']}') &&
    _wire(map['expected_version']) &&
    map['reason'] is String &&
    (map['reason'] as String).trim().isNotEmpty;

bool _archive(Map<String, Object?> map) =>
    map.length == 5 &&
    map['confirm_archive'] == true &&
    isUuid('${map['repair_id']}') &&
    _wire(map['expected_version']);

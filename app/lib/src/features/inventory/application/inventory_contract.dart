import '../../daily_ledger/application/idempotency_key.dart';

/// Versioned inventory and catalog RPCs from the milestone 3 migration.
const inventoryRpcs = <String, String>{
  'inventory_addition': 'post_inventory_addition_v1',
  'inventory_removal': 'post_inventory_removal_v1',
  'inventory_correction': 'post_inventory_correction_v1',
  'inventory_conversion': 'post_inventory_conversion_v1',
  'inventory_receipt': 'post_inventory_receipt_v1',
  'inventory_recognition': 'post_inventory_recognition_v1',
  'ownership_transfer': 'post_ownership_transfer_v1',
  'receipt_manual_allocation': 'post_receipt_manual_allocation_v1',
  'gold_obligation_acquisition': 'post_gold_obligation_acquisition_v1',
  'gold_obligation_settlement': 'post_gold_obligation_settlement_v1',
  'product': 'save_inventory_product_v1',
  'bullion_denomination': 'save_bullion_denomination_v1',
  'coin_type': 'save_coin_type_v1',
  'trader': 'save_trader_v1',
};

const catalogCommandKinds = <String>{
  'product',
  'bullion_denomination',
  'coin_type',
  'trader',
};

/// Sale and scrap-sale envelopes that name a lot use trade v2, not FIFO v1.
bool matchesExplicitLotSale(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != 'sale' && kind != 'scrap_sale') return false;
  if (body.length != 2 || body['p_idempotency_key'] != key) return false;
  final payload = body['p_payload'];
  if (payload is! Map) return false;
  final selections = payload['lot_selections'];
  final items = payload['items'];
  final dayId = payload['expected_day_id'];
  final version = payload['expected_day_version'];
  return payload['version'] == 2 &&
      payload['kind'] == kind &&
      payload['lot_identities'] == null &&
      selections is List &&
      items is List &&
      selections.isNotEmpty &&
      selections.length == items.length &&
      dayId is String &&
      isUuid(dayId) &&
      version is String &&
      _versionWire.hasMatch(version) &&
      version != '0';
}

bool ownsInventoryCommand(String key, String kind, Map<String, Object?> body) =>
    matchesInventoryEnvelope(key, kind, body) ||
    matchesExplicitLotSale(key, kind, body);

final _versionWire = RegExp(r'^(0|[1-9][0-9]*)$');

/// True when a stored retry body is still the original two-field envelope.
bool matchesInventoryEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (!inventoryRpcs.containsKey(kind) || body.length != 2) return false;
  if (body['p_idempotency_key'] != key) return false;
  final payload = body['p_payload'];
  if (payload is! Map) return false;
  final dayId = payload['expected_day_id'];
  final version = payload['expected_day_version'];
  return payload['kind'] == kind &&
      payload['version'] == 1 &&
      dayId is String &&
      isUuid(dayId) &&
      version is String &&
      _versionWire.hasMatch(version) &&
      version != '0';
}

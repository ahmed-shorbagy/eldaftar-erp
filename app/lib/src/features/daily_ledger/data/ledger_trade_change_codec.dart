import '../application/ledger_trade_change.dart';
import '../application/idempotency_key.dart';
import '../domain/postgres_integer.dart';
import '../domain/opening_catalog.dart';

bool _signed(Object? value) =>
    value is String &&
    RegExp(r'^(0|-?[1-9][0-9]{0,18})$').hasMatch(value) &&
    PostgresInteger.fits(BigInt.parse(value));

LedgerTradeChangeReview parseTradeChangeReview(
  Object? raw, {
  required String shopId,
  required String operationId,
  required String action,
}) {
  if (raw is! Map ||
      raw['version'] != 1 ||
      raw['shop_id'] != shopId ||
      raw['operation_id'] != operationId ||
      raw['action'] != action ||
      raw['source'] is! Map ||
      raw['effects'] is! Map) {
    throw const FormatException('change_review');
  }
  final source = Map<String, Object?>.from(raw['source'] as Map);
  if (!const {'sale', 'purchase'}.contains(source['kind']) ||
      source['payload'] is! Map ||
      (source['payload'] as Map)['kind'] != source['kind'] ||
      !const {1, 2}.contains((source['payload'] as Map)['version']) ||
      (source['payload'] as Map)['items'] is! List ||
      ((source['payload'] as Map)['tenders'] is! List &&
          !(source['kind'] == 'purchase' &&
              (source['payload'] as Map)['tenders'] == null))) {
    throw const FormatException('change_source');
  }
  final effects = Map<String, Object?>.from(raw['effects'] as Map);
  for (final key in ['cash', 'stock', 'scrap']) {
    if (effects[key] is! List) throw const FormatException('change_effect');
    final seen = <String>{};
    for (final row in effects[key] as List) {
      if (row is! Map) throw const FormatException('change_effect');
      final quantities = key == 'cash'
          ? ['delta_piastres']
          : key == 'stock'
          ? ['delta_milligrams', 'delta_count']
          : ['delta_milligrams'];
      for (final quantity in quantities) {
        final value = row[quantity];
        if (!_signed(value)) {
          throw const FormatException('change_quantity');
        }
      }
      if (key == 'cash' &&
          !const {
            'cash',
            'instant_transfer',
            'wallet',
            'card',
          }.contains(row['method'])) {
        throw const FormatException('method');
      }
      if (key != 'cash' && !const {14, 18, 21, 22, 24}.contains(row['karat'])) {
        throw const FormatException('karat');
      }
      if (key == 'stock' &&
          !const {
            'worked_jewelry',
            'bullion',
            'coin',
          }.contains(row['category'])) {
        throw const FormatException('category');
      }
      if (key == 'stock' &&
          StockCategory.byCode(
                row['category'] as String,
              )?.allowsKarat(row['karat'] as int) !=
              true) {
        throw const FormatException('category_karat');
      }
      final bucket = key == 'cash'
          ? '${row['method']}'
          : '${row['category']}:${row['karat']}';
      if (!seen.add(bucket)) throw const FormatException('duplicate_effect');
    }
  }
  final payable = effects['payable_delta_piastres'];
  if (!_signed(payable) ||
      raw['expected_day_id'] is! String ||
      !isUuid(raw['expected_day_id'] as String) ||
      raw['expected_day_version'] is! int ||
      (raw['expected_day_version'] as int) < 1 ||
      raw['source_sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['source_sha256'] as String) ||
      raw['review_token'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['review_token'] as String)) {
    throw const FormatException('change_review');
  }
  return LedgerTradeChangeReview(
    shopId: shopId,
    operationId: operationId,
    action: action,
    dayId: raw['expected_day_id'] as String,
    dayVersion: raw['expected_day_version'] as int,
    sourceHash: raw['source_sha256'] as String,
    token: raw['review_token'] as String,
    source: Map.unmodifiable(source),
    effects: Map.unmodifiable(effects),
  );
}

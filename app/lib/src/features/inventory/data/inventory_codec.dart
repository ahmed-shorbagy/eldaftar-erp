import '../../daily_ledger/application/idempotency_key.dart';
import '../application/inventory_gateway.dart';
import '../domain/inventory_models.dart';

BigInt _positive(Object? raw) {
  if (raw is! String) throw const FormatException('inventory');
  final parsed = parseSignedWire(raw);
  if (parsed is! InventoryAccepted<BigInt> || parsed.value.isNegative) {
    throw const FormatException('inventory');
  }
  return parsed.value;
}

BigInt _signed(Object? raw) {
  if (raw is! String) throw const FormatException('inventory');
  final parsed = parseSignedWire(raw);
  if (parsed is! InventoryAccepted<BigInt>) {
    throw const FormatException('inventory');
  }
  return parsed.value;
}

BigInt? _nullableCount(Object? raw) {
  if (raw == null) return null;
  return _signed(raw);
}

int _karat(Object? raw) {
  if (raw is! int || !const {14, 18, 21, 22, 24}.contains(raw)) {
    throw const FormatException('inventory');
  }
  return raw;
}

String _text(Object? raw) {
  if (raw is! String || raw.isEmpty) throw const FormatException('inventory');
  return raw;
}

String? _cursor(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || !raw.contains('|')) {
    throw const FormatException('inventory');
  }
  return raw;
}

Map<String, Object?> _map(Object? raw) {
  if (raw is! Map) throw const FormatException('inventory');
  return Map<String, Object?>.from(raw);
}

InventoryTotals parseInventoryTotals(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['buckets'] is! List) {
    throw const FormatException('inventory');
  }
  return InventoryTotals([
    for (final item in json['buckets'] as List)
      InventoryBucket(
        category: _text(_map(item)['category']),
        karat: _karat(_map(item)['karat']),
        quantities: QuantityTriple(
          availableMilligrams: _positive(_map(item)['available_milligrams']),
          pendingMilligrams: _positive(_map(item)['pending_milligrams']),
          heldMilligrams: _positive(_map(item)['held_milligrams']),
          availableCount: _nullableCount(_map(item)['available_count']),
          pendingCount: _nullableCount(_map(item)['pending_count']),
          heldCount: _nullableCount(_map(item)['held_count']),
        ),
      ),
  ]);
}

LotPage parseLotPage(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return LotPage([
    for (final item in json['items'] as List) _lot(_map(item)),
  ], _cursor(json['next_cursor']));
}

LotSnapshot _lot(Map<String, Object?> json) {
  final stock = StockClass.byCode(_text(json['stock_class']));
  final category = _text(json['category']);
  if (stock == null) throw const FormatException('inventory');
  final originalCount = _nullableCount(json['original_count']);
  final remainingCount = _nullableCount(json['remaining_count']);
  if ((category == 'scrap') != (originalCount == null) ||
      (originalCount == null) != (remainingCount == null)) {
    throw const FormatException('inventory');
  }
  final id = _text(json['lot_id']);
  if (!isUuid(id)) throw const FormatException('inventory');
  return LotSnapshot(
    id: id,
    productId: _uuid(json['product_id']),
    productName: _text(json['product_name']),
    displayName: _text(json['display_name']),
    category: category,
    karat: _karat(json['karat']),
    stockClass: stock,
    remainingMilligrams: _positive(json['remaining_milligrams']),
    remainingCount: remainingCount,
    originalMilligrams: _positive(json['original_milligrams']),
    originalCount: originalCount,
    legacyAggregate: json['legacy_aggregate'] == true,
    denominationId: _optionalUuid(json['denomination_id']),
    nominalMilligrams: _optionalPositive(json['nominal_milligrams']),
    coinTypeId: _optionalUuid(json['coin_type_id']),
    coinNominalMilligrams: _optionalPositive(json['coin_nominal_milligrams']),
    traderId: _optionalUuid(json['trader_id']),
    originOperationId: _optionalUuid(json['origin_operation_id']),
  );
}

String _uuid(Object? raw) {
  final value = _text(raw);
  if (!isUuid(value)) throw const FormatException('inventory');
  return value;
}

String? _optionalUuid(Object? raw) {
  if (raw == null) return null;
  return _uuid(raw);
}

BigInt? _optionalPositive(Object? raw) {
  if (raw == null) return null;
  return _positive(raw);
}

MovementPage parseMovementPage(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return MovementPage([
    for (final item in json['items'] as List)
      MovementLine(
        id: _uuid(_map(item)['movement_id']),
        deltaMilligrams: _signed(_map(item)['delta_milligrams']),
        deltaCount: _signed(_map(item)['delta_count']),
        movementKind: _text(_map(item)['movement_kind']),
        allocationMode: _text(_map(item)['allocation_mode']),
        operationId: _optionalUuid(_map(item)['operation_id']),
        operationKind: _map(item)['operation_kind'] as String?,
        createdAt: _text(_map(item)['created_at']),
        cursor: _text(_map(item)['cursor']),
      ),
  ], _cursor(json['next_cursor']));
}

TraderPage parseTraderPage(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return TraderPage([
    for (final item in json['items'] as List)
      TraderSummary(
        id: _uuid(_map(item)['trader_id']),
        displayName: _text(_map(item)['display_name']),
        phone: _map(item)['phone'] is String
            ? _map(item)['phone'] as String
            : '',
        active: _map(item)['active'] == true,
        createdAt: _text(_map(item)['created_at']),
        cursor: _text(_map(item)['cursor']),
      ),
  ], _cursor(json['next_cursor']));
}

TraderDetail parseTraderDetail(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['buckets'] is! List) {
    throw const FormatException('inventory');
  }
  final pending = json['pending_receipt_count'];
  return TraderDetail(
    id: _uuid(json['trader_id']),
    displayName: _text(json['display_name']),
    phone: json['phone'] is String ? json['phone'] as String : '',
    note: json['note'] is String ? json['note'] as String : '',
    active: json['active'] == true,
    createdAt: _text(json['created_at']),
    originalHeldMilligrams: _positive(json['original_held_milligrams']),
    currentHeldMilligrams: _positive(json['current_held_milligrams']),
    pendingReceiptCount: pending is int
        ? BigInt.from(pending)
        : _positive(pending),
    cashPayableRemainingPiastres: _positive(
      json['cash_payable_remaining_piastres'],
    ),
    goldRemaining: [
      for (final item in json['gold_remaining'] as List)
        TraderGoldBalance(
          karat: _karat(_map(item)['karat']),
          initialMilligrams: _positive(_map(item)['initial_milligrams']),
          remainingMilligrams: _positive(_map(item)['remaining_milligrams']),
        ),
    ],
    buckets: [
      for (final item in json['buckets'] as List)
        TraderHolding(
          category: _text(_map(item)['category']),
          karat: _karat(_map(item)['karat']),
          originalMilligrams: _positive(_map(item)['original_milligrams']),
          originalCount: _nullableCount(_map(item)['original_count']),
          currentMilligrams: _positive(_map(item)['current_milligrams']),
          currentCount: _nullableCount(_map(item)['current_count']),
          pendingReceiptCount: _map(item)['pending_receipt_count'] is int
              ? BigInt.from(_map(item)['pending_receipt_count'] as int)
              : _positive(_map(item)['pending_receipt_count']),
        ),
    ],
  );
}

TraderActivityPage parseTraderActivity(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return TraderActivityPage([
    for (final item in json['items'] as List)
      TraderActivity(
        operationId: _uuid(_map(item)['operation_id']),
        kind: _text(_map(item)['kind']),
        shopSequence: _sequence(_map(item)['shop_sequence']),
        receiptId: _optionalUuid(_map(item)['receipt_id']),
        createdAt: _text(_map(item)['created_at']),
        cursor: _text(_map(item)['cursor']),
      ),
  ], _cursor(json['next_cursor']));
}

String _sequence(Object? raw) {
  if (raw is int && raw >= 0) return raw.toString();
  if (raw is String && RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw)) return raw;
  throw const FormatException('inventory');
}

ReceiptPage parseReceiptPage(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return ReceiptPage.ready([
    for (final item in json['items'] as List) _receipt(_map(item)),
  ], _cursor(json['next_cursor']));
}

ReceiptSnapshot _receipt(Map<String, Object?> json) {
  final category = _text(json['category']);
  final count = _nullableCount(json['count']);
  final remainingCount = _nullableCount(json['remaining_count']);
  if ((category == 'scrap') != (count == null) ||
      (count == null) != (remainingCount == null)) {
    throw const FormatException('inventory');
  }
  return ReceiptSnapshot(
    id: _uuid(json['receipt_id']),
    ownerKind: _text(json['owner_kind']),
    policy: _text(json['recognition_policy']),
    traderId: _optionalUuid(json['trader_id']),
    counterpartyName: _text(json['counterparty_name']),
    productId: _uuid(json['product_id']),
    productName: _text(json['product_name']),
    lotId: _uuid(json['lot_id']),
    category: category,
    karat: _karat(json['karat']),
    remainingMilligrams: _positive(json['remaining_milligrams']),
    remainingCount: remainingCount,
  );
}

CatalogProduct parseProductRow(Map<String, Object?> json) => CatalogProduct(
  id: _uuid(json['id']),
  name: _text(json['name']),
  category: _text(json['category_code']),
  karat: _karat(json['karat']),
  createdAt: _text(json['created_at']),
);

CatalogDenomination parseDenominationRow(Map<String, Object?> json) =>
    CatalogDenomination(
      id: _uuid(json['id']),
      label: _text(json['label']),
      nominalMilligrams: _positive(json['nominal_milligrams']),
      active: json['active'] == true,
      createdAt: _text(json['created_at']),
    );

CatalogCoin parseCoinRow(Map<String, Object?> json) => CatalogCoin(
  id: _uuid(json['id']),
  label: _text(json['label']),
  nominalMilligrams: _optionalPositive(json['nominal_milligrams']),
  active: json['active'] == true,
  createdAt: _text(json['created_at']),
);

GoldObligationView parseGoldObligationRow(Map<String, Object?> json) {
  final id = _uuid(json['operation_id']);
  final createdAt = _text(json['created_at']);
  return GoldObligationView(
    operationId: id,
    traderId: _optionalUuid(json['trader_id']),
    karat: _karat(json['karat']),
    initialMilligrams: _positive(json['initial_milligrams']),
    remainingMilligrams: _positive(json['remaining_milligrams']),
    createdAt: createdAt,
    cursor: '$createdAt|$id',
  );
}

ReadPage<TraderObligation> parseTraderObligations(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['items'] is! List) {
    throw const FormatException('inventory');
  }
  return ReadPage.ready([
    for (final item in json['items'] as List)
      () {
        final row = _map(item);
        final unit = _text(row['unit']);
        if (unit != 'egp_piastres' && unit != 'gold_mg') {
          throw const FormatException('inventory');
        }
        final karat = row['karat'];
        if (unit == 'egp_piastres' && karat != null) {
          throw const FormatException('inventory');
        }
        return TraderObligation(
          operationId: _uuid(row['operation_id']),
          unit: unit,
          karat: unit == 'gold_mg' ? _karat(karat) : null,
          original: _positive(row['original']),
          remaining: _positive(row['remaining']),
          createdAt: _text(row['created_at']),
          cursor: _text(row['cursor']),
        );
      }(),
  ], _cursor(json['next_cursor']));
}

// Item × karat aggregate for «الجرد الفوري» (ADR 0043 / ADR 0044).

import '../../daily_ledger/domain/gold_metrics.dart';
import '../../daily_ledger/domain/jewelry_items.dart';

final class InventoryGridCell {
  const InventoryGridCell({
    required this.count,
    required this.countKnown,
    required this.milligrams,
  });

  final BigInt count;
  final bool countKnown;
  final BigInt milligrams;
}

final class InventoryGridRow {
  const InventoryGridRow({required this.itemName, required this.cells});

  final String itemName;
  final Map<int, InventoryGridCell> cells;
}

final class InventoryItemGrid {
  const InventoryItemGrid({
    required this.rows,
    required this.scrapByKarat,
    required this.totals,
  });

  final List<InventoryGridRow> rows;
  final Map<int, BigInt> scrapByKarat;
  final Map<int, InventoryGridCell> totals;
}

const inventoryDefaultKaratOrder = <int>[18, 21, 22, 14];

List<int> visibleInventoryKarats(List<int> order, {required bool expanded}) {
  if (order.length < 2) return List<int>.from(inventoryDefaultKaratOrder);
  if (expanded) return List<int>.from(order);
  return order.take(2).toList(growable: false);
}

List<int> parseInventoryKaratOrder(List<String>? saved) {
  if (saved == null || saved.length != inventoryDefaultKaratOrder.length) {
    return List<int>.from(inventoryDefaultKaratOrder);
  }
  final parsed = <int>[];
  for (final raw in saved) {
    final value = int.tryParse(raw);
    if (value == null) return List<int>.from(inventoryDefaultKaratOrder);
    parsed.add(value);
  }
  final expected = inventoryDefaultKaratOrder.toSet();
  if (parsed.toSet().length != parsed.length ||
      parsed.toSet().difference(expected).isNotEmpty ||
      expected.difference(parsed.toSet()).isNotEmpty) {
    return List<int>.from(inventoryDefaultKaratOrder);
  }
  return parsed;
}

/// Built-in table order: coins first, then the 11 jewelry names, zeros allowed.
const inventoryBuiltinRowOrder = <String>['جنيهات', ...jewelryBuiltIns];

List<InventoryGridRow> orderInventoryGridRows(Iterable<InventoryGridRow> rows) {
  final byName = <String, InventoryGridRow>{};
  for (final row in rows) {
    final name = canonicalJewelryName(row.itemName);
    final existing = byName[name];
    if (existing == null) {
      byName[name] = InventoryGridRow(itemName: name, cells: {...row.cells});
      continue;
    }
    final merged = Map<int, InventoryGridCell>.from(existing.cells);
    for (final entry in row.cells.entries) {
      final prior = merged[entry.key];
      if (prior == null) {
        merged[entry.key] = entry.value;
      } else {
        merged[entry.key] = InventoryGridCell(
          count: prior.count + entry.value.count,
          countKnown: prior.countKnown && entry.value.countKnown,
          milligrams: prior.milligrams + entry.value.milligrams,
        );
      }
    }
    byName[name] = InventoryGridRow(itemName: name, cells: merged);
  }

  final ordered = <InventoryGridRow>[];
  for (final name in inventoryBuiltinRowOrder) {
    ordered.add(
      byName.remove(name) ?? InventoryGridRow(itemName: name, cells: const {}),
    );
  }
  final opening = byName.remove('رصيد افتتاحي مجمّع');
  final rest = byName.values.toList()
    ..sort((a, b) => a.itemName.compareTo(b.itemName));
  // Custom items with stock only (no empty custom rows).
  ordered.addAll(
    rest.where(
      (row) => row.cells.values.any((cell) => cell.milligrams > BigInt.zero),
    ),
  );
  if (opening != null &&
      opening.cells.values.any((cell) => cell.milligrams > BigInt.zero)) {
    ordered.add(opening);
  }
  return ordered;
}

Map<int, InventoryGridCell> inventoryGridTotals(
  Iterable<InventoryGridRow> rows,
) {
  final milligrams = <int, BigInt>{};
  final counts = <int, BigInt>{};
  final known = <int, bool>{};
  for (final row in rows) {
    for (final entry in row.cells.entries) {
      milligrams[entry.key] =
          (milligrams[entry.key] ?? BigInt.zero) + entry.value.milligrams;
      counts[entry.key] =
          (counts[entry.key] ?? BigInt.zero) + entry.value.count;
      known[entry.key] = (known[entry.key] ?? true) && entry.value.countKnown;
    }
  }
  return {
    for (final karat in milligrams.keys)
      karat: InventoryGridCell(
        count: counts[karat] ?? BigInt.zero,
        countKnown: known[karat] ?? true,
        milligrams: milligrams[karat] ?? BigInt.zero,
      ),
  };
}

final class InventoryInsightBucket {
  const InventoryInsightBucket({
    required this.category,
    required this.availableMilligrams,
    this.availableCount,
  });

  final String category;
  final BigInt availableMilligrams;
  final BigInt? availableCount;
}

final class InventoryInsights {
  const InventoryInsights({
    required this.workedMilligrams,
    required this.workedCount,
    required this.workedCountKnown,
    required this.scrapMilligrams,
    required this.bullionMilligrams,
    required this.coinCount,
    required this.cashPiastres,
  });

  final BigInt workedMilligrams;
  final BigInt workedCount;
  final bool workedCountKnown;
  final BigInt scrapMilligrams;
  final BigInt bullionMilligrams;
  final BigInt coinCount;
  final BigInt cashPiastres;
}

InventoryInsights inventoryInsights(
  Iterable<InventoryInsightBucket> buckets,
  Map<String, BigInt> cash,
) {
  var workedMg = BigInt.zero;
  var workedCount = BigInt.zero;
  var workedKnown = true;
  var scrapMg = BigInt.zero;
  var bullionMg = BigInt.zero;
  var coinCount = BigInt.zero;
  for (final bucket in buckets) {
    switch (bucket.category) {
      case 'worked_jewelry':
        workedMg += bucket.availableMilligrams;
        if (bucket.availableCount == null) {
          workedKnown = false;
        } else {
          workedCount += bucket.availableCount!;
        }
      case 'scrap':
        scrapMg += bucket.availableMilligrams;
      case 'bullion':
        bullionMg += bucket.availableMilligrams;
      case 'coin':
        coinCount += bucket.availableCount ?? BigInt.zero;
    }
  }
  var cashTotal = BigInt.zero;
  for (final value in cash.values) {
    cashTotal += value;
  }
  return InventoryInsights(
    workedMilligrams: workedMg,
    workedCount: workedCount,
    workedCountKnown: workedKnown,
    scrapMilligrams: scrapMg,
    bullionMilligrams: bullionMg,
    coinCount: coinCount,
    cashPiastres: cashTotal,
  );
}

/// One figure in the «الجرد الفوري» carousel (ADR 0044 C-D5).
final class InventoryFigure {
  const InventoryFigure({
    required this.id,
    required this.label,
    required this.milligrams,
    this.count,
    this.cashCalculator = false,
    this.awaitingPrice = false,
  });

  final String id;
  final String label;
  final BigInt milligrams;
  final BigInt? count;
  final bool cashCalculator;

  /// The cash calculator has no gram price yet; the tile asks for one.
  final bool awaitingPrice;
}

BigInt _mgFor(
  Iterable<({String category, int karat, BigInt milligrams, BigInt? count})>
  buckets, {
  required String category,
  required int karat,
}) {
  var total = BigInt.zero;
  for (final bucket in buckets) {
    if (bucket.category == category && bucket.karat == karat) {
      total += bucket.milligrams;
    }
  }
  return total;
}

BigInt _countFor(
  Iterable<({String category, int karat, BigInt milligrams, BigInt? count})>
  buckets, {
  required String category,
}) {
  var total = BigInt.zero;
  for (final bucket in buckets) {
    if (bucket.category == category) {
      total += bucket.count ?? BigInt.zero;
    }
  }
  return total;
}

BigInt _to21(Iterable<({int karat, BigInt milligrams})> weights) =>
    normalizedGoldCentigrams(weights, 21) * BigInt.from(10);

/// Cash-to-21 calculator: milligrams = base21 + (cashPiastres * 1000) ~/ pricePiastresPerGram.
BigInt? inventoryCashToWeight21({
  required BigInt base21Milligrams,
  required BigInt cashPiastres,
  required BigInt pricePiastresPerGram,
}) {
  if (pricePiastresPerGram <= BigInt.zero) return null;
  return base21Milligrams +
      (cashPiastres * BigInt.from(1000)) ~/ pricePiastresPerGram;
}

List<InventoryFigure> inventoryFigures(
  Iterable<({String category, int karat, BigInt milligrams, BigInt? count})>
  buckets,
  Map<String, BigInt> cash, {
  BigInt? cashPricePiastresPerGram,
}) {
  final list = buckets.toList(growable: false);
  final karat18 = _mgFor(list, category: 'worked_jewelry', karat: 18);
  final karat21 = _mgFor(list, category: 'worked_jewelry', karat: 21);
  final karat22 = _mgFor(list, category: 'worked_jewelry', karat: 22);
  final karat14 = _mgFor(list, category: 'worked_jewelry', karat: 14);
  final bullionMg = list
      .where((b) => b.category == 'bullion')
      .fold(BigInt.zero, (sum, b) => sum + b.milligrams);
  final bullionCount = _countFor(list, category: 'bullion');
  final scrap18 = _mgFor(list, category: 'scrap', karat: 18);
  final scrap21 = _mgFor(list, category: 'scrap', karat: 21);
  final scrap22 = _mgFor(list, category: 'scrap', karat: 22);
  final scrap14 = _mgFor(list, category: 'scrap', karat: 14);
  var cashTotal = BigInt.zero;
  for (final value in cash.values) {
    cashTotal += value;
  }

  final workedAndBullion21 = _to21([
    for (final b in list)
      if (b.category == 'worked_jewelry' || b.category == 'bullion')
        (
          karat: b.category == 'bullion' ? 24 : b.karat,
          milligrams: b.milligrams,
        ),
  ]);
  final withScrap21 = _to21([
    for (final b in list)
      if (b.category == 'worked_jewelry' ||
          b.category == 'bullion' ||
          b.category == 'scrap')
        (
          karat: b.category == 'bullion' ? 24 : b.karat,
          milligrams: b.milligrams,
        ),
  ]);
  final scrapAs21 = _to21([
    for (final b in list)
      if (b.category == 'scrap') (karat: b.karat, milligrams: b.milligrams),
  ]);

  final figures = <InventoryFigure>[
    InventoryFigure(id: 'karat_18', label: 'عيار 18', milligrams: karat18),
    InventoryFigure(id: 'karat_21', label: 'عيار 21', milligrams: karat21),
    if (karat22 > BigInt.zero)
      InventoryFigure(id: 'karat_22', label: 'عيار 22', milligrams: karat22),
    if (karat14 > BigInt.zero)
      InventoryFigure(id: 'karat_14', label: 'عيار 14', milligrams: karat14),
    InventoryFigure(
      id: 'bullion_count',
      label: 'عدد السبائك',
      milligrams: BigInt.zero,
      count: bullionCount,
    ),
    InventoryFigure(
      id: 'bullion_weight',
      label: 'وزن السبائك',
      milligrams: bullionMg,
    ),
    InventoryFigure(
      id: 'cash',
      label: 'اجمالي النقدية',
      milligrams: BigInt.zero,
      count: cashTotal,
    ),
    InventoryFigure(id: 'scrap_18', label: 'الكسر 18', milligrams: scrap18),
    InventoryFigure(id: 'scrap_21', label: 'الكسر 21', milligrams: scrap21),
    if (scrap22 > BigInt.zero)
      InventoryFigure(id: 'scrap_22', label: 'الكسر 22', milligrams: scrap22),
    if (scrap14 > BigInt.zero)
      InventoryFigure(id: 'scrap_14', label: 'الكسر 14', milligrams: scrap14),
    InventoryFigure(
      id: 'scrap_as_21',
      label: 'اجمالي الكسر 21',
      milligrams: scrapAs21,
    ),
    InventoryFigure(
      id: 'weight_21',
      label: 'اجمالي الوزنة 21 (مشغولات + سبائك)',
      milligrams: workedAndBullion21,
    ),
    InventoryFigure(
      id: 'weight_21_with_scrap',
      label: 'اجمالي الوزنة 21 (مع الكسر)',
      milligrams: withScrap21,
    ),
    InventoryFigure(
      id: 'weight_21_with_cash',
      label: 'اجمالي الوزنة 21 مع النقدية',
      milligrams:
          inventoryCashToWeight21(
            base21Milligrams: withScrap21,
            cashPiastres: cashTotal,
            pricePiastresPerGram: cashPricePiastresPerGram ?? BigInt.zero,
          ) ??
          withScrap21,
      cashCalculator: true,
      awaitingPrice:
          cashPricePiastresPerGram == null ||
          cashPricePiastresPerGram <= BigInt.zero,
    ),
  ];
  return figures;
}

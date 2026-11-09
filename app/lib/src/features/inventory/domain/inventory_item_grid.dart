// Item × karat aggregate for «الجرد الفوري» (ADR 0043).

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

const _builtinItemOrder = <String>['خاتم', 'حلق', 'سلسلة', 'تعليقة'];

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

List<InventoryGridRow> orderInventoryGridRows(Iterable<InventoryGridRow> rows) {
  final byName = {for (final row in rows) row.itemName: row};
  final ordered = <InventoryGridRow>[];
  for (final name in _builtinItemOrder) {
    final row = byName.remove(name);
    if (row != null) ordered.add(row);
  }
  final rest = byName.values.toList()
    ..sort((a, b) => a.itemName.compareTo(b.itemName));
  ordered.addAll(rest);
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

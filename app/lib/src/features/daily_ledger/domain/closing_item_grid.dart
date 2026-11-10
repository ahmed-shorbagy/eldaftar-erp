import 'jewelry_items.dart';
import 'opening_issue.dart';
import 'quantities.dart';

/// One row of the closing grid: an item name, its category, and its columns.
final class ClosingGridRow {
  const ClosingGridRow(this.name, this.category, this.karats);

  final String name;
  final String category;
  final List<int> karats;
}

/// Why a closing cell cannot become an observation.
enum ClosingGridIssue { weightWithoutCount, countOutOfRange, invalidWeight }

/// Stock rows produced from the closing grid, or the first cell error.
sealed class ClosingGridDraft {
  const ClosingGridDraft();
}

final class ClosingGridReady extends ClosingGridDraft {
  const ClosingGridReady(this.stock);

  final List<Map<String, Object?>> stock;
}

final class ClosingGridRejected extends ClosingGridDraft {
  const ClosingGridRejected(this.issue);

  final ClosingGridIssue issue;
}

/// Builds the item rows and karat columns for closing.
///
/// [bookStock] is counts['stock'] (list of {category, karat, count, milligrams}).
/// [shopNames] are (name, category, karat) from InventoryGateway.products.
final class ClosingItemGrid {
  const ClosingItemGrid({
    required this.jewelryKarats,
    required this.rows,
    this.zeroBuckets = const [],
  });

  static const builtInJewelry = jewelryBuiltIns;
  static const _jewelryOrder = [18, 21, 22, 14];

  final List<int> jewelryKarats;
  final List<ClosingGridRow> rows;

  /// Book buckets whose recorded piece count is zero. The server needs a row
  /// for every bucket, so an untouched zero bucket is sent as a zero count.
  final List<(String category, int karat)> zeroBuckets;

  factory ClosingItemGrid.build({
    required List<Map<String, Object?>> bookStock,
    required List<({String name, String category, int karat})> shopNames,
  }) {
    final jewelryKarats = [
      for (final karat in _jewelryOrder)
        if (bookStock.any(
          (row) => row['category'] == 'worked_jewelry' && row['karat'] == karat,
        ))
          karat,
    ];
    final rows = <ClosingGridRow>[];
    if (jewelryKarats.isNotEmpty) {
      final seen = <String>{};
      for (final name in builtInJewelry) {
        seen.add(name);
        rows.add(ClosingGridRow(name, 'worked_jewelry', jewelryKarats));
      }
      for (final product in shopNames) {
        final name = canonicalJewelryName(product.name);
        if (product.category != 'worked_jewelry' ||
            !jewelryKarats.contains(product.karat) ||
            !seen.add(name)) {
          continue;
        }
        rows.add(ClosingGridRow(name, 'worked_jewelry', jewelryKarats));
      }
    }
    final coin = bookStock.where((row) => row['category'] == 'coin');
    if (coin.isNotEmpty) {
      rows.add(ClosingGridRow('جنيهات', 'coin', [coin.first['karat']! as int]));
    }
    if (bookStock.any((row) => row['category'] == 'bullion')) {
      rows.add(const ClosingGridRow('سبائك', 'bullion', [24]));
    }
    final zeroBuckets = [
      for (final row in bookStock)
        if (row['category'] is String &&
            row['karat'] is int &&
            BigInt.tryParse('${row['count']}') == BigInt.zero)
          (row['category']! as String, row['karat']! as int),
    ];
    return ClosingItemGrid(
      jewelryKarats: jewelryKarats,
      rows: rows,
      zeroBuckets: zeroBuckets,
    );
  }

  /// One stock observation per non-empty cell. An empty count is omitted.
  ClosingGridDraft toObservations(Map<(String, int), (String, String)> cells) {
    final stock = <Map<String, Object?>>[];
    for (final row in rows) {
      for (final karat in row.karats) {
        final cell = cells[(row.name, karat)];
        if (cell == null) continue;
        final countText = cell.$1.trim();
        final gramsText = cell.$2.trim();
        if (countText.isEmpty) {
          if (gramsText.isNotEmpty) {
            return const ClosingGridRejected(
              ClosingGridIssue.weightWithoutCount,
            );
          }
          continue;
        }
        if (!RegExp(r'^[0-9]{1,4}$').hasMatch(countText)) {
          return const ClosingGridRejected(ClosingGridIssue.countOutOfRange);
        }
        // «05» is read as 5.
        final canonical = BigInt.parse(countText).toString();
        final count = PieceCount.parseWire(canonical);
        if (count is! Accepted<PieceCount> || count.value.wire != canonical) {
          return const ClosingGridRejected(ClosingGridIssue.countOutOfRange);
        }
        final pieces = count.value;
        String? milligrams;
        if (gramsText.isNotEmpty) {
          final weight = Milligrams.parseGrams(gramsText);
          if (weight is! Accepted<Milligrams>) {
            return const ClosingGridRejected(ClosingGridIssue.invalidWeight);
          }
          milligrams = weight.value.wire;
        }
        stock.add({
          'item_name': row.name,
          'category': row.category,
          'karat': karat,
          'count': pieces.wire,
          'milligrams': milligrams,
        });
      }
    }
    for (final (category, karat) in zeroBuckets) {
      final counted = stock.any(
        (row) => row['category'] == category && row['karat'] == karat,
      );
      if (counted) continue;
      final ClosingGridRow? named = rows
          .where(
            (row) => row.category == category && row.karats.contains(karat),
          )
          .firstOrNull;
      if (named == null) continue;
      stock.add({
        'item_name': named.name,
        'category': category,
        'karat': karat,
        'count': '0',
        'milligrams': null,
      });
    }
    return ClosingGridReady(stock);
  }
}

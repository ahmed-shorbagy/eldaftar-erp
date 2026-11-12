// O1 / ADR 0047 D1: selling every remaining piece of a named item takes that
// item's whole recorded weight; the difference is a stock correction. This
// predicts the server rule so the owner sees it before confirming.

import '../../inventory/domain/inventory_item_grid.dart';
import 'jewelry_items.dart';

final class LastPieceWeightNotice {
  const LastPieceWeightNotice({
    required this.itemName,
    required this.karat,
    required this.recordedMilligrams,
    required this.soldMilligrams,
  });

  final String itemName;
  final int karat;
  final BigInt recordedMilligrams;
  final BigInt soldMilligrams;

  /// Positive when the recorded weight is heavier than the weight sold.
  BigInt get differenceMilligrams => recordedMilligrams - soldMilligrams;
}

/// Sale items (wire maps with `item_name`, `karat`, `count`, `milligrams`)
/// that take every remaining piece of their item at a different weight.
List<LastPieceWeightNotice> lastPieceWeightNotices(
  InventoryItemGrid grid,
  List<Map<String, Object?>> saleItems,
) {
  final sold = <(String, int), (BigInt, BigInt)>{};
  for (final item in saleItems) {
    if (item['category'] != 'worked_jewelry') continue;
    final name = item['item_name'];
    final karat = item['karat'];
    final count = BigInt.tryParse('${item['count']}');
    final mg = BigInt.tryParse('${item['milligrams']}');
    if (name is! String || karat is! int || count == null || mg == null) {
      continue;
    }
    final key = (canonicalJewelryName(name.trim()), karat);
    final previous = sold[key] ?? (BigInt.zero, BigInt.zero);
    sold[key] = (previous.$1 + count, previous.$2 + mg);
  }
  final notices = <LastPieceWeightNotice>[];
  for (final entry in sold.entries) {
    final row = grid.rows
        .where((row) => canonicalJewelryName(row.itemName) == entry.key.$1)
        .firstOrNull;
    final cell = row?.cells[entry.key.$2];
    if (cell == null || !cell.countKnown) continue;
    if (cell.count <= BigInt.zero || cell.milligrams <= BigInt.zero) continue;
    if (cell.count != entry.value.$1) continue;
    if (cell.milligrams == entry.value.$2) continue;
    notices.add(
      LastPieceWeightNotice(
        itemName: entry.key.$1,
        karat: entry.key.$2,
        recordedMilligrams: cell.milligrams,
        soldMilligrams: entry.value.$2,
      ),
    );
  }
  return notices;
}

import 'package:eldafttar/src/features/daily_ledger/domain/last_piece_weight.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_journal_table.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_item_grid.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryItemGrid _grid(Map<String, Map<int, (int, int)>> rows) =>
    InventoryItemGrid(
      rows: [
        for (final row in rows.entries)
          InventoryGridRow(
            itemName: row.key,
            cells: {
              for (final cell in row.value.entries)
                cell.key: InventoryGridCell(
                  count: BigInt.from(cell.value.$1),
                  countKnown: true,
                  milligrams: BigInt.from(cell.value.$2),
                ),
            },
          ),
      ],
      scrapByKarat: const {},
      totals: const {},
    );

Map<String, Object?> _item(String name, int karat, int count, int mg) => {
  'category': 'worked_jewelry',
  'item_name': name,
  'karat': karat,
  'count': '$count',
  'milligrams': '$mg',
};

void main() {
  group('O1 last piece weight notice', () {
    final grid = _grid({
      'سلاسل': {21: (1, 10500)},
      'خواتم': {21: (2, 4000)},
    });

    test('selling the last piece at a lower weight is announced', () {
      final notices = lastPieceWeightNotices(grid, [
        _item('سلاسل', 21, 1, 10000),
      ]);
      expect(notices, hasLength(1));
      expect(notices.single.itemName, 'سلاسل');
      expect(notices.single.recordedMilligrams, BigInt.from(10500));
      expect(notices.single.differenceMilligrams, BigInt.from(500));
    });

    test('a heavier sale gives a negative difference', () {
      final notices = lastPieceWeightNotices(grid, [
        _item('سلسلة', 21, 1, 10800),
      ]);
      expect(notices.single.differenceMilligrams, BigInt.from(-300));
    });

    test('no notice when pieces remain, weights match, or item unknown', () {
      expect(
        lastPieceWeightNotices(grid, [_item('خواتم', 21, 1, 1800)]),
        isEmpty,
      );
      expect(
        lastPieceWeightNotices(grid, [_item('سلاسل', 21, 1, 10500)]),
        isEmpty,
      );
      expect(
        lastPieceWeightNotices(grid, [_item('حلقان', 21, 1, 900)]),
        isEmpty,
      );
      expect(
        lastPieceWeightNotices(grid, [_item('سلاسل', 18, 1, 900)]),
        isEmpty,
      );
    });

    test('two lines of the same item are summed', () {
      final notices = lastPieceWeightNotices(grid, [
        _item('خواتم', 21, 1, 1900),
        _item('خاتم', 21, 1, 1900),
      ]);
      expect(notices.single.soldMilligrams, BigInt.from(3800));
      expect(notices.single.differenceMilligrams, BigInt.from(200));
    });
  });

  test('O4 weight sheets follow the owner karat order 18, 21, 22, 14', () {
    final karats = [14, 22, 21, 18, 24]..sort(compareKaratDisplay);
    expect(karats, [18, 21, 24, 22, 14]);
    final withUnknown = [9, 14, 18]..sort(compareKaratDisplay);
    expect(withUnknown, [18, 14, 9]);
  });

  test('U8 cards name the seller on sales and the recorder elsewhere', () {
    expect(actorLabel('sale'), 'اسم البائع');
    expect(actorLabel('scrap_sale'), 'اسم البائع');
    expect(actorLabel('purchase'), 'المسجِّل');
    expect(actorLabel('expense'), 'المسجِّل');
  });
}

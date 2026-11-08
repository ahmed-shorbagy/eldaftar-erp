import 'package:eldafttar/src/features/daily_ledger/domain/closing_count_observation.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/closing_item_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> bucket(String category, int karat) => {
    'category': category,
    'karat': karat,
    'count': '1',
    'milligrams': '1000',
  };

  test('jewelry columns follow 18, 21, 22, 14 and drop missing karats', () {
    final all = ClosingItemGrid.build(
      bookStock: [
        bucket('worked_jewelry', 14),
        bucket('worked_jewelry', 22),
        bucket('worked_jewelry', 21),
        bucket('worked_jewelry', 18),
      ],
      shopNames: const [],
    );
    expect(all.jewelryKarats, [18, 21, 22, 14]);

    final partial = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 21), bucket('worked_jewelry', 18)],
      shopNames: const [],
    );
    expect(partial.jewelryKarats, [18, 21]);
  });

  test('built-in names come first and shop products are not repeated', () {
    final grid = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 18)],
      shopNames: const [
        (name: 'دبلة خاصة', category: 'worked_jewelry', karat: 18),
        (name: 'خاتم', category: 'worked_jewelry', karat: 18),
        (name: 'دبلة خاصة', category: 'worked_jewelry', karat: 21),
        (name: 'سبيكة خاصة', category: 'bullion', karat: 24),
      ],
    );
    expect(grid.rows.map((row) => row.name), [
      'خاتم',
      'حلق',
      'سلسلة',
      'تعليقة',
      'دبلة خاصة',
    ]);
  });

  test('coin and bullion rows appear only for those buckets', () {
    final jewelry = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 18)],
      shopNames: const [],
    );
    expect(jewelry.rows.map((row) => row.name), [
      'خاتم',
      'حلق',
      'سلسلة',
      'تعليقة',
    ]);

    final withMetal = ClosingItemGrid.build(
      bookStock: [
        bucket('worked_jewelry', 18),
        bucket('coin', 21),
        bucket('bullion', 24),
      ],
      shopNames: const [],
    );
    expect(withMetal.rows.last.name, 'سبائك');
    expect(withMetal.rows.last.karats, [24]);
    expect(withMetal.rows.singleWhere((row) => row.name == 'جنيهات').karats, [
      21,
    ]);
  });

  test('empty cells are omitted and a weight without a count is rejected', () {
    final grid = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 21), bucket('worked_jewelry', 18)],
      shopNames: const [],
    );
    final ready = grid.toObservations({
      ('خاتم', 21): ('2', ''),
      ('حلق', 18): ('', ''),
    });
    expect(ready, isA<ClosingGridReady>());
    expect((ready as ClosingGridReady).stock, [
      {
        'item_name': 'خاتم',
        'category': 'worked_jewelry',
        'karat': 21,
        'count': '2',
        'milligrams': null,
      },
    ]);

    final missingCount = grid.toObservations({('خاتم', 21): ('', '1.500')});
    expect(
      missingCount,
      isA<ClosingGridRejected>().having(
        (error) => error.issue,
        'issue',
        ClosingGridIssue.weightWithoutCount,
      ),
    );
  });

  test(
    'an untouched zero bucket is sent as a zero count and matches the book',
    () {
      // The book keeps a 22k bucket after all of it was sold. The server needs a
      // row for every bucket, so the owner must not have to type 0 there.
      final book = <String, Object?>{
        'cash': {'cash': '0'},
        'stock': [
          bucket('worked_jewelry', 21),
          {
            'category': 'worked_jewelry',
            'karat': 22,
            'count': '0',
            'milligrams': '0',
          },
        ],
        'scrap': const [],
      };
      final grid = ClosingItemGrid.build(
        bookStock: [
          for (final row in book['stock']! as List)
            Map<String, Object?>.from(row as Map),
        ],
        shopNames: const [],
      );
      final draft = grid.toObservations({('خاتم', 21): ('1', '')});
      expect(draft, isA<ClosingGridReady>());
      final stock = (draft as ClosingGridReady).stock;
      expect(stock, hasLength(2));
      expect(stock.last, {
        'item_name': 'خاتم',
        'category': 'worked_jewelry',
        'karat': 22,
        'count': '0',
        'milligrams': null,
      });
      expect(
        closingObservationsMatch({
          'version': 2,
          'cash': {'cash': '0'},
          'stock': stock,
          'scrap': const [],
        }, book),
        isTrue,
      );
    },
  );

  test('a typed zero bucket is not sent twice', () {
    final grid = ClosingItemGrid.build(
      bookStock: [
        {
          'category': 'worked_jewelry',
          'karat': 22,
          'count': '0',
          'milligrams': '0',
        },
      ],
      shopNames: const [],
    );
    final draft = grid.toObservations({('حلق', 22): ('0', '')});
    expect((draft as ClosingGridReady).stock, hasLength(1));
    expect(draft.stock.single['item_name'], 'حلق');
  });

  test('a leading zero is read as the plain number', () {
    final grid = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 18)],
      shopNames: const [],
    );
    final draft = grid.toObservations({('خاتم', 18): ('05', '')});
    expect((draft as ClosingGridReady).stock.single['count'], '5');
  });

  test('a count of 10000 is rejected', () {
    final grid = ClosingItemGrid.build(
      bookStock: [bucket('worked_jewelry', 18)],
      shopNames: const [],
    );
    final rejected = grid.toObservations({('خاتم', 18): ('10000', '')});
    expect(
      rejected,
      isA<ClosingGridRejected>().having(
        (error) => error.issue,
        'issue',
        ClosingGridIssue.countOutOfRange,
      ),
    );
  });
}

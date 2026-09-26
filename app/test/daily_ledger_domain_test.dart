import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const half = '4611686018427387904';
  const aboveMax = '9223372036854775808';
  const jsUnsafe = '9007199254740993';

  T accepted<T>(DomainResult<T> result) {
    expect(result, isA<Accepted<T>>());
    return (result as Accepted<T>).value;
  }

  void rejected<T>(DomainResult<T> result, OpeningIssueCode code) {
    expect(result, isA<Rejected<T>>());
    expect((result as Rejected<T>).code, code);
  }

  Piastres pounds(String text) => accepted(Piastres.parsePounds(text));
  Milligrams grams(String text) => accepted(Milligrams.parseGrams(text));
  PieceCount count(String text) => accepted(PieceCount.parseWire(text));

  OpeningStockBucket stock({
    required StockCategory category,
    required int karat,
    required String milligrams,
    required String pieces,
  }) {
    return accepted(
      OpeningStockBucket.tryCreate(
        category: category,
        karat: karat,
        milligrams: grams(milligrams),
        count: count(pieces),
      ),
    );
  }

  OpeningDraft synthetic() {
    return accepted(
      OpeningDraft.compose(
        cash: {
          CashMethod.cash: pounds('10000.00'),
          CashMethod.wallet: pounds('2500.00'),
        },
        stock: [
          stock(
            category: StockCategory.workedJewelry,
            karat: 21,
            milligrams: '2.560',
            pieces: '1',
          ),
          stock(
            category: StockCategory.workedJewelry,
            karat: 14,
            milligrams: '1.250',
            pieces: '1',
          ),
          stock(
            category: StockCategory.workedJewelry,
            karat: 18,
            milligrams: '5.000',
            pieces: '3',
          ),
          stock(
            category: StockCategory.bullion,
            karat: 24,
            milligrams: '8.000',
            pieces: '2',
          ),
          stock(
            category: StockCategory.coin,
            karat: 21,
            milligrams: '8.000',
            pieces: '1',
          ),
        ],
        scrap: [
          accepted(
            OpeningScrapBucket.tryCreate(karat: 21, milligrams: grams('1.000')),
          ),
          accepted(
            OpeningScrapBucket.tryCreate(karat: 14, milligrams: grams('0.500')),
          ),
        ],
      ),
    );
  }

  test('exact gram and pound identities', () {
    final oneEightThree = grams('1.830');
    expect(oneEightThree.value, BigInt.from(1830));
    expect(oneEightThree.gramsText, '1.830');
    expect(oneEightThree.wire, '1830');

    final halfGram = grams('0.500');
    expect(halfGram.value, BigInt.from(500));
    expect(halfGram.gramsText, '0.500');

    final tenThousand = pounds('10000.00');
    expect(tenThousand.value, BigInt.from(1000000));
    expect(tenThousand.poundsText, '10000.00');
    expect(tenThousand.wire, '1000000');

    final oneAndQuarter = pounds('1.25');
    expect(oneAndQuarter.value, BigInt.from(125));
    expect(oneAndQuarter.poundsText, '1.25');

    final draft = synthetic();
    expect(draft.cash[CashMethod.cash].wire, '1000000');
    expect(draft.cash[CashMethod.instantTransfer].wire, '0');
    expect(draft.cash[CashMethod.instantTransfer].poundsText, '0.00');
    expect(draft.cash[CashMethod.wallet].wire, '250000');
    expect(draft.cash[CashMethod.wallet].poundsText, '2500.00');
    expect(draft.cash[CashMethod.card].wire, '0');

    expect(draft.stock.map((row) => row.category.code).toList(), [
      'bullion',
      'coin',
      'worked_jewelry',
      'worked_jewelry',
      'worked_jewelry',
    ]);
    expect(
      draft.stock.map((row) => '${row.category.code}:${row.karat}').toList(),
      [
        'bullion:24',
        'coin:21',
        'worked_jewelry:14',
        'worked_jewelry:18',
        'worked_jewelry:21',
      ],
    );
    expect(draft.stock[2].milligrams.gramsText, '1.250');
    expect(draft.stock[2].count.wire, '1');
    expect(draft.stock[3].milligrams.wire, '5000');
    expect(draft.stock[3].milligrams.gramsText, '5.000');
    expect(draft.stock[3].count.wire, '3');
    expect(draft.stock[4].milligrams.gramsText, '2.560');
    expect(draft.stock[0].milligrams.gramsText, '8.000');
    expect(draft.stock[0].count.wire, '2');
    expect(draft.stock[1].milligrams.gramsText, '8.000');
    expect(draft.stock[1].count.wire, '1');
    expect(draft.scrap.map((row) => row.karat).toList(), [14, 21]);
    expect(draft.scrap[0].milligrams.gramsText, '0.500');
    expect(draft.scrap[1].milligrams.wire, '1000');
    expect(draft.scrap[1].milligrams.gramsText, '1.000');
  });

  test(
    'canonical payload matches the reviewed shape and keeps large strings',
    () {
      final parsed = accepted(
        OpeningDraft.parseJson({
          'scrap': [
            {'karat': 21, 'milligrams': '1000'},
          ],
          'stock': [
            {
              'count': '3',
              'milligrams': '5000',
              'karat': 18,
              'category': 'worked_jewelry',
            },
          ],
          'version': 1,
          'cash': {'wallet': '0'},
        }),
      );
      expect(
        jsonEncode(parsed.toCanonicalJson()),
        jsonEncode({
          'version': 1,
          'cash': {
            'cash': '0',
            'instant_transfer': '0',
            'wallet': '0',
            'card': '0',
          },
          'stock': [
            {
              'category': 'worked_jewelry',
              'karat': 18,
              'milligrams': '5000',
              'count': '3',
            },
          ],
          'scrap': [
            {'karat': 21, 'milligrams': '1000'},
          ],
        }),
      );

      final wide = accepted(
        OpeningDraft.parseJson({
          'version': 1,
          'cash': {
            'cash': jsUnsafe,
            'instant_transfer': '0',
            'wallet': '0',
            'card': '0',
          },
          'stock': [
            {
              'category': 'bullion',
              'karat': 24,
              'milligrams': jsUnsafe,
              'count': jsUnsafe,
            },
          ],
          'scrap': [],
        }),
      );
      final encoded = jsonEncode(wide.toCanonicalJson());
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final cash = decoded['cash'] as Map<String, Object?>;
      final row = (decoded['stock'] as List).single as Map<String, Object?>;
      expect(cash['cash'], jsUnsafe);
      expect(row['milligrams'], jsUnsafe);
      expect(row['count'], jsUnsafe);
      expect(row['karat'], 24);
      expect(decoded['version'], 1);
      expect(wide.cash[CashMethod.cash].value, BigInt.parse(jsUnsafe));
    },
  );

  test('overflow bounds, fractional units, and notation', () {
    expect(PostgresInteger.checkedAdd(PostgresInteger.max, BigInt.one), isNull);
    expect(
      PostgresInteger.checkedAdd(PostgresInteger.min, -BigInt.one),
      isNull,
    );
    expect(
      PostgresInteger.checkedAdd(PostgresInteger.max + BigInt.one, -BigInt.one),
      isNull,
    );
    expect(
      PostgresInteger.checkedMultiply(PostgresInteger.max, BigInt.two),
      isNull,
    );
    rejected(Karat.tryCreate(20), OpeningIssueCode.unsupportedCategoryKarat);
    expect(accepted(Karat.tryCreate(22)).value, 22);
    expect(
      accepted(Piastres.parseWire(PostgresInteger.max.toString())).value,
      PostgresInteger.max,
    );
    rejected(Piastres.parseWire(aboveMax), OpeningIssueCode.overflow);
    rejected(Milligrams.parseWire(aboveMax), OpeningIssueCode.overflow);
    rejected(PieceCount.parseWire(aboveMax), OpeningIssueCode.overflow);
    rejected(Piastres.parseWire('-1'), OpeningIssueCode.negativeAmount);
    rejected(Milligrams.parseGrams('-0.001'), OpeningIssueCode.negativeAmount);
    rejected(Piastres.parsePounds('1.251'), OpeningIssueCode.invalidInput);
    rejected(Piastres.parseWire('1.25'), OpeningIssueCode.invalidInput);
    rejected(Milligrams.parseGrams('1.8300'), OpeningIssueCode.invalidInput);
    rejected(Milligrams.parseWire('1.830'), OpeningIssueCode.invalidInput);
    rejected(Piastres.parsePounds('1e2'), OpeningIssueCode.invalidInput);
    rejected(Milligrams.parseGrams('1.5e1'), OpeningIssueCode.invalidInput);
    rejected(PieceCount.parseWire('01'), OpeningIssueCode.invalidInput);
    rejected(PieceCount.parseWire('1.0'), OpeningIssueCode.invalidInput);
    rejected(Piastres.parseWire(' 125'), OpeningIssueCode.invalidInput);

    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {
          'cash': half,
          'instant_transfer': half,
          'wallet': '0',
          'card': '0',
        },
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.overflow,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {'cash': aboveMax},
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.overflow,
    );
    rejected(
      OpeningDraft.compose(
        stock: [
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.workedJewelry,
              karat: 21,
              milligrams: accepted(Milligrams.parseWire(half)),
              count: count('1'),
            ),
          ),
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.coin,
              karat: 21,
              milligrams: accepted(Milligrams.parseWire(half)),
              count: count('1'),
            ),
          ),
        ],
      ),
      OpeningIssueCode.overflow,
    );
    accepted(
      OpeningDraft.compose(
        stock: [
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.workedJewelry,
              karat: 18,
              milligrams: accepted(
                Milligrams.parseWire(PostgresInteger.max.toString()),
              ),
              count: count('1'),
            ),
          ),
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.bullion,
              karat: 24,
              milligrams: accepted(
                Milligrams.parseWire(PostgresInteger.max.toString()),
              ),
              count: count('1'),
            ),
          ),
        ],
      ),
    );
    rejected(
      OpeningDraft.compose(
        stock: [
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.workedJewelry,
              karat: 18,
              milligrams: grams('1.000'),
              count: accepted(PieceCount.parseWire(half)),
            ),
          ),
          accepted(
            OpeningStockBucket.tryCreate(
              category: StockCategory.workedJewelry,
              karat: 21,
              milligrams: grams('1.000'),
              count: accepted(PieceCount.parseWire(half)),
            ),
          ),
        ],
      ),
      OpeningIssueCode.overflow,
    );
  });

  test('category matrix, duplicates, and row shape', () {
    for (final version in <Object?>[1.0, null, '1', 2, true]) {
      rejected(
        OpeningDraft.parseJson({
          'version': version,
          'cash': {},
          'stock': [],
          'scrap': [],
        }),
        OpeningIssueCode.invalidInput,
      );
    }
    final everyPair = accepted(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {
            'category': 'worked_jewelry',
            'karat': 22,
            'milligrams': '1',
            'count': '1',
          },
          {
            'category': 'worked_jewelry',
            'karat': 14,
            'milligrams': '2',
            'count': '1',
          },
          {'category': 'bullion', 'karat': 24, 'milligrams': '3', 'count': '1'},
          {'category': 'coin', 'karat': 21, 'milligrams': '4', 'count': '1'},
          {
            'category': 'worked_jewelry',
            'karat': 18,
            'milligrams': '5',
            'count': '1',
          },
          {
            'category': 'worked_jewelry',
            'karat': 21,
            'milligrams': '6',
            'count': '1',
          },
        ],
        'scrap': [
          {'karat': 24, 'milligrams': '7'},
          {'karat': 14, 'milligrams': '8'},
          {'karat': 22, 'milligrams': '9'},
          {'karat': 18, 'milligrams': '10'},
          {'karat': 21, 'milligrams': '11'},
        ],
      }),
    );
    expect(everyPair.stock.map((row) => '${row.category.code}:${row.karat}'), [
      'bullion:24',
      'coin:21',
      'worked_jewelry:14',
      'worked_jewelry:18',
      'worked_jewelry:21',
      'worked_jewelry:22',
    ]);
    expect(everyPair.scrap.map((row) => row.karat), [14, 18, 21, 22, 24]);
    expect(everyPair.cash[CashMethod.card].wire, '0');

    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {
            'category': 'worked_jewelry',
            'karat': 24,
            'milligrams': '1',
            'count': '1',
          },
        ],
        'scrap': [],
      }),
      OpeningIssueCode.unsupportedCategoryKarat,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {'category': 'bullion', 'karat': 21, 'milligrams': '1', 'count': '1'},
        ],
        'scrap': [],
      }),
      OpeningIssueCode.unsupportedCategoryKarat,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {'category': 'coin', 'karat': 18, 'milligrams': '1', 'count': '1'},
        ],
        'scrap': [],
      }),
      OpeningIssueCode.unsupportedCategoryKarat,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [],
        'scrap': [
          {'karat': 21, 'milligrams': '1', 'count': '1'},
        ],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {'category': 'coin', 'karat': 21, 'milligrams': '1', 'count': '1'},
          {'category': 'coin', 'karat': 21, 'milligrams': '2', 'count': '1'},
        ],
        'scrap': [],
      }),
      OpeningIssueCode.duplicateBucket,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [],
        'scrap': [
          {'karat': 14, 'milligrams': '1'},
          {'karat': 14, 'milligrams': '2'},
        ],
      }),
      OpeningIssueCode.duplicateBucket,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {'category': 'coin', 'karat': 21, 'milligrams': '0', 'count': '1'},
        ],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [
          {'category': 'coin', 'karat': 21, 'milligrams': '1', 'count': '0'},
        ],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {},
        'stock': [],
        'scrap': [
          {'karat': 18, 'milligrams': '0'},
        ],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {'cheque': '1'},
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'shop_id': 'not-allowed',
        'cash': {},
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {'cash': 125},
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );
    rejected(
      OpeningDraft.parseJson({
        'version': '1',
        'cash': {},
        'stock': [],
        'scrap': [],
      }),
      OpeningIssueCode.invalidInput,
    );

    final zeros = accepted(
      OpeningDraft.parseJson({
        'version': 1,
        'cash': {
          'card': '0',
          'cash': '0',
          'wallet': '0',
          'instant_transfer': '0',
        },
        'stock': [],
        'scrap': [],
      }),
    );
    expect(zeros.stock, isEmpty);
    expect(zeros.scrap, isEmpty);
    expect(zeros.toCanonicalJson()['cash'], {
      'cash': '0',
      'instant_transfer': '0',
      'wallet': '0',
      'card': '0',
    });
  });
}

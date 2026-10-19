import 'package:eldafttar/src/features/daily_ledger/domain/gold_metrics.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_home_metrics.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_metric_specs.dart';
import 'package:eldafttar/src/theme/gram_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('different purities normalize to 21k with one exact rounding', () {
    expect(
      normalizedGoldCentigrams([
        (karat: 18, milligrams: BigInt.from(1000)),
        (karat: 24, milligrams: BigInt.from(2000)),
      ], 21),
      BigInt.from(314),
    );
    expect(
      normalizedGoldCentigrams([
        (karat: 14, milligrams: BigInt.from(2)),
        (karat: 18, milligrams: BigInt.from(3)),
        (karat: 22, milligrams: BigInt.one),
      ], 21),
      BigInt.zero,
    ); // 104/21 mg is below 0.005 g: no double rounding.
    expect(
      normalizedGoldCentigrams([(karat: 21, milligrams: BigInt.from(5))], 21),
      BigInt.one,
    );
    expect(
      normalizedGoldCentigrams([
        (karat: 24, milligrams: BigInt.parse('90071992547409930')),
      ], 24),
      BigInt.parse('9007199254740993'),
    );
    expect(() => normalizedGoldCentigrams([], 20), throwsArgumentError);
  });

  test(
    'metric values keep cash, actual sale karats and scrap-only purchases separate',
    () {
      const view = DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: [],
        stock: [],
        scrap: [],
        feed: [],
        daySummary: LedgerDaySummary(
          salePiastres: '12345',
          purchasePiastres: '100',
          expensePiastres: '0',
          saleCount: 2,
          purchaseCount: 2,
          expenseCount: 0,
          goldByBucket: [
            LedgerGoldMovement(
              kind: 'sale',
              category: 'worked_jewelry',
              karat: 18,
              milligrams: '1000',
              count: '1',
            ),
            LedgerGoldMovement(
              kind: 'sale',
              category: 'bullion',
              karat: 24,
              milligrams: '2000',
              count: '1',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'scrap',
              karat: 22,
              milligrams: '500',
              count: '0',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'worked_jewelry',
              karat: 22,
              milligrams: '9000',
              count: '1',
            ),
          ],
        ),
      );
      final at21 = ledgerMetricValues(view, 21),
          at24 = ledgerMetricValues(view, 24);
      expect(at21.containsKey('total_gold'), isFalse);
      expect(at21['sale']!.value, '123.45');
      expect(at24['sale']!.value, '123.45');
      expect(at21['sale_gold']!.value, '3.14');
      expect(at24['sale_gold']!.value, '2.75');
      expect(at21['sale_karat_18']!.value, '1.00');
      expect(at21['sale_karat_21']!.value, '0.00');
      expect(at21['sale_karat_24']!.value, '2.00');
      expect(at21['scrap_purchase_22']!.value, '0.50');
    },
  );

  test(
    'sale entry accepts Arabic digits, rejects excess precision, and preserves exact trailing-zero pastes',
    () {
      const formatter = GramInputFormatter(decimalPlaces: 2);
      const old = TextEditingValue(
        text: '1.23',
        selection: TextSelection.collapsed(offset: 4),
      );
      final tooPrecise = formatter.formatEditUpdate(
        old,
        const TextEditingValue(text: '1.234'),
      );
      expect(tooPrecise, old);
      expect(
        formatter
            .formatEditUpdate(
              TextEditingValue.empty,
              const TextEditingValue(text: '١٫٢٣'),
            )
            .text,
        '1.23',
      );
      expect(gramEntryValue('1.8300000', decimalPlaces: 2), '1.83');
      expect(gramEntryValue('1.831', decimalPlaces: 2), isNull);
      expect(gramEntryValue('1e4', decimalPlaces: 2), isNull);
      expect(gramEntryValue('-1.20', decimalPlaces: 2), isNull);
      expect(gramEntryValue('1.831', decimalPlaces: 3), '1.831');
    },
  );

  test(
    'normalization and hidden scrap choices roundtrip without losing six selected figures',
    () {
      final layout = selectMetricForSlot(
        migrateLedgerMetricLayout(null),
        0,
        'sale_karat_24',
      ).copyWith(normalizationKarat: 18, hiddenScrapKarats: {14, 22});
      final restored = migrateLedgerMetricLayout(
        encodeLedgerMetricLayout(layout),
      );
      expect(restored.homeIds, layout.homeIds);
      expect(restored.moreIds, hasLength(7));
      expect(restored.normalizationKarat, 18);
      expect(restored.hiddenScrapKarats, {14, 22});
      final swapped = selectMetricForSlot(restored, 0, 'sale');
      expect(swapped.isValid, isTrue);
      expect(swapped.homeIds.toSet(), layout.homeIds.toSet());
    },
  );
}

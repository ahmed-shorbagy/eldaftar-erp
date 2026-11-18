// FB-003: the owner works by item names. The category word he rejected is not
// shown anywhere. A row with no item name reads «عيار 21»; headings and choice
// lists say «أصناف».

import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_balance_sections.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/opening_copy.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_copy.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_copy.dart';
import 'package:eldafttar/src/features/reports/domain/financial_week_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a row with a karat and no item name reads the karat alone', () {
    expect(karatRowLabel('أصناف', 'worked_jewelry', 21), 'عيار 21');
    expect(
      karatRowLabel('أصناف', 'worked_jewelry', 18, separator: ' · '),
      'عيار 18',
    );
  });

  test('bullion, coins and scrap keep their own names on such rows', () {
    expect(karatRowLabel('سبائك', 'bullion', 24), 'سبائك عيار 24');
    expect(
      karatRowLabel('جنيهات', 'coin', 21, separator: ' · '),
      'جنيهات · عيار 21',
    );
    expect(karatRowLabel('كسر', 'scrap', 18), 'كسر عيار 18');
  });

  test('headings and choice lists say «أصناف»', () {
    expect(stockCategoryLabel(StockCategory.workedJewelry), 'أصناف');
    expect(goldCategoryLabel('worked_jewelry'), 'أصناف');
    expect(inventoryCategoryLabel('worked_jewelry'), 'أصناف');
    expect(debtCategoryLabels['worked_jewelry'], 'أصناف');
    expect(reportCategory('worked_jewelry'), 'أصناف');
  });

  test('coins are «جنيهات» in every list, as in the daily ledger', () {
    expect(stockCategoryLabel(StockCategory.coin), 'جنيهات');
    expect(goldCategoryLabel('coin'), 'جنيهات');
    expect(inventoryCategoryLabel('coin'), 'جنيهات');
    expect(debtCategoryLabels['coin'], 'جنيهات');
    expect(reportCategory('coin'), 'جنيهات');
  });

  test('a stock addition is reviewed by weight and karat', () {
    final weight = effectCopy(
      InventoryEffect(
        bucket: 'owned_available',
        unit: EffectUnit.milligrams,
        delta: BigInt.from(5250),
        category: 'worked_jewelry',
        karat: 21,
      ),
    );
    expect(weight, 'يزيد المتاح للبيع: 5.25 جرام عيار 21.');
    final count = effectCopy(
      InventoryEffect(
        bucket: 'owned_available',
        unit: EffectUnit.count,
        delta: BigInt.one,
        category: 'worked_jewelry',
        karat: 21,
      ),
    );
    expect(count, 'يزيد عدد المتاح للبيع (عيار 21): 1.');
    final bullion = effectCopy(
      InventoryEffect(
        bucket: 'owned_available',
        unit: EffectUnit.milligrams,
        delta: BigInt.from(10000),
        category: 'bullion',
        karat: 24,
      ),
    );
    expect(bullion, 'يزيد المتاح للبيع: 10.00 جرام سبائك عيار 24.');
  });

  // The scan that keeps the rejected wording out of `app/lib` and `admin/src`
  // is in owner_terms_guard_test.dart, with every other rejected term.
}

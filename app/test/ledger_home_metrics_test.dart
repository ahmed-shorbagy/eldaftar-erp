import 'package:eldafttar/src/features/daily_ledger/application/ledger_home_metrics.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/opening_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default layout has six figures and eight distinct karat choices in More',
    () {
      final layout = migrateLedgerMetricLayout(null);
      expect(layout.homeIds, ledgerDefaultHomeMetrics);
      expect(layout.moreIds, hasLength(8));
      expect(layout.homeIds, isNot(contains('total_gold')));
      expect(layout.isValid, isTrue);
      expect(layout.homeIds, isNot(contains('operations')));
    },
  );

  test(
    'legacy hidden count and operations drop without shrinking below six',
    () {
      final layout = migrateLedgerMetricLayout(const [
        'metrics',
        'movement',
        'cash',
        'gold',
        'activity',
        'metric:total_cash',
        'metric:total_gold',
        'metric:sale',
        'metric:purchase',
        'metric:sale_gold',
        'metric:purchase_gold',
        'metric:expense',
        'metric:operations',
        'hidden:metric:operations',
        'hidden:count',
        'hidden:movement',
      ]);
      expect(layout.homeIds.length, 6);
      expect(layout.homeIds, isNot(contains('operations')));
      expect(layout.moreIds, hasLength(8));
      expect(layout.homeIds, isNot(contains('total_gold')));
    },
  );

  test('hidden cash migrates to remaining and keeps six others', () {
    final layout = migrateLedgerMetricLayout(const [
      'metric:total_cash',
      'metric:total_gold',
      'metric:sale',
      'metric:purchase',
      'metric:sale_gold',
      'metric:purchase_gold',
      'metric:expense',
      'hidden:metric:total_cash',
    ]);
    expect(layout.homeIds, [
      'sale',
      'purchase',
      'sale_gold',
      'purchase_gold',
      'expense',
      'sale_karat_18',
    ]);
    expect(layout.moreIds, contains('total_cash'));
  });

  test('shops stay isolated because migration is pure per saved list', () {
    final first = migrateLedgerMetricLayout(const [
      'metric:expense',
      'metric:sale',
      'metric:purchase',
      'metric:total_cash',
      'metric:total_gold',
      'metric:sale_gold',
      'remaining:purchase_gold',
    ]);
    final second = migrateLedgerMetricLayout(null);
    expect(first.moreIds, contains('purchase_gold'));
    expect(second.homeIds, contains('purchase_gold'));
    expect(first.homeIds.first, 'expense');
  });

  test('selecting a slot swaps exactly one home figure without duplicates', () {
    final start = migrateLedgerMetricLayout(null);
    final next = selectMetricForSlot(start, 0, 'scrap_purchase_22');
    expect(next.moreIds, contains('total_cash'));
    expect(next.homeIds.first, 'scrap_purchase_22');
    expect(next.homeIds, contains('expense'));
    expect(next.homeIds, isNot(contains('total_cash')));
    expect(next.homeIds.length, 6);
  });

  test(
    'optional 22k and 14k scrap figures come last and hide without losing six slots',
    () {
      final start = selectMetricForSlot(
        migrateLedgerMetricLayout(null),
        0,
        'scrap_purchase_14',
      );
      expect(start.homeIds.first, 'scrap_purchase_14');
      expect(start.availableIds.sublist(start.availableIds.length - 2), [
        'scrap_purchase_22',
        'scrap_purchase_14',
      ]);
      final hidden = start.copyWith(hiddenScrapKarats: {14, 22});
      expect(hidden.isValid, isTrue);
      expect(hidden.homeIds, hasLength(6));
      expect(hidden.availableIds, isNot(contains('scrap_purchase_14')));
      expect(hidden.moreIds, isNot(contains('scrap_purchase_22')));
      expect(hidden.homeIds, isNot(contains('scrap_purchase_14')));
      final restored = migrateLedgerMetricLayout(
        encodeLedgerMetricLayout(hidden),
      );
      expect(restored.homeIds, hidden.homeIds);
      expect(restored.hiddenScrapKarats, {14, 22});
      expect(selectMetricForSlot(hidden, 0, 'scrap_purchase_22'), same(hidden));
      expect(
        hidden.copyWith(hiddenScrapKarats: {}).availableIds,
        containsAll(['scrap_purchase_14', 'scrap_purchase_22']),
      );
    },
  );

  test('shop-local twelve-hour time omits the calendar day', () {
    expect(
      formatShopTwelveHourTime('2026-09-26T03:30:00'),
      '\u20663:30\u2069 ص',
    );
    expect(
      formatShopTwelveHourTime('2026-09-26T12:00:00'),
      '\u206612:00\u2069 م',
    );
    expect(
      formatShopTwelveHourTime('2026-09-26T15:05:00'),
      '\u20663:05\u2069 م',
    );
    expect(
      formatShopTwelveHourTime('2026-09-26T00:15:00'),
      '\u206612:15\u2069 ص',
    );
    expect(
      formatServerCairoTimestamp('2026-09-26T03:30:00'),
      contains('سبتمبر'),
    );
  });
}

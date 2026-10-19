import 'package:eldafttar/src/features/daily_ledger/application/ledger_home_metrics.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/opening_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default layout is six home figures and expense in More', () {
    final layout = migrateLedgerMetricLayout(null);
    expect(layout.homeIds, ledgerDefaultHomeMetrics);
    expect(layout.remainingId, 'expense');
    expect(layout.isValid, isTrue);
    expect(layout.homeIds, isNot(contains('operations')));
  });

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
      expect(layout.remainingId, 'expense');
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
      'total_gold',
      'sale',
      'purchase',
      'sale_gold',
      'purchase_gold',
      'expense',
    ]);
    expect(layout.remainingId, 'total_cash');
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
    expect(first.remainingId, 'purchase_gold');
    expect(second.remainingId, 'expense');
    expect(first.homeIds.first, 'expense');
  });

  test('replacing remaining swaps exactly one home figure', () {
    final start = migrateLedgerMetricLayout(null);
    final next = replaceRemainingMetric(start, 'total_cash');
    expect(next.remainingId, 'total_cash');
    expect(next.homeIds, contains('expense'));
    expect(next.homeIds, isNot(contains('total_cash')));
    expect(next.homeIds.length, 6);
  });

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

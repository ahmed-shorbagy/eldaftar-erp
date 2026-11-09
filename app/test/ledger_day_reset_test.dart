import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_metric_specs.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meeting_calendar_and_count_test.dart' show calendarBody;

DailyLedgerView _view({required bool reset}) => DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: null,
  dayReset: reset,
  lastClosedBusinessDate: reset ? '2026-11-08' : null,
  cash: const [
    LedgerCashLine(
      method: 'cash',
      labelAr: 'نقدي',
      piastres: '250000',
      pounds: '2500.00',
    ),
  ],
  stock: const [],
  scrap: const [],
  feed: const [],
  daySummary: const LedgerDaySummary(
    salePiastres: '0',
    purchasePiastres: '0',
    expensePiastres: '0',
    saleCount: 0,
    purchaseCount: 0,
    expenseCount: 0,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('day_reset parses and a missing key stays false', () {
    final reset = {
      ...calendarBody(),
      'day_reset': true,
      'last_closed_business_date': '2026-11-08',
      'day_summary': {
        ...(calendarBody()['day_summary']! as Map),
        'repair_piastres': '0',
        'repair_count': 0,
      },
    };
    final parsed = parseDailyLedger(reset);
    expect(parsed.dayReset, isTrue);
    expect(parsed.lastClosedBusinessDate, '2026-11-08');
    expect(parseDailyLedger(calendarBody()).dayReset, isFalse);
    expect(parseDailyLedger(calendarBody()).daySummary?.repairPiastres, '0');
    expect(parseDailyLedger(calendarBody()).daySummary?.repairCount, 0);
  });

  test('repair metric reads the day summary in pounds', () {
    final view = _view(reset: false).copyWithSummary('20000');
    final spec = ledgerMetricValues(view, 21)['repair']!;
    expect(spec.label, 'إيراد الصيانة');
    expect(spec.value, '200');
    // Same unit as the other money figures (2026-11-09 review).
    expect(spec.unit, '');
  });

  testWidgets(
    'a reset home shows the card, an empty sale book, and both buttons',
    (tester) async {
      var opened = false;
      String? archived;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ConfirmedLedgerDashboard(
                  ledger: _view(reset: true),
                  shopId: 'shop-reset',
                  onOpenDay: () => opened = true,
                  onOpenArchive: (date) => archived = date,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-day-reset')), findsOneWidget);
      expect(find.text('تم تقفيل اليوم'), findsOneWidget);
      expect(find.text('دفتر البيع'), findsOneWidget);
      expect(find.text('لا توجد عمليات حتى الآن.'), findsWidgets);
      await tester.tap(find.byKey(const Key('ledger-day-reset-open')));
      await tester.tap(find.byKey(const Key('ledger-day-reset-archive')));
      await tester.pump();
      expect(opened, isTrue);
      expect(archived, '2026-11-08');
      expect(
        find.textContaining('عرض يوم 8 نوفمبر 2026 في الدفاتر'),
        findsOneWidget,
      );
    },
  );

  testWidgets('an open day does not show the reset card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ConfirmedLedgerDashboard(
                ledger: _view(reset: false),
                shopId: 'shop-open',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-day-reset')), findsNothing);
  });
}

extension on DailyLedgerView {
  DailyLedgerView copyWithSummary(String repairPiastres) => DailyLedgerView(
    state: state,
    entitlementStatus: entitlementStatus,
    canConfirm: canConfirm,
    businessDay: businessDay,
    cash: cash,
    stock: stock,
    scrap: scrap,
    feed: feed,
    dayReset: dayReset,
    lastClosedBusinessDate: lastClosedBusinessDate,
    daySummary: LedgerDaySummary(
      salePiastres: '0',
      purchasePiastres: '0',
      expensePiastres: '0',
      saleCount: 0,
      purchaseCount: 0,
      expenseCount: 0,
      repairPiastres: repairPiastres,
      repairCount: 1,
    ),
  );
}

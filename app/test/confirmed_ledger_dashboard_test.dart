import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_home_charts.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ledger = DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: null,
  cash: [
    LedgerCashLine(
      method: 'cash',
      labelAr: 'نقدي',
      piastres: '12345',
      pounds: '123.45',
    ),
    LedgerCashLine(
      method: 'card',
      labelAr: 'فيزا',
      piastres: '55',
      pounds: '0.55',
    ),
  ],
  stock: [
    LedgerStockLine(
      category: 'jewelry',
      labelAr: 'مشغولات',
      karat: 18,
      milligrams: '1250',
      grams: '1.250',
      count: '1',
    ),
  ],
  scrap: [
    LedgerScrapLine(
      karat: 21,
      labelAr: 'كسر',
      milligrams: '500',
      grams: '0.500',
    ),
  ],
  feed: [],
);

Future<void> pumpDashboard(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  DailyLedgerView view = ledger,
  bool disableAnimations = false,
  Size size = const Size(800, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: disableAnimations
              ? media.copyWith(disableAnimations: true)
              : media,
          child: child!,
        );
      },
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConfirmedLedgerDashboard(ledger: view, shopId: 'shop-1'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cash and gold summaries use confirmed exact values', (
    tester,
  ) async {
    await pumpDashboard(tester);
    expect(find.text('124.00'), findsOneWidget);
    expect(find.text('1.750'), findsOneWidget);
    expect(find.text('عيار 18'), findsOneWidget);
    expect(find.text('عيار 21'), findsOneWidget);
    expect(find.text('71.5%'), findsOneWidget);
    expect(find.text('28.5%'), findsOneWidget);
    expect(find.text('99.6%'), findsOneWidget);
    expect(find.text('0.4%'), findsOneWidget);
    expect(find.text('أعلى وزن: عيار 18 · 1.250 جرام'), findsOneWidget);
    expect(find.text('أعلى رصيد: نقدي · 123.45 جنيه'), findsOneWidget);
    expect(find.text('لا توجد عمليات معروضة حتى الآن.'), findsOneWidget);
  });

  testWidgets('section visibility is saved and restored', (tester) async {
    await pumpDashboard(tester);
    await tester.tap(find.byKey(const Key('ledger-customize')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ledger-show-cash')));
    await tester.tap(find.byKey(const Key('ledger-show-cash')));
    await tester.pumpAndSettle();
    expect(find.text('مقارنة طرق النقدية'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpDashboard(tester);
    expect(find.text('مقارنة طرق النقدية'), findsNothing);
    expect(find.text('الذهب حسب العيار'), findsOneWidget);
  });

  testWidgets('narrow dark layout has no overflow', (tester) async {
    await pumpDashboard(
      tester,
      brightness: Brightness.dark,
      size: const Size(320, 900),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide light charts have no overflow', (tester) async {
    await pumpDashboard(tester, size: const Size(840, 1400));
    expect(find.byKey(const Key('ledger-gold-chart')), findsOneWidget);
    expect(find.byKey(const Key('ledger-cash-chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a karat highlights that share', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(tester, disableAnimations: true);
    await tester.ensureVisible(find.byKey(const Key('ledger-gold-share-18')));
    await tester.tap(find.byKey(const Key('ledger-gold-share-18')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('ledger-gold-share-18'))),
      matchesSemantics(
        label: 'عيار 18، 1.250 جرام، 71.5% من الإجمالي',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    await tester.tap(find.byKey(const Key('ledger-gold-share-18')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('ledger-gold-share-18'))),
      matchesSemantics(
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('full karat and payment charts fit phone and desktop', (
    tester,
  ) async {
    const dense = DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: 'active',
      canConfirm: false,
      businessDay: null,
      cash: [
        LedgerCashLine(
          method: 'cash',
          labelAr: 'نقدي',
          piastres: '1000000',
          pounds: '10000.00',
        ),
        LedgerCashLine(
          method: 'instant_transfer',
          labelAr: 'انستا',
          piastres: '50050',
          pounds: '500.50',
        ),
        LedgerCashLine(
          method: 'wallet',
          labelAr: 'محفظة',
          piastres: '250000',
          pounds: '2500.00',
        ),
        LedgerCashLine(
          method: 'card',
          labelAr: 'فيزا',
          piastres: '7525',
          pounds: '75.25',
        ),
      ],
      stock: [
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 24,
          milligrams: '1000',
          grams: '1.000',
          count: '1',
        ),
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 22,
          milligrams: '2000',
          grams: '2.000',
          count: '1',
        ),
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 21,
          milligrams: '3000',
          grams: '3.000',
          count: '1',
        ),
        LedgerStockLine(
          category: 'bullion',
          labelAr: 'سبائك',
          karat: 18,
          milligrams: '4000',
          grams: '4.000',
          count: '1',
        ),
        LedgerStockLine(
          category: 'coin',
          labelAr: 'جنيهات',
          karat: 14,
          milligrams: '500',
          grams: '0.500',
          count: '2',
        ),
      ],
      scrap: [
        LedgerScrapLine(
          karat: 21,
          labelAr: 'كسر',
          milligrams: '250',
          grams: '0.250',
        ),
      ],
      feed: [],
    );
    await pumpDashboard(
      tester,
      view: dense,
      brightness: Brightness.dark,
      size: const Size(320, 900),
      disableAnimations: true,
    );
    expect(find.text('عيار 24'), findsOneWidget);
    expect(find.text('عيار 14'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await pumpDashboard(
      tester,
      view: dense,
      size: const Size(840, 1600),
      disableAnimations: true,
    );
    expect(tester.takeException(), isNull);
  });

  test('chart shares stay exact and sum to 100 percent', () {
    expect(ChartShares.tenthsOfPercent([BigInt.from(500), BigInt.from(1250)]), [
      285,
      715,
    ]);
    expect(ChartShares.tenthsOfPercent([BigInt.from(12345), BigInt.from(55)]), [
      996,
      4,
    ]);
    expect(ChartShares.tenthsOfPercent([BigInt.one, BigInt.one, BigInt.one]), [
      334,
      333,
      333,
    ]);
    expect(ChartShares.tenthsOfPercent([BigInt.zero, BigInt.zero]), [0, 0]);
    expect(ChartShares.tenthsOfPercent([BigInt.from(5)]), [1000]);
    expect(ChartShares.label(715), '71.5%');
    expect(ChartShares.label(4), '0.4%');
    expect(ChartShares.label(1000), '100.0%');
  });
}

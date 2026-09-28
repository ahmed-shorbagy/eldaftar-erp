import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ConfirmedLedgerDashboard(ledger: ledger, shopId: 'shop-1'),
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
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDashboard(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}

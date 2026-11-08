import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_line_items.dart';
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
  Future<List<LedgerLineItem>?> Function(String operationId)? loadItems,
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
              child: ConfirmedLedgerDashboard(
                ledger: view,
                shopId: 'shop-1',
                loadItems: loadItems,
              ),
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

  testWidgets('cash and gold summaries use exact readable values', (
    tester,
  ) async {
    await pumpDashboard(tester);
    expect(find.text('124'), findsOneWidget);
    expect(find.byKey(const Key('ledger-total-gold')), findsNothing);
    expect(find.textContaining('عيار 18'), findsNothing);
    expect(find.textContaining('123.45'), findsNothing);
    expect(find.byKey(const Key('ledger-view-cash')), findsNothing);
    expect(find.byKey(const Key('ledger-view-gold')), findsNothing);
    await tester.tap(find.byKey(const Key('ledger-cash-methods')));
    await tester.pumpAndSettle();
    expect(find.textContaining('123.45'), findsOneWidget);
    expect(find.textContaining('0.55'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-gold-chart')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('money tiles hide the normalized gold line', (tester) async {
    await pumpDashboard(
      tester,
      view: DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: ledger.cash,
        stock: ledger.stock,
        scrap: ledger.scrap,
        feed: ledger.feed,
        daySummary: LedgerDaySummary(
          salePiastres: '150000',
          purchasePiastres: '80000',
          expensePiastres: '0',
          saleCount: 1,
          purchaseCount: 1,
          expenseCount: 0,
          goldByBucket: [
            LedgerGoldMovement(
              kind: 'sale',
              category: 'worked_jewelry',
              karat: 21,
              milligrams: '2500',
              count: '1',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'worked_jewelry',
              karat: 21,
              milligrams: '1800',
              count: '1',
            ),
          ],
        ),
      ),
    );
    expect(find.text('وزن مباع'), findsOneWidget);
    expect(find.text('وزن مشترى'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('ledger-metric-sale')),
        matching: find.textContaining('محيف'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('ledger-metric-purchase')),
        matching: find.textContaining('محيف'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sold weight sheet shows karats without piece counts', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      view: DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: ledger.cash,
        stock: ledger.stock,
        scrap: ledger.scrap,
        feed: ledger.feed,
        daySummary: LedgerDaySummary(
          salePiastres: '0',
          purchasePiastres: '0',
          expensePiastres: '0',
          saleCount: 2,
          purchaseCount: 0,
          expenseCount: 0,
          goldByBucket: [
            LedgerGoldMovement(
              kind: 'sale',
              category: 'worked_jewelry',
              karat: 18,
              milligrams: '1800',
              count: '2',
            ),
            LedgerGoldMovement(
              kind: 'sale',
              category: 'worked_jewelry',
              karat: 21,
              milligrams: '2500',
              count: '2',
            ),
          ],
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('ledger-sale-gold-weights')),
    );
    await tester.tap(find.byKey(const Key('ledger-sale-gold-weights')));
    await tester.pumpAndSettle();
    expect(find.text('عيار 18'), findsOneWidget);
    expect(find.text('عيار 21'), findsOneWidget);
    expect(find.textContaining('قطعة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchased weight sheet groups every category without counts', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      view: DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: ledger.cash,
        stock: ledger.stock,
        scrap: ledger.scrap,
        feed: ledger.feed,
        daySummary: LedgerDaySummary(
          salePiastres: '0',
          purchasePiastres: '0',
          expensePiastres: '0',
          saleCount: 0,
          purchaseCount: 4,
          expenseCount: 0,
          goldByBucket: [
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'worked_jewelry',
              karat: 21,
              milligrams: '2100',
              count: '3',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'bullion',
              karat: 24,
              milligrams: '10000',
              count: '1',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'coin',
              karat: 21,
              milligrams: '8000',
              count: '2',
            ),
            LedgerGoldMovement(
              kind: 'purchase',
              category: 'scrap',
              karat: 18,
              milligrams: '1555',
              count: '4',
            ),
          ],
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('ledger-metric-purchase_gold')),
    );
    await tester.tap(find.byKey(const Key('ledger-metric-purchase_gold')));
    await tester.pumpAndSettle();
    expect(find.text('مشغولات'), findsOneWidget);
    expect(find.text('سبائك'), findsOneWidget);
    expect(find.text('جنيهات'), findsOneWidget);
    expect(find.text('كسر'), findsOneWidget);
    expect(find.textContaining('2.10'), findsOneWidget);
    expect(find.textContaining('10.00'), findsOneWidget);
    expect(find.textContaining('8.00'), findsOneWidget);
    expect(find.textContaining('1.56'), findsOneWidget);
    expect(find.textContaining('قطعة'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty purchased weight names the empty state', (tester) async {
    await pumpDashboard(tester);
    await tester.ensureVisible(
      find.byKey(const Key('ledger-metric-purchase_gold')),
    );
    await tester.tap(find.byKey(const Key('ledger-metric-purchase_gold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-purchase-gold-empty')), findsOneWidget);
    expect(find.text('لا يوجد وزن مشترى.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sale cards preview three item rows and can reveal the rest', (
    tester,
  ) async {
    LedgerFeedLine sale(String id) => LedgerFeedLine(
      kind: 'sale',
      labelAr: 'بيع',
      operationId: id,
      actorDisplayName: 'مالك',
      occurredAt: '2026-10-12T09:00:00Z',
      occurredAtCairo: '2026-10-12T12:00:00',
    );
    List<LedgerLineItem> rows(int count) => [
      for (var index = 1; index <= count; index++)
        LedgerLineItem(name: 'صنف $index', grams: '1.000', karat: 21),
    ];
    DailyLedgerView viewFor(String id) => DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: 'active',
      canConfirm: false,
      businessDay: null,
      cash: ledger.cash,
      stock: ledger.stock,
      scrap: ledger.scrap,
      feed: [sale(id)],
    );

    await pumpDashboard(
      tester,
      view: viewFor('two'),
      loadItems: (_) async => rows(2),
    );
    expect(find.text('صنف 1'), findsOneWidget);
    expect(find.text('صنف 2'), findsOneWidget);
    expect(find.byKey(const Key('ledger-items-more-sale-two')), findsNothing);

    await pumpDashboard(
      tester,
      view: viewFor('five'),
      loadItems: (_) async => rows(5),
    );
    expect(find.text('صنف 1'), findsOneWidget);
    expect(find.text('صنف 2'), findsOneWidget);
    expect(find.text('صنف 3'), findsOneWidget);
    expect(find.text('صنف 4'), findsNothing);
    expect(find.text('إظهار المزيد'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('ledger-items-more-sale-five')),
    );
    await tester.tap(find.byKey(const Key('ledger-items-more-sale-five')));
    await tester.pumpAndSettle();
    expect(find.text('صنف 4'), findsOneWidget);
    expect(find.text('صنف 5'), findsOneWidget);
    expect(find.text('إظهار أقل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('note dots mark trade cards that carry a note', (tester) async {
    LedgerFeedLine row({
      required String id,
      required String kind,
      required bool hasNote,
      bool isDailyNote = false,
    }) => LedgerFeedLine(
      kind: kind,
      labelAr: kind == 'purchase' ? 'شراء' : 'بيع',
      operationId: id,
      actorDisplayName: 'مالك',
      occurredAt: '2026-10-12T09:00:00Z',
      occurredAtCairo: '2026-10-12T12:00:00',
      hasNote: hasNote,
      isDailyNote: isDailyNote,
    );
    await pumpDashboard(
      tester,
      view: DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: ledger.cash,
        stock: ledger.stock,
        scrap: ledger.scrap,
        feed: [
          row(id: 'noted', kind: 'sale', hasNote: true),
          row(id: 'plain', kind: 'purchase', hasNote: false),
          row(id: 'daily', kind: 'sale', hasNote: true, isDailyNote: true),
        ],
      ),
    );
    expect(find.byKey(const Key('ledger-note-dot-sale-noted')), findsOneWidget);
    expect(
      find.byKey(const Key('ledger-note-dot-purchase-plain')),
      findsNothing,
    );
    expect(find.byKey(const Key('ledger-note-dot-sale-daily')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty journals always show add and hide the details icon', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(390, 900));
    expect(find.text('عرض التفاصيل'), findsNothing);
    expect(find.byKey(const Key('ledger-new-sale')), findsOneWidget);
    expect(find.byKey(const Key('ledger-new-purchase')), findsOneWidget);
    expect(find.text('لا توجد عمليات حتى الآن.'), findsNWidgets(2));
    expect(find.byKey(const Key('ledger-journal-divider')), findsOneWidget);
  });

  testWidgets('the metric strip has no show-more sheet', (tester) async {
    await pumpDashboard(tester, size: const Size(390, 900));
    expect(find.byKey(const Key('ledger-more-metrics')), findsNothing);
    expect(find.byKey(const Key('ledger-all-metrics')), findsNothing);
    expect(find.byKey(const Key('ledger-customize')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger filters are small buttons', (tester) async {
    await pumpDashboard(tester, size: const Size(390, 900));
    expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
    expect(find.text('ترتيب العمليات'), findsNothing);
    final chip = find.ancestor(
      of: find.text('الأحدث'),
      matching: find.byType(ChoiceChip),
    );
    expect(chip, findsOneWidget);
    final size = tester.getSize(chip);
    expect(size.height, lessThan(36));
    expect(size.width, lessThan(120));
  });

  testWidgets('section visibility is saved and restored', (tester) async {
    await pumpDashboard(tester);
    await tester.tap(find.byKey(const Key('ledger-customize')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ledger-show-activity')));
    await tester.tap(find.byKey(const Key('ledger-show-activity')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-journal-sort')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpDashboard(tester);
    expect(find.byKey(const Key('ledger-journal-sort')), findsNothing);
    expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
  });

  testWidgets(
    'home summary tiles share one size and settings sit in the gear',
    (tester) async {
      await pumpDashboard(tester, size: const Size(390, 900));
      final cash = tester.getSize(find.byKey(const Key('ledger-total-cash')));
      final sale = tester.getSize(find.byKey(const Key('ledger-metric-sale')));
      expect(cash.width, sale.width);
      expect(cash.height, sale.height);
      expect(find.text('ملخص اليوم'), findsNothing);
      expect(find.text('دفتر حسب التاريخ'), findsNothing);
      expect(find.byKey(const ValueKey('ledger-normalize-21')), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      await tester.tap(find.byKey(const Key('ledger-customize')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ledger-normalize-21')), findsOneWidget);
    },
  );

  testWidgets('narrow dark layout has no overflow', (tester) async {
    await pumpDashboard(
      tester,
      brightness: Brightness.dark,
      size: const Size(320, 900),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide light cards have no overflow', (tester) async {
    await pumpDashboard(tester, size: const Size(840, 1400));
    expect(find.byKey(const Key('ledger-gold-chart')), findsNothing);
    expect(find.byKey(const Key('ledger-cash-chart')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory details stay off home and cash methods disclose', (
    tester,
  ) async {
    await pumpDashboard(tester);
    expect(find.text('مشغولات'), findsNothing);
    expect(find.byKey(const Key('ledger-view-gold')), findsNothing);
    expect(find.text('حركة الذهب'), findsNothing);
    await tester.tap(find.byKey(const Key('ledger-cash-methods')));
    await tester.pumpAndSettle();
    expect(find.textContaining('123.45'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
    expect(find.text('مشغولات'), findsNothing);
  });

  testWidgets('full karat and payment cards fit phone and desktop', (
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
    expect(find.byKey(const Key('ledger-view-gold')), findsNothing);
    await tester.tap(find.byKey(const Key('ledger-cash-methods')));
    await tester.pumpAndSettle();
    expect(find.textContaining('10,000'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
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

// «الجرد الفوري»: item × karat table, karat order and insights (ADR 0043).
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/data/inventory_codec.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inventory_widget_test.dart'
    show MemoryLocker, QuietInventory, QuietOpening, shopId, userId;

const _contract = {
  'rows': [
    {
      'item_name': 'سلاسل',
      'karat': 21,
      'count': '2',
      'count_known': true,
      'milligrams': '9500',
    },
    {
      'item_name': 'خواتم',
      'karat': 18,
      'count': '3',
      'count_known': true,
      'milligrams': '4250',
    },
    {
      'item_name': 'خواتم',
      'karat': 21,
      'count': '12',
      'count_known': true,
      'milligrams': '45230',
    },
    {
      'item_name': 'دبل',
      'karat': 22,
      'count': '0',
      'count_known': false,
      'milligrams': '3000',
    },
    {
      'item_name': 'رصيد افتتاحي مجمّع',
      'karat': 14,
      'count': '1',
      'count_known': true,
      'milligrams': '2000',
    },
  ],
  'scrap': [
    {'karat': 21, 'milligrams': '100000'},
  ],
  'karats': [14, 18, 21, 22],
};

QuantityTriple _q(int mg, int? count) => QuantityTriple(
  availableMilligrams: BigInt.from(mg),
  pendingMilligrams: BigInt.zero,
  heldMilligrams: BigInt.zero,
  availableCount: count == null ? null : BigInt.from(count),
  pendingCount: count == null ? null : BigInt.zero,
  heldCount: count == null ? null : BigInt.zero,
);

class _GridInventory extends QuietInventory {
  _GridInventory({this.fail = false}) : super(null);
  final bool fail;
  final lotQueries = <({String? category, int? karat, String? query})>[];

  @override
  Future<InventoryItemGrid> itemGrid({required String callerUserId}) async {
    if (fail) throw const InventoryReadException('unavailable');
    return parseInventoryItemGrid(_contract);
  }

  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) async => InventoryTotals([
    InventoryBucket(
      category: 'worked_jewelry',
      karat: 21,
      quantities: _q(54730, 14),
    ),
    InventoryBucket(
      category: 'worked_jewelry',
      karat: 18,
      quantities: _q(4250, 3),
    ),
    InventoryBucket(category: 'scrap', karat: 21, quantities: _q(100000, null)),
    InventoryBucket(category: 'bullion', karat: 24, quantities: _q(8000, 1)),
    InventoryBucket(category: 'coin', karat: 21, quantities: _q(16000, 2)),
  ]);

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) async {
    lotQueries.add((category: category, karat: karat, query: query));
    return const LotPage([], null);
  }
}

Future<_GridInventory> _pump(
  WidgetTester tester, {
  double width = 390,
  Brightness brightness = Brightness.light,
  _GridInventory? gateway,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final inventory = gateway ?? _GridInventory();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: InventoryScreen(
        gateway: inventory,
        statusGateway: QuietOpening(),
        userId: userId,
        shopId: shopId,
        shopName: 'متجر',
        readOnly: true,
        store: MemoryLocker(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return inventory;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('domain', () {
    test('codec reads the contract and orders built-in items first', () {
      final grid = parseInventoryItemGrid(_contract);
      expect(grid.rows.map((row) => row.itemName).take(12).toList(), [
        'جنيهات',
        'محابس',
        'توينز',
        'غوايش',
        'سلاسل',
        'انسيالات',
        'حلقان',
        'اساور',
        'تعاليق',
        'كوليهات',
        'دبل',
        'خواتم',
      ]);
      expect(grid.rows.last.itemName, 'رصيد افتتاحي مجمّع');
      final rings = grid.rows.singleWhere((row) => row.itemName == 'خواتم');
      expect(rings.cells[21]!.count, BigInt.from(12));
      expect(grid.scrapByKarat[21], BigInt.from(100000));
      expect(grid.totals[21]!.count, BigInt.from(14));
      expect(grid.totals[21]!.milligrams, BigInt.from(54730));
      expect(grid.totals[22]!.countKnown, isFalse);
    });
    test('visible karats: first two, all when expanded', () {
      expect(visibleInventoryKarats([18, 21, 22, 14], expanded: false), [
        18,
        21,
      ]);
      expect(visibleInventoryKarats([18, 21, 22, 14], expanded: true), [
        18,
        21,
        22,
        14,
      ]);
      expect(visibleInventoryKarats([22, 14, 18, 21], expanded: false), [
        22,
        14,
      ]);
    });
    test('a bad saved order gives the default', () {
      expect(parseInventoryKaratOrder(['18', '18', '21', '22']), [
        18,
        21,
        22,
        14,
      ]);
      expect(parseInventoryKaratOrder(['24', '18', '21', '22']), [
        18,
        21,
        22,
        14,
      ]);
      expect(parseInventoryKaratOrder(null), [18, 21, 22, 14]);
      expect(parseInventoryKaratOrder(['22', '14', '18', '21']), [
        22,
        14,
        18,
        21,
      ]);
    });
    test('insights add buckets and mark unknown counts', () {
      final insights = inventoryInsights(
        [
          InventoryInsightBucket(
            category: 'worked_jewelry',
            availableMilligrams: BigInt.from(1000),
            availableCount: BigInt.one,
          ),
          InventoryInsightBucket(
            category: 'worked_jewelry',
            availableMilligrams: BigInt.from(500),
          ),
          InventoryInsightBucket(
            category: 'coin',
            availableMilligrams: BigInt.from(8000),
            availableCount: BigInt.two,
          ),
        ],
        {'cash': BigInt.from(150), 'card': BigInt.from(50)},
      );
      expect(insights.workedMilligrams, BigInt.from(1500));
      expect(insights.workedCountKnown, isFalse);
      expect(insights.coinCount, BigInt.two);
      expect(insights.cashPiastres, BigInt.from(200));
    });
  });

  testWidgets('default shows 18 and 21; the chip adds 22 and 14 and stays', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('الأصناف حسب العيار'), findsOneWidget);
    expect(find.text('عيار 18'), findsWidgets);
    expect(find.text('عيار 21'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-grid-header')),
        matching: find.text('عيار 22'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('inventory-grid-more-karats')));
    await tester.pumpAndSettle();
    for (final karat in [22, 14]) {
      expect(
        find.descendant(
          of: find.byKey(const Key('inventory-grid-header')),
          matching: find.text('عيار $karat'),
        ),
        findsOneWidget,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('inventory_karat_expanded_$shopId'), isTrue);
    await _pump(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-grid-header')),
        matching: find.text('عيار 14'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a saved order puts 22 and 14 first', (tester) async {
    SharedPreferences.setMockInitialValues({
      'inventory_karat_order_$shopId': ['22', '14', '18', '21'],
    });
    await _pump(tester);
    final header = find.byKey(const Key('inventory-grid-header'));
    expect(
      find.descendant(of: header, matching: find.text('عيار 22')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('عيار 18')),
      findsNothing,
    );
  });

  testWidgets('the order sheet saves a new order', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('inventory-grid-order')));
    await tester.pumpAndSettle();
    expect(find.text('أول عيارين يظهران دائمًا.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-karat-up-22')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-karat-up-22')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-karat-order-save')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('inventory_karat_order_$shopId'), [
      '22',
      '18',
      '21',
      '14',
    ]);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-grid-header')),
        matching: find.text('عيار 22'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cells, unknown counts, scrap and totals rows', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('inventory-grid-more-karats')));
    await tester.pumpAndSettle();
    final ring21 = find.byKey(const Key('inventory-grid-cell-خواتم-21'));
    await tester.ensureVisible(ring21);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: ring21, matching: find.text('12')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ring21, matching: find.text('45.23')),
      findsOneWidget,
    );
    final unknown = find.byKey(const Key('inventory-grid-cell-دبل-22'));
    await tester.ensureVisible(unknown);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: unknown, matching: find.text('—')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('inventory-grid-scrap')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-grid-scrap')),
        matching: find.text('100.00'),
      ),
      findsOneWidget,
    );
    final total = find.byKey(const Key('inventory-grid-total'));
    expect(find.descendant(of: total, matching: find.text('14')), findsWidgets);
    expect(find.text('رصيد افتتاحي (بدون صنف)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-grid')),
        matching: find.textContaining('مشغولات'),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping a cell filters the lots to that item and karat', (
    tester,
  ) async {
    final inventory = await _pump(tester);
    inventory.lotQueries.clear();
    final cell = find.byKey(const Key('inventory-grid-cell-خواتم-21'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(inventory.lotQueries.last, (
      category: 'worked_jewelry',
      karat: 21,
      query: 'خواتم',
    ));
  });

  test('figure values follow the old-app carousel order', () {
    final figures = inventoryFigures([
      (
        category: 'worked_jewelry',
        karat: 21,
        milligrams: BigInt.from(54730),
        count: BigInt.from(14),
      ),
      (
        category: 'worked_jewelry',
        karat: 18,
        milligrams: BigInt.from(4250),
        count: BigInt.from(3),
      ),
      (
        category: 'scrap',
        karat: 21,
        milligrams: BigInt.from(100000),
        count: null,
      ),
      (
        category: 'bullion',
        karat: 24,
        milligrams: BigInt.from(8000),
        count: BigInt.one,
      ),
      (
        category: 'coin',
        karat: 21,
        milligrams: BigInt.from(16000),
        count: BigInt.two,
      ),
    ], const {});
    expect(figures.map((figure) => figure.id).toList(), [
      'karat_18',
      'karat_21',
      'bullion_count',
      'bullion_weight',
      'cash',
      'scrap_18',
      'scrap_21',
      'scrap_as_21',
      'weight_21',
      'weight_21_with_scrap',
      'weight_21_with_cash',
    ]);
    expect(
      figures.firstWhere((f) => f.id == 'karat_18').milligrams,
      BigInt.from(4250),
    );
    // Jewelry only (C-D5): coins are not part of «عيار 21».
    expect(
      figures.firstWhere((f) => f.id == 'karat_21').milligrams,
      BigInt.from(54730),
    );
    expect(
      figures.firstWhere((f) => f.id == 'bullion_count').count,
      BigInt.one,
    );
    expect(
      figures.firstWhere((f) => f.id == 'bullion_weight').milligrams,
      BigInt.from(8000),
    );
    expect(figures.firstWhere((f) => f.id == 'cash').count, BigInt.zero);
    expect(
      figures.firstWhere((f) => f.id == 'scrap_21').milligrams,
      BigInt.from(100000),
    );
    expect(figures.last.cashCalculator, isTrue);
    expect(figures.last.awaitingPrice, isTrue);
    // Jewelry and bullion only, Σ(mg × karat) ÷ 21 rounded half-up to
    // centigrams: (4250×18 + 54730×21 + 8000×24) ÷ 21 = 67.5157 g → 67.520.
    final without = figures.firstWhere((f) => f.id == 'weight_21');
    expect(without.label, 'اجمالي الوزنة 21 (مشغولات + سبائك)');
    expect(without.milligrams, BigInt.from(67520));
    final withScrap = figures.firstWhere((f) => f.id == 'weight_21_with_scrap');
    expect(withScrap.milligrams, without.milligrams + BigInt.from(100000));
    final priced = inventoryFigures(
      [
        (
          category: 'worked_jewelry',
          karat: 21,
          milligrams: BigInt.from(10000),
          count: BigInt.one,
        ),
      ],
      {'cash': BigInt.from(500000)},
      cashPricePiastresPerGram: BigInt.from(250000),
    ).last;
    // 10 g + 5,000 EGP ÷ 2,500 EGP/g = 12.000 g.
    expect(priced.awaitingPrice, isFalse);
    expect(priced.milligrams, BigInt.from(12000));
  });

  testWidgets('figure carousel shows the first tiles and cash calculator', (
    tester,
  ) async {
    await _pump(tester, width: 1280);
    expect(find.byKey(const Key('inventory-figures')), findsOneWidget);
    Finder tile(String name, String text) => find.descendant(
      of: find.byKey(Key('inventory-figure-$name')),
      matching: find.text(text),
    );
    expect(tile('karat_18', '4.25'), findsOneWidget);
    expect(tile('karat_21', '54.73'), findsOneWidget);
    expect(tile('bullion_count', '1'), findsOneWidget);
    expect(tile('bullion_weight', '8.00'), findsOneWidget);
  });

  testWidgets('a failed table read keeps the page and offers a retry', (
    tester,
  ) async {
    await _pump(tester, gateway: _GridInventory(fail: true));
    expect(find.text('تعذر تحميل جدول الأصناف. أعد المحاولة.'), findsOneWidget);
    expect(find.byKey(const Key('inventory-grid-retry')), findsOneWidget);
    expect(find.byKey(const Key('inventory-search')), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('375 px fits two karats without scroll (${brightness.name})', (
      tester,
    ) async {
      await _pump(tester, width: 375, brightness: brightness);
      expect(find.byKey(const Key('inventory-grid-scroll')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('inventory-grid-more-karats')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a 375 px phone fits four karats without scroll', (tester) async {
    await _pump(tester, width: 375);
    await tester.tap(find.byKey(const Key('inventory-grid-more-karats')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-grid-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop width shows four karats without scroll', (tester) async {
    await _pump(tester, width: 1280);
    await tester.tap(find.byKey(const Key('inventory-grid-more-karats')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-grid-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

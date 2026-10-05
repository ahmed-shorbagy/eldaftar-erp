import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_command_flow.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_forms.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_screen.dart';
import 'package:eldafttar/src/features/inventory/presentation/trader_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const traderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const userId = 'owner-1';
const shopId = 'shop-1';

DayAnchor get day =>
    (DayAnchor.tryCreate(dayId, '2') as InventoryAccepted<DayAnchor>).value;

class _Guide implements OnboardingStore {
  _Guide({this.complete = false});
  final bool complete;

  @override
  Future<bool> isComplete(String path) async => complete;

  @override
  Future<int> readStep(String path) async => 0;

  @override
  Future<void> saveStep(String path, int step) async {}

  @override
  Future<void> markComplete(String path) async {}
}

class _Locker implements FinancialCommandLocker {
  @override
  Future<void> clear(String userId, String shopId, String key) async {}

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      null;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {}
}

class _Opening implements OpeningGateway {
  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => Future.error(UnimplementedError());

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      const DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: [],
        stock: [],
        scrap: [],
        feed: [],
      );

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();
}

class _Day implements FinancialGateway {
  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(
        state: 'open',
        dayId: dayId,
        businessDate: '2026-10-04',
        dayVersion: 2,
      );

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) => Future.error(UnimplementedError());

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) => Future.error(UnimplementedError());

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) => Future.error(UnimplementedError());

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) => Future.error(UnimplementedError());

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) => Future.error(UnimplementedError());
}

class _Inventory implements InventoryGateway {
  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) async => InventoryTotals([
    InventoryBucket(
      category: 'worked_jewelry',
      karat: 21,
      quantities: QuantityTriple(
        availableMilligrams: BigInt.from(10000),
        pendingMilligrams: BigInt.from(2500),
        heldMilligrams: BigInt.from(4000),
        availableCount: BigInt.one,
        pendingCount: BigInt.one,
        heldCount: BigInt.one,
      ),
    ),
  ]);

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) async => const LotPage([], null);

  @override
  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  }) async => const MovementPage([], null);

  @override
  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  }) async => const ReceiptPage.ready([], null);

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.missing();

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.missing();

  @override
  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) async => ReadPage.ready([
    TraderObligation(
      operationId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      unit: 'egp_piastres',
      karat: null,
      original: BigInt.from(50000),
      remaining: BigInt.from(15050),
      createdAt: '2026-10-04T00:00:00Z',
      cursor: '2026-10-04T00:00:00Z|ffffffff-ffff-4fff-8fff-ffffffffffff',
    ),
  ], null);

  @override
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => TraderPage([
    TraderSummary(
      id: traderId,
      displayName: 'تاجر الأمانة',
      phone: '01000000000',
      active: true,
      createdAt: '2026-10-04T00:00:00Z',
      cursor: '2026-10-04T00:00:00Z|$traderId',
    ),
  ], null);

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) async => TraderDetail(
    id: traderId,
    displayName: 'تاجر الأمانة',
    phone: '01000000000',
    note: 'أمانة مشغولات',
    active: true,
    createdAt: '2026-10-04T00:00:00Z',
    originalHeldMilligrams: BigInt.from(10000),
    currentHeldMilligrams: BigInt.from(4000),
    pendingReceiptCount: BigInt.zero,
    cashPayableRemainingPiastres: BigInt.from(15050),
    goldRemaining: [
      TraderGoldBalance(
        karat: 21,
        initialMilligrams: BigInt.from(5000),
        remainingMilligrams: BigInt.from(2000),
      ),
    ],
    buckets: [
      TraderHolding(
        category: 'worked_jewelry',
        karat: 21,
        originalMilligrams: BigInt.from(10000),
        originalCount: BigInt.one,
        currentMilligrams: BigInt.from(4000),
        currentCount: BigInt.one,
        pendingReceiptCount: BigInt.zero,
      ),
    ],
  );

  @override
  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  }) async => TraderActivityPage([
    TraderActivity(
      operationId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      kind: 'inventory_receipt',
      shopSequence: '12',
      receiptId: null,
      createdAt: '2026-10-04T00:00:00Z',
      cursor: '2026-10-04T00:00:00Z|ffffffff-ffff-4fff-8fff-ffffffffffff',
    ),
  ], '2026-10-04T00:00:00Z|ffffffff-ffff-4fff-8fff-ffffffffffff');

  @override
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => const FinancialUnknown();
}

/// Page list only. Text fields add their own [Scrollable]s.
Finder get _pageScroll => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      widget.axisDirection == AxisDirection.down &&
      !widget.excludeFromSemantics,
);

Widget _host(Widget child, Brightness brightness, GlobalKey capture) =>
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: child,
      builder: (context, page) => RepaintBoundary(key: capture, child: page),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/m03-inventory-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });

  for (final width in [320.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      final suffix = '${width.toInt()}-${brightness.name}';
      testWidgets('inventory totals $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            InventoryScreen(
              gateway: _Inventory(),
              statusGateway: _Opening(),
              dayGateway: _Day(),
              userId: userId,
              shopId: shopId,
              shopName: 'متجر تجريبي',
              readOnly: false,
              onboardingStore: _Guide(complete: true),
              store: _Locker(),
            ),
            brightness,
            capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('inventory-available')),
          300,
          scrollable: _pageScroll,
        );
        await _capture(tester, capture, 'inventory-$suffix');
        expect(find.byKey(const Key('inventory-available')), findsOneWidget);
        expect(find.byKey(const Key('inventory-pending')), findsOneWidget);
        expect(find.byKey(const Key('inventory-held')), findsOneWidget);
      }, timeout: const Timeout(Duration(minutes: 2)));

      testWidgets('trader detail $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            TraderScreen(
              gateway: _Inventory(),
              statusGateway: _Opening(),
              dayGateway: _Day(),
              userId: userId,
              shopId: shopId,
              shopName: 'متجر تجريبي',
              readOnly: false,
              onboardingStore: _Guide(complete: true),
              store: _Locker(),
              sharePdf: (_) async {},
            ),
            brightness,
            capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('trader-row-$traderId')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('trader-holding')),
          300,
          scrollable: _pageScroll,
        );
        await _capture(tester, capture, 'trader-$suffix');
        expect(find.textContaining('ما زال في الحيازة'), findsOneWidget);
      }, timeout: const Timeout(Duration(minutes: 2)));

      testWidgets('reviewed addition $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        final flow = InventoryCommandFlow(
          gateway: _Inventory(),
          statusGateway: _Opening(),
          store: _Locker(),
        );
        await tester.pumpWidget(
          _host(
            InventoryAdditionForm(
              scope: InventoryFormScope(
                flow: flow,
                userId: userId,
                shopId: shopId,
                readOnly: false,
                day: day,
                reloadDay: () async => day,
              ),
            ),
            brightness,
            capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('add-name')), 'خاتم');
        await tester.enterText(find.byKey(const Key('add-grams')), '4.998');
        await tester.enterText(find.byKey(const Key('add-reason')), 'وزن فعلي');
        await tester.scrollUntilVisible(
          find.byKey(const Key('command-review')),
          200,
          scrollable: _pageScroll,
        );
        await tester.tap(find.byKey(const Key('command-review')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('command-effects')),
          200,
          scrollable: _pageScroll,
        );
        await _capture(tester, capture, 'addition-review-$suffix');
        expect(find.textContaining('4.998'), findsWidgets);
      }, timeout: const Timeout(Duration(minutes: 2)));

      testWidgets(
        'inventory without guidance $suffix',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final capture = GlobalKey();
          await tester.pumpWidget(
            _host(
              InventoryScreen(
                gateway: _Inventory(),
                statusGateway: _Opening(),
                dayGateway: _Day(),
                userId: userId,
                shopId: shopId,
                shopName: 'متجر تجريبي',
                readOnly: false,
                onboardingStore: _Guide(),
                store: _Locker(),
              ),
              brightness,
              capture,
            ),
          );
          await _capture(tester, capture, 'guide-$suffix');
          expect(find.byKey(const Key('onboarding-guide')), findsNothing);
          expect(find.byKey(const Key('onboarding-skip')), findsNothing);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

bool tahomaReady = false;

const shopId = '11111111-1111-4111-8111-111111111111';
const ownerName = 'منى حسن';
const cairoStamp = '26 سبتمبر 2026، 03:30:00';
const captureDir = 'build/opening-review';

const primaryStems = <String>[
  'uninitialized-top',
  'uninitialized-lower',
  'review-top',
  'review-lower',
  'confirmed-top',
  'confirmed-movement',
  'confirmed-lower',
  'pending-activation',
];

ShopAccount account(ShopEntitlement entitlement) => ShopAccount(
  id: shopId,
  name: 'ذهب الجيزة',
  role: 'owner',
  entitlement: entitlement,
);

DailyLedgerView emptyLedger({String entitlement = 'active'}) => DailyLedgerView(
  state: 'uninitialized',
  entitlementStatus: entitlement,
  canConfirm: entitlement == 'active',
  businessDay: null,
  cash: const [],
  stock: const [],
  scrap: const [],
  feed: const [],
);

DailyLedgerView confirmedLedger({String entitlement = 'active'}) =>
    DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: entitlement,
      canConfirm: false,
      businessDay: const LedgerBusinessDay(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        openedAt: '2026-09-26T00:30:00+00:00',
      ),
      cash: const [
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
      stock: const [
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 14,
          milligrams: '1250',
          grams: '1.250',
          count: '2',
        ),
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 18,
          milligrams: '5000',
          grams: '5.000',
          count: '3',
        ),
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 21,
          milligrams: '2560',
          grams: '2.560',
          count: '1',
        ),
        LedgerStockLine(
          category: 'worked_jewelry',
          labelAr: 'مشغولات',
          karat: 22,
          milligrams: '830',
          grams: '0.830',
          count: '4',
        ),
        LedgerStockLine(
          category: 'bullion',
          labelAr: 'سبائك',
          karat: 24,
          milligrams: '10000',
          grams: '10.000',
          count: '1',
        ),
      ],
      scrap: const [
        LedgerScrapLine(
          karat: 18,
          labelAr: 'كسر',
          milligrams: '1500',
          grams: '1.500',
        ),
        LedgerScrapLine(
          karat: 24,
          labelAr: 'كسر',
          milligrams: '500',
          grams: '0.500',
        ),
      ],
      feed: const [
        LedgerFeedLine(
          kind: 'opening_balances_confirmed',
          labelAr: 'رصيد افتتاحي',
          operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          actorDisplayName: ownerName,
          occurredAt: '2026-09-26T00:30:00+00:00',
          occurredAtCairo: '2026-09-26T03:30:00',
        ),
      ],
      daySummary: const LedgerDaySummary(
        salePiastres: '420025',
        purchasePiastres: '200000',
        expensePiastres: '50000',
        saleCount: 1,
        purchaseCount: 1,
        expenseCount: 1,
        goldByBucket: [
          LedgerGoldMovement(
            kind: 'sale',
            category: 'worked_jewelry',
            karat: 18,
            milligrams: '1830',
            count: '1',
          ),
          LedgerGoldMovement(
            kind: 'purchase',
            category: 'scrap',
            karat: 21,
            milligrams: '3000',
            count: '0',
          ),
        ],
      ),
    );

class CaptureGateway implements OpeningGateway {
  CaptureGateway(this.view);

  DailyLedgerView view;
  Completer<ConfirmResult>? confirmGate;

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) {
    final gate = confirmGate;
    if (gate != null) return gate.future;
    return Future<ConfirmResult>.value(const ConfirmUnknown());
  }

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async => view;

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusUnknown();
}

class CaptureStore implements PendingOpeningStore {
  @override
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  }) async => null;

  @override
  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {}

  @override
  Future<void> retire({required String userId, required String shopId}) async {}
}

class CaptureGuideStore implements OnboardingStore {
  @override
  Future<bool> isComplete(String path) async => false;
  @override
  Future<int> readStep(String path) async => 0;
  @override
  Future<void> saveStep(String path, int step) async {}
  @override
  Future<void> markComplete(String path) async {}
}

class CaptureShops implements ShopAccountGateway {
  CaptureShops(this.accounts);

  final List<ShopAccount> accounts;

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => accounts;
}

ThemeData withTahoma(ThemeData theme) {
  if (!tahomaReady) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Tahoma'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Tahoma'),
  );
}

void expectNoException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void expectOnScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final top = tester.getTopLeft(finder).dy;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  expect(top, greaterThanOrEqualTo(-1));
  expect(top, lessThan(height - 1));
}

void expectThemeAndRtl(WidgetTester tester, Brightness brightness) {
  final title = find.byKey(const Key('ledger-title'));
  expect(title, findsOneWidget);
  final context = tester.element(title);
  expect(Theme.of(context).brightness, brightness);
  expect(Directionality.of(context), TextDirection.rtl);
  expect(find.text('الدفتر اليومي'), findsOneWidget);
}

void expectConfirmedFeed(WidgetTester tester) {
  expect(find.text('رصيد افتتاحي'), findsOneWidget);
  expect(find.text('$ownerName · $cairoStamp'), findsOneWidget);
  expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
  expect(find.text('مراجعة الأرصدة الافتتاحية'), findsNothing);
}

void expectReviewEnabled(WidgetTester tester) {
  expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
  expect(find.text('إعداد الأرصدة الافتتاحية'), findsNothing);
  final button = tester.widget<FilledButton>(
    find.byKey(const Key('confirm-opening')),
  );
  expect(button.onPressed, isNotNull);
}

void expectPendingDisabled(WidgetTester tester) {
  expect(find.byKey(const Key('opening-pending')), findsOneWidget);
  expect(find.text('بانتظار تأكيد الخادم'), findsOneWidget);
  expect(find.byKey(const Key('confirm-opening')), findsNothing);
  expect(find.byKey(const Key('back-to-edit')), findsNothing);
  expect(find.byKey(const Key('review-values')), findsNothing);
}

void expectExpiredNoWrite(WidgetTester tester) {
  expect(find.text('منتهي - للقراءة فقط'), findsOneWidget);
  expect(find.byKey(const Key('confirm-opening')), findsNothing);
  expect(find.byKey(const Key('review-values')), findsNothing);
  expect(find.byKey(const Key('add-stock')), findsNothing);
  expect(find.byKey(const Key('add-scrap')), findsNothing);
}

Future<void> capture(WidgetTester tester, String name) async {
  expectNoException(tester);
  await tester.pump();
  expectNoException(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('opening-capture-boundary')),
  );
  expect(boundary.size.width, greaterThan(0));
  expect(boundary.size.height, greaterThan(0));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    expect(bytes.length, greaterThan(8));
    final file = File('$captureDir/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  });
}

Future<void> captureGuide(WidgetTester tester, String name) async {
  expectNoException(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('opening-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '${Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/onboarding-review'}/$name',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

Future<void> show(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  final list = find.byKey(const Key('ledger-scroll'));
  expect(list, findsOneWidget);
  final controller = tester.widget<ListView>(list).controller!;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  controller.jumpTo(0);
  await tester.pump();
  for (var attempt = 0; attempt < 30; attempt++) {
    expectNoException(tester);
    if (target.evaluate().isEmpty) {
      final next = controller.position.maxScrollExtent;
      if (next == controller.offset) break;
      controller.jumpTo(next);
      await tester.pump();
      continue;
    }
    final dy = tester.getTopLeft(target).dy;
    if (dy >= 8 && dy < height - 48) return;
    final delta = dy >= height - 48 ? 240.0 : -240.0;
    final next = (controller.offset + delta).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if (next == controller.offset) return;
    controller.jumpTo(next);
    await tester.pump();
  }
  expect(target, findsOneWidget);
}

Future<void> jump(WidgetTester tester, double offset) async {
  final controller = tester
      .widget<ListView>(find.byKey(const Key('ledger-scroll')))
      .controller!;
  final max = controller.position.maxScrollExtent;
  controller.jumpTo(offset.clamp(0, max));
  await tester.pump();
  expectNoException(tester);
}

Future<void> blank(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> frames(WidgetTester tester, {int count = 6}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expectNoException(tester);
}

Future<void> chooseDropdown(WidgetTester tester, Key key, String option) async {
  await show(tester, key);
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expectNoException(tester);
  await tester.tap(find.text(option).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expectNoException(tester);
}

Future<void> fillFullExample(WidgetTester tester) async {
  const cash = <String, String>{
    'cash-cash': '10000',
    'cash-instant_transfer': '500.50',
    'cash-wallet': '2500',
    'cash-card': '75.25',
  };
  for (final entry in cash.entries) {
    final key = Key(entry.key);
    await show(tester, key);
    await tester.enterText(find.byKey(key), entry.value);
    await tester.pump();
  }
  for (var extra = 0; extra < 4; extra++) {
    await show(tester, const Key('add-stock'));
    await tester.tap(find.byKey(const Key('add-stock')));
    await tester.pump();
  }
  await show(tester, const Key('add-scrap'));
  await tester.tap(find.byKey(const Key('add-scrap')));
  await tester.pump();

  const stock = <(int, String, String)>[
    (0, '5', '3'),
    (1, '2.560', '1'),
    (2, '1.250', '2'),
    (3, '0.830', '4'),
    (4, '10', '1'),
  ];
  for (final row in stock) {
    await show(tester, Key('stock-grams-${row.$1}'));
    await tester.enterText(find.byKey(Key('stock-grams-${row.$1}')), row.$2);
    await show(tester, Key('stock-count-${row.$1}'));
    await tester.enterText(find.byKey(Key('stock-count-${row.$1}')), row.$3);
    await tester.pump();
  }
  await chooseDropdown(tester, const Key('stock-category-4'), 'سبائك');
  await chooseDropdown(
    tester,
    const ValueKey('stock-karat-1-worked_jewelry-18'),
    '21',
  );
  await chooseDropdown(
    tester,
    const ValueKey('stock-karat-2-worked_jewelry-18'),
    '14',
  );
  await chooseDropdown(
    tester,
    const ValueKey('stock-karat-3-worked_jewelry-18'),
    '22',
  );
  await show(tester, const Key('scrap-grams-0'));
  await tester.enterText(find.byKey(const Key('scrap-grams-0')), '1.500');
  await show(tester, const Key('scrap-grams-1'));
  await tester.enterText(find.byKey(const Key('scrap-grams-1')), '0.500');
  await chooseDropdown(tester, const Key('scrap-karat-1'), '24');
  await show(tester, const Key('review-values'));
  await tester.tap(find.byKey(const Key('review-values')));
  await tester.pump();
  expectNoException(tester);
  expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
  expect(find.text('10000.00'), findsWidgets);
  expect(find.text('500.50'), findsWidgets);
  expect(find.text('2500.00'), findsWidgets);
  expect(find.text('75.25'), findsWidgets);
  expect(find.text('مشغولات عيار 18'), findsOneWidget);
  expect(find.text('مشغولات عيار 21'), findsOneWidget);
  expect(find.text('مشغولات عيار 14'), findsOneWidget);
  expect(find.text('مشغولات عيار 22'), findsOneWidget);
  expect(find.text('سبائك عيار 24'), findsOneWidget);
  expect(find.text('5.000 جرام'), findsWidgets);
  expect(find.text('كسر عيار 18'), findsOneWidget);
  expect(find.text('كسر عيار 24'), findsOneWidget);
  expect(find.text('العدد'), findsNWidgets(5));
}

Future<void> captureScrollSlots(
  WidgetTester tester, {
  required String stem,
  required String label,
  required Finder topMarker,
  required Finder lowerMarker,
  required bool middleWhenTall,
}) async {
  await jump(tester, 0);
  expectOnScreen(tester, topMarker);
  await capture(tester, '$stem-top-$label.png');
  final controller = tester
      .widget<ListView>(find.byKey(const Key('ledger-scroll')))
      .controller!;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  if (middleWhenTall && controller.position.maxScrollExtent > height) {
    await jump(tester, controller.position.maxScrollExtent / 2);
    await capture(tester, '$stem-middle-$label.png');
  }
  await jump(tester, controller.position.maxScrollExtent);
  expectOnScreen(tester, lowerMarker);
  await capture(tester, '$stem-lower-$label.png');
}

Future<void> pumpLedger(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required ShopAccount shop,
  required OpeningGateway gateway,
  required String screenKey,
  OnboardingStore? onboardingStore,
}) async {
  await blank(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final theme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: withTahoma(theme),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: RepaintBoundary(
        key: const Key('opening-capture-boundary'),
        child: DailyLedgerScreen(
          key: ValueKey(screenKey),
          shop: shop,
          gateway: gateway,
          store: CaptureStore(),
          userId: 'user-1',
          onboardingStore: onboardingStore,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          onChangeShop: () {},
        ),
      ),
    ),
  );
  await frames(tester);
  expect(find.byKey(const Key('ledger-loading')), findsNothing);
  expectThemeAndRtl(tester, brightness);
}

Future<void> captureMatrix(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required bool includeBigint,
}) async {
  final label = '${brightness.name}-${size.width.toInt()}';
  final wide = size.width > 1000 ? 'desktop' : 'phone';

  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.active),
    gateway: CaptureGateway(emptyLedger()),
    screenKey: 'uninitialized-$label',
  );
  expect(find.text('إعداد الأرصدة الافتتاحية'), findsOneWidget);
  expect(find.text('ذهب الجيزة'), findsOneWidget);
  expect(
    tester
        .widget<FilledButton>(find.byKey(const Key('review-values')))
        .onPressed,
    isNotNull,
  );
  await captureScrollSlots(
    tester,
    stem: 'uninitialized',
    label: label,
    topMarker: find.text('إعداد الأرصدة الافتتاحية'),
    lowerMarker: find.byKey(const Key('review-zero')),
    middleWhenTall: false,
  );

  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.active),
    gateway: CaptureGateway(emptyLedger()),
    screenKey: 'review-$label-$wide',
  );
  await fillFullExample(tester);
  expectReviewEnabled(tester);
  await captureScrollSlots(
    tester,
    stem: 'review',
    label: label,
    topMarker: find.text('مراجعة الأرصدة الافتتاحية'),
    lowerMarker: find.byKey(const Key('confirm-opening')),
    middleWhenTall: true,
  );

  if (includeBigint) {
    await pumpLedger(
      tester,
      size: size,
      brightness: brightness,
      shop: account(ShopEntitlement.active),
      gateway: CaptureGateway(emptyLedger()),
      screenKey: 'bigint-$label',
    );
    await show(tester, const Key('cash-cash'));
    await tester.enterText(
      find.byKey(const Key('cash-cash')),
      '92233720368547758.07',
    );
    await tester.pump();
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pump();
    expectReviewEnabled(tester);
    expect(find.text('92233720368547758.07'), findsOneWidget);
    expect(find.text('92233720368547758.07 جنيه'), findsWidgets);
    await jump(tester, 0);
    expectOnScreen(tester, find.text('مراجعة الأرصدة الافتتاحية'));
    await capture(tester, 'review-bigint-top-$label.png');
  }

  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.active),
    gateway: CaptureGateway(confirmedLedger()),
    screenKey: 'confirmed-$label',
  );
  expectConfirmedFeed(tester);
  expect(find.text('نقدي'), findsOneWidget);
  expect(find.text('سبائك · عيار 24 · 1 قطعة'), findsOneWidget);
  expect(find.text('كسر · عيار 24'), findsOneWidget);
  await captureScrollSlots(
    tester,
    stem: 'confirmed',
    label: label,
    topMarker: find.byKey(const Key('ledger-confirmed-status')),
    lowerMarker: find.text('$ownerName · $cairoStamp'),
    middleWhenTall: true,
  );
  await show(tester, const Key('ledger-karat-18'));
  await capture(tester, 'confirmed-movement-$label.png');

  await blank(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final theme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: withTahoma(theme),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: RepaintBoundary(
        key: const Key('opening-capture-boundary'),
        child: ShopAccountsGate(
          key: ValueKey('pending-$label'),
          gateway: CaptureShops([account(ShopEntitlement.pending)]),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
        ),
      ),
    ),
  );
  final shopTile = find.byKey(Key('shop-$shopId'));
  for (
    var attempt = 0;
    attempt < 12 && shopTile.evaluate().isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(shopTile, findsOneWidget);
  expect(find.text('قيد التفعيل'), findsOneWidget);
  expect(Theme.of(tester.element(shopTile)).brightness, brightness);
  expect(Directionality.of(tester.element(shopTile)), TextDirection.rtl);
  await tester.tap(shopTile);
  await tester.pump();
  expectNoException(tester);
  expect(find.text('قيد التفعيل'), findsOneWidget);
  expect(
    find.text(
      'لم يُفعّل اشتراك هذا المتجر بعد. ستتاح بيانات المتجر بعد التفعيل.',
    ),
    findsOneWidget,
  );
  expect(find.byKey(const Key('ledger-title')), findsNothing);
  expect(find.byKey(const Key('confirm-opening')), findsNothing);
  expectOnScreen(
    tester,
    find.text(
      'لم يُفعّل اشتراك هذا المتجر بعد. ستتاح بيانات المتجر بعد التفعيل.',
    ),
  );
  await capture(tester, 'pending-activation-$label.png');
  await blank(tester);

  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.expired),
    gateway: CaptureGateway(emptyLedger(entitlement: 'expired')),
    screenKey: 'expired-empty-$label',
  );
  expectExpiredNoWrite(tester);
  expect(find.text('لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.'), findsOneWidget);
  expect(find.byKey(const Key('ledger-confirmed-status')), findsNothing);
  expectOnScreen(tester, find.text('لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.'));
  await capture(tester, 'expired-empty-$label.png');

  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.expired),
    gateway: CaptureGateway(confirmedLedger(entitlement: 'expired')),
    screenKey: 'expired-confirmed-$label',
  );
  expectExpiredNoWrite(tester);
  expectConfirmedFeed(tester);
  await captureScrollSlots(
    tester,
    stem: 'expired-confirmed',
    label: label,
    topMarker: find.text('منتهي - للقراءة فقط'),
    lowerMarker: find.text('$ownerName · $cairoStamp'),
    middleWhenTall: true,
  );

  final hanging = CaptureGateway(emptyLedger())
    ..confirmGate = Completer<ConfirmResult>();
  await pumpLedger(
    tester,
    size: size,
    brightness: brightness,
    shop: account(ShopEntitlement.active),
    gateway: hanging,
    screenKey: 'inflight-$label',
  );
  await show(tester, const Key('review-zero'));
  await tester.tap(find.byKey(const Key('review-zero')));
  await tester.pump();
  expectReviewEnabled(tester);
  await show(tester, const Key('confirm-opening'));
  await tester.tap(find.byKey(const Key('confirm-opening')));
  await tester.pump();
  expectPendingDisabled(tester);
  expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
  await jump(tester, 0);
  expectOnScreen(tester, find.byKey(const Key('opening-pending')));
  await capture(tester, 'inflight-pending-$label.png');
  if (!hanging.confirmGate!.isCompleted) {
    hanging.confirmGate!.complete(const ConfirmUnknown());
  }
  await frames(tester, count: 4);
  await blank(tester);
}

final captureFontsAvailable =
    File(r'C:\Windows\Fonts\tahoma.ttf').existsSync() &&
    File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).existsSync();
final managedCapture = RegExp(
  r'^(uninitialized-(top|lower)|review-(top|lower)|confirmed-(top|lower|movement)|pending-activation|expired-empty|expired-confirmed-(top|lower)|inflight-pending|review-bigint-top)-(light|dark)-(320|1440)\.png$',
);

void main() {
  setUpAll(() async {
    if (!captureFontsAvailable) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = File(r'C:\Windows\Fonts\tahoma.ttf');
    expect(await font.exists(), isTrue, reason: 'Tahoma is required');
    final bytes = await font.readAsBytes();
    final loader = FontLoader('Tahoma')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    final icons = File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );
    expect(await icons.exists(), isTrue, reason: 'MaterialIcons is required');
    final iconBytes = await icons.readAsBytes();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
    await iconLoader.load();
    tahomaReady = true;

    final dir = Directory(captureDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File &&
            managedCapture.hasMatch(entity.uri.pathSegments.last)) {
          await entity.delete();
        }
      }
    }
  });

  for (final size in const [Size(320, 640), Size(1440, 900)]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = '${brightness.name}-${size.width.toInt()}';
      testWidgets(
        'opening captures $label',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() async => blank(tester));
          await captureMatrix(
            tester,
            size: size,
            brightness: brightness,
            includeBigint: size.width == 320,
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: !captureFontsAvailable,
      );
      testWidgets('ledger guide capture $label', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async => blank(tester));
        await pumpLedger(
          tester,
          size: size,
          brightness: brightness,
          shop: account(ShopEntitlement.active),
          gateway: CaptureGateway(emptyLedger()),
          screenKey: 'guide-$label',
          onboardingStore: CaptureGuideStore(),
        );
        expect(find.byKey(const Key('onboarding-guide')), findsOneWidget);
        await captureGuide(tester, 'ledger-$label.png');
      }, skip: !captureFontsAvailable);
    }
  }

  test('manifest covers the 32 primary captures', () async {
    final dir = Directory(captureDir);
    expect(await dir.exists(), isTrue);
    final names = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          managedCapture.hasMatch(entity.uri.pathSegments.last)) {
        final length = await entity.length();
        expect(length, greaterThan(8));
        names.add(entity.uri.pathSegments.last);
      }
    }
    names.sort();
    for (final brightness in ['light', 'dark']) {
      for (final width in [320, 1440]) {
        for (final stem in primaryStems) {
          expect(
            names,
            contains('$stem-$brightness-$width.png'),
            reason: 'missing $stem-$brightness-$width.png',
          );
        }
        expect(names, contains('expired-empty-$brightness-$width.png'));
        expect(names, contains('expired-confirmed-top-$brightness-$width.png'));
        expect(
          names,
          contains('expired-confirmed-lower-$brightness-$width.png'),
        );
        expect(names, contains('inflight-pending-$brightness-$width.png'));
      }
      expect(names, contains('review-bigint-top-$brightness-320.png'));
    }
    expect(names.where((name) => primaryStems.any(name.startsWith)).length, 32);
    expect(names.length, 50);
    // ignore: avoid_print
    print('CAPTURE_COUNT ${names.length}');
    for (final name in names) {
      // ignore: avoid_print
      print('CAPTURE $name');
    }
  }, skip: !captureFontsAvailable);
}

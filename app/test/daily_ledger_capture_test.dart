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

ShopAccount account(ShopEntitlement entitlement) => ShopAccount(
  id: shopId,
  name: 'ذهب الجيزة',
  role: 'owner',
  entitlement: entitlement,
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

  @override
  Future<List<SubscriptionNotice>> listMySubscriptionNotices() async =>
      const [];

  @override
  Future<void> dismissSubscriptionNotice({
    required String shopId,
    required SubscriptionNoticeKind kind,
    required DateTime expiresAt,
  }) async {}

  @override
  Future<SubscriptionActivationResult> activateSubscription({
    required String requestKey,
    required String code,
    required String shopId,
  }) async {
    throw const SubscriptionActivationException(
      SubscriptionActivationFailure.unavailable,
    );
  }
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

void expectThemeAndRtl(WidgetTester tester, Brightness brightness) {
  final title = find.byKey(const Key('ledger-title'));
  expect(title, findsOneWidget);
  final context = tester.element(title);
  expect(Theme.of(context).brightness, brightness);
  expect(Directionality.of(context), TextDirection.rtl);
  expect(find.text('الدفتر اليومي'), findsOneWidget);
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
          onChangeShop: () {},
        ),
      ),
    ),
  );
  await frames(tester);
  expect(find.byKey(const Key('ledger-loading')), findsNothing);
  expectThemeAndRtl(tester, brightness);
}

final captureFontsAvailable =
    File(r'C:\Windows\Fonts\tahoma.ttf').existsSync() &&
    File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).existsSync();
final managedCapture = RegExp(
  r'^(uninitialized-(top|lower)|review-(top|lower)|confirmed-(top|lower|cash)|pending-activation|expired-empty|expired-confirmed-(top|lower)|inflight-pending|review-bigint-top)-(light|dark)-(320|1440)\.png$',
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
      testWidgets('ledger without guidance capture $label', (tester) async {
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
          gateway: CaptureGateway(confirmedLedger()),
          screenKey: 'guide-$label',
          onboardingStore: CaptureGuideStore(),
        );
        expect(find.byKey(const Key('onboarding-guide')), findsNothing);
        await captureGuide(tester, 'ledger-$label.png');
      }, skip: !captureFontsAvailable);
    }
  }
}

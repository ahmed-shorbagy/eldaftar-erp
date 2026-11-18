import 'dart:async';

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shopId = '11111111-1111-4111-8111-111111111111';
const user = 'user-1';

ShopAccount shop(ShopEntitlement entitlement) => ShopAccount(
  id: shopId,
  name: 'متجر تجريبي',
  role: 'owner',
  entitlement: entitlement,
);

DailyLedgerView uninitializedLedger() => const DailyLedgerView(
  state: 'uninitialized',
  entitlementStatus: 'active',
  canConfirm: true,
  businessDay: null,
  cash: [],
  stock: [],
  scrap: [],
  feed: [],
);

DailyLedgerView confirmedLedger() => const DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: LedgerBusinessDay(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    businessDate: '2026-09-26',
    openedAt: '2026-09-26T00:30:00+00:00',
  ),
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
      piastres: '0',
      pounds: '0.00',
    ),
    LedgerCashLine(
      method: 'wallet',
      labelAr: 'محفظة',
      piastres: '0',
      pounds: '0.00',
    ),
    LedgerCashLine(
      method: 'card',
      labelAr: 'فيزا',
      piastres: '0',
      pounds: '0.00',
    ),
  ],
  stock: [],
  scrap: [],
  feed: [
    LedgerFeedLine(
      kind: 'opening_balances_confirmed',
      labelAr: 'رصيد افتتاحي',
      operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      actorDisplayName: 'منى حسن',
      occurredAt: '2026-09-26T00:30:00+00:00',
      occurredAtCairo: '2026-09-26T03:30:00',
    ),
  ],
);

class MemoryStore implements PendingOpeningStore {
  PendingOpening? saved;

  @override
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  }) async => saved;

  @override
  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {
    saved = pending;
  }

  @override
  Future<void> retire({required String userId, required String shopId}) async {
    saved = null;
  }
}

class GuideMemoryStore implements OnboardingStore {
  final steps = <String, int>{};
  final complete = <String>{};

  @override
  Future<bool> isComplete(String path) async => complete.contains(path);

  @override
  Future<int> readStep(String path) async => steps[path] ?? 0;

  @override
  Future<void> saveStep(String path, int step) async {
    steps[path] = step;
  }

  @override
  Future<void> markComplete(String path) async {
    complete.add(path);
  }
}

class ScriptGateway implements OpeningGateway {
  int confirmCalls = 0;
  int statusCalls = 0;
  int ledgerCalls = 0;
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];
  DailyLedgerView ledgerView = uninitializedLedger();
  ConfirmResult confirmResult = const ConfirmUnknown();
  FutureOr<ConfirmResult> Function()? confirmHook;
  Future<StatusResult> Function()? statusHook;
  StatusResult statusResult = const StatusUnknown();

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    confirmCalls++;
    keys.add(idempotencyKey);
    payloads.add(payload);
    final hook = confirmHook;
    if (hook != null) return await hook();
    return confirmResult;
  }

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    statusCalls++;
    final hook = statusHook;
    if (hook != null) return hook();
    return statusResult;
  }

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    ledgerCalls++;
    return ledgerView;
  }
}

class ItemCacheGateway implements OpeningGateway, FinancialGateway {
  ItemCacheGateway(this.ledgerView);
  final DailyLedgerView ledgerView;
  int operationCalls = 0;
  final operationIds = <String>[];

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const ConfirmUnknown();

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      ledgerView;

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(state: 'closed');

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const FinancialUnknown();

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async {
    operationCalls++;
    operationIds.add(operationId);
    return {
      'payload': {
        'items': [
          {
            'item_name': 'خواتم',
            'milligrams': '1000',
            'karat': 21,
            'category': 'worked_jewelry',
            'line_price_piastres': '1000',
          },
        ],
      },
    };
  }
}

class ListingShops implements ShopAccountGateway {
  ListingShops(this.accounts);
  List<ShopAccount> accounts;

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

class SignedInAuth implements AuthGateway {
  AuthStatus current = AuthStatus.signedIn;
  final controller = StreamController<AuthStatus>.broadcast();

  @override
  AuthStatus get status => current;
  @override
  Stream<AuthStatus> get changes => controller.stream;
  @override
  Future<void> signIn(SignInRequest request) async {}
  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<Governorate>> loadGovernorates() async => const [];
  @override
  Future<void> signOut() async {}

  void expire() {
    current = AuthStatus.signedOut;
    controller.add(current);
  }
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required ShopAccount account,
  required ScriptGateway gateway,
  required MemoryStore store,
  int generation = 0,
  OnboardingStore? onboardingStore,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: DailyLedgerScreen(
        shop: account,
        gateway: gateway,
        store: store,
        userId: user,
        refreshGeneration: generation,
        onboardingStore: onboardingStore,
        newKey: () => '99999999-9999-4999-8999-999999999999',
      ),
    ),
  );
}

Future<void> show(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  final controller = tester
      .widget<ListView>(find.byKey(const Key('ledger-scroll')))
      .controller!;
  controller.jumpTo(0);
  await tester.pump();
  if (target.evaluate().isEmpty) {
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
  }
  for (var attempt = 0; attempt < 20; attempt++) {
    if (target.evaluate().isEmpty) break;
    final dy = tester.getTopLeft(target).dy;
    if (dy >= 8 && dy < 520) return;
    final next = (controller.offset + (dy >= 520 ? 220 : -220)).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if (next == controller.offset) return;
    controller.jumpTo(next);
    await tester.pump();
  }
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
        'home metrics and cash disclosure fit at $width in $brightness RTL',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final base = confirmedLedger();
          final view = DailyLedgerView(
            state: base.state,
            entitlementStatus: base.entitlementStatus,
            canConfirm: base.canConfirm,
            businessDay: base.businessDay,
            cash: base.cash,
            stock: base.stock,
            scrap: base.scrap,
            feed: base.feed,
            daySummary: const LedgerDaySummary(
              salePiastres: '5000',
              purchasePiastres: '2000',
              expensePiastres: '500',
              saleCount: 1,
              purchaseCount: 1,
              expenseCount: 1,
              goldByBucket: [
                LedgerGoldMovement(
                  kind: 'sale',
                  category: 'worked_jewelry',
                  karat: 18,
                  milligrams: '2000',
                  count: '2',
                ),
                LedgerGoldMovement(
                  kind: 'purchase',
                  category: 'scrap',
                  karat: 21,
                  milligrams: '1250',
                  count: '0',
                ),
              ],
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: ConfirmedLedgerDashboard(
                      ledger: view,
                      shopId: shopId,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(find.text('حركة الذهب'), findsNothing);
          expect(find.byKey(const Key('ledger-more-metrics')), findsNothing);
          expect(find.byKey(const Key('ledger-metric-strip')), findsOneWidget);
          expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
          expect(
            find.byKey(const Key('ledger-metric-expense')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('ledger-cash-methods')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('ledger-cash-empty')), findsNothing);
          await tester.tap(find.byKey(const Key('detail-close')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'narrow ledger hides page-top reload and groups account actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScreen(
        tester,
        account: shop(ShopEntitlement.active),
        gateway: ScriptGateway()..ledgerView = confirmedLedger(),
        store: MemoryStore(),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('تحديث الدفتر'), findsNothing);
      expect(find.byKey(const Key('theme-toggle')), findsNothing);
      expect(find.byTooltip('المزيد'), findsNothing);
      expect(find.byTooltip('تسجيل الخروج'), findsNothing);
      expect(find.text('تسجيل الخروج'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ledger has no guidance and refresh reads the real ledger', (
    tester,
  ) async {
    final gateway = ScriptGateway()..ledgerView = confirmedLedger();
    final guide = GuideMemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
      onboardingStore: guide,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    expect(find.byKey(const Key('ledger-help')), findsNothing);
    final reads = gateway.ledgerCalls;
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
      onboardingStore: guide,
      generation: 1,
    );
    await tester.pumpAndSettle();
    expect(gateway.ledgerCalls, greaterThan(reads));
    expect(guide.steps, isEmpty);
    expect(guide.complete, isEmpty);
    expect(gateway.confirmCalls, 0);
  });

  test('confirmed cash total uses exact piastres above double precision', () {
    const view = DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: 'active',
      canConfirm: false,
      businessDay: null,
      cash: [
        LedgerCashLine(
          method: 'cash',
          labelAr: 'نقدي',
          piastres: '9007199254740993',
          pounds: '90071992547409.93',
        ),
        LedgerCashLine(
          method: 'card',
          labelAr: 'فيزا',
          piastres: '7',
          pounds: '0.07',
        ),
      ],
      stock: [],
      scrap: [],
      feed: [],
    );
    expect(view.totalCashPounds, '90071992547410.00');
  });
  // Owner feedback of 2026-11-17 (ADR 0049): there is no opening-balances
  // form. A new shop's ledger opens directly.
  testWidgets('a new shop opens straight on the ledger with no form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final gateway = ScriptGateway();
    gateway.confirmHook = () {
      gateway.ledgerView = confirmedLedger();
      return const ConfirmCommitted(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      );
    };
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
    expect(find.text('10,000'), findsWidgets);
    expect(gateway.confirmCalls, 1);
    expect(gateway.payloads.single['stock'], isEmpty);
    expect(gateway.payloads.single['scrap'], isEmpty);
    expect(store.saved, isNull);
    // Nothing of the old setup screen is left.
    expect(find.textContaining('الأرصدة الافتتاحية'), findsNothing);
    expect(find.byKey(const Key('cash-cash')), findsNothing);
    expect(find.byKey(const Key('review-zero')), findsNothing);
    expect(find.byKey(const Key('review-values')), findsNothing);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.byKey(const Key('add-stock')), findsNothing);
    expect(find.textContaining('مشغولات'), findsNothing);
    expect(find.textContaining('منازل'), findsNothing);
  });

  testWidgets('staff of an unopened shop wait and see no form', (tester) async {
    final gateway = ScriptGateway();
    await pumpScreen(
      tester,
      account: const ShopAccount(
        id: shopId,
        name: 'متجر تجريبي',
        role: 'employee',
        entitlement: ShopEntitlement.active,
      ),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ledger-opening-owner-only')), findsOneWidget);
    expect(find.text('لم يفتح صاحب المحل الدفتر بعد.'), findsOneWidget);
    expect(gateway.confirmCalls, 0);
    expect(find.byKey(const Key('ledger-open-retry')), findsNothing);
    expect(find.byKey(const Key('cash-cash')), findsNothing);
  });

  testWidgets('a failed opening offers the owner a retry that opens the '
      'ledger', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmRejected('overflow');
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-open-failed')), findsOneWidget);
    expect(find.byKey(const Key('cash-cash')), findsNothing);
    final first = gateway.confirmCalls;

    gateway.confirmHook = () {
      gateway.ledgerView = confirmedLedger();
      return const ConfirmCommitted(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      );
    };
    await tester.tap(find.byKey(const Key('ledger-open-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
    expect(gateway.confirmCalls, first + 1);
    expect(gateway.keys.toSet(), hasLength(1), reason: 'the same key');
  });

  testWidgets(
    'a lost success stays pending until status and does not post twice',
    (tester) async {
      final gateway = ScriptGateway();
      final status = Completer<StatusResult>();
      gateway.confirmHook = () async => const ConfirmUnknown();
      gateway.statusHook = () => status.future;
      await pumpScreen(
        tester,
        account: shop(ShopEntitlement.active),
        gateway: gateway,
        store: MemoryStore(),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ledger-loading')), findsOneWidget);
      expect(find.byKey(const Key('cash-cash')), findsNothing);
      expect(gateway.confirmCalls, 1);
      gateway.ledgerView = confirmedLedger();
      status.complete(
        const StatusCompleted('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
      expect(gateway.confirmCalls, 1);
    },
  );

  testWidgets('an absent status retries the retained key and payload', (
    tester,
  ) async {
    final draft = (OpeningDraft.compose() as Accepted<OpeningDraft>).value;
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '99999999-9999-4999-8999-999999999999',
        payload: draft.toCanonicalJson(),
      );
    final gateway = ScriptGateway()..statusResult = const StatusAbsent();
    gateway.confirmHook = () {
      gateway.ledgerView = confirmedLedger();
      return const ConfirmCommitted(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: true,
      );
    };
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(gateway.confirmCalls, 1);
    expect(gateway.keys.single, '99999999-9999-4999-8999-999999999999');
    expect(gateway.payloads.single, draft.toCanonicalJson());
    expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
  });

  testWidgets('a pending shop makes no ledger read and no confirm', (
    tester,
  ) async {
    final gateway = ScriptGateway();
    final shops = ListingShops([shop(ShopEntitlement.pending)]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ShopAccountsGate(
          gateway: shops,
          openingGateway: gateway,
          pendingOpeningStore: MemoryStore(),
          currentUserId: () => user,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('قيد التفعيل'), findsOneWidget);
    expect(gateway.ledgerCalls, 0);
    expect(gateway.confirmCalls, 0);
    expect(gateway.statusCalls, 0);
  });

  testWidgets('an expired shop can read and has no confirm controls', (
    tester,
  ) async {
    final gateway = ScriptGateway()
      ..ledgerView = uninitializedLedger().copyExpired();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.expired),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    expect(gateway.ledgerCalls, 1);
    expect(find.text('الاشتراك منتهٍ. العرض للقراءة فقط.'), findsOneWidget);
    expect(find.text('منتهي - للقراءة فقط'), findsOneWidget);
    expect(find.byKey(const Key('ledger-not-opened')), findsOneWidget);
    expect(gateway.confirmCalls, 0);
    expect(find.byKey(const Key('ledger-open-retry')), findsNothing);
  });

  testWidgets('staff see the ledger once the owner has opened it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const employee = ShopAccount(
      id: shopId,
      name: 'متجر تجريبي',
      role: 'employee',
      entitlement: ShopEntitlement.active,
    );
    final gateway = ScriptGateway();
    final store = MemoryStore();
    await pumpScreen(tester, account: employee, gateway: gateway, store: store);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-opening-owner-only')), findsOneWidget);

    // The owner opens the ledger on another device.
    gateway.ledgerView = confirmedLedger();
    await pumpScreen(
      tester,
      account: employee,
      gateway: gateway,
      store: store,
      generation: 1,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ledger-opening-owner-only')), findsNothing);
    expect(find.byKey(const Key('ledger-confirmed-status')), findsOneWidget);
    expect(gateway.confirmCalls, 0);
  });

  testWidgets('a failed read after the confirm offers a retry that opens the '
      'ledger', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // The server acknowledged the opening; the read that followed is stale.
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '99999999-9999-4999-8999-999999999999',
        payload: const {},
        disposition: PendingDisposition.acknowledged,
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
    final gateway = ScriptGateway();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحديث الدفتر. أعد المحاولة.'), findsOneWidget);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    final retry = find.byKey(const Key('opening-refresh-retry'));
    expect(retry, findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    gateway.ledgerView = confirmedLedger();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحديث الدفتر. أعد المحاولة.'), findsNothing);
    expect(find.text('10,000'), findsWidgets);
    expect(gateway.confirmCalls, 0);
    expect(store.saved, isNull);
  });

  testWidgets(
    'an active session catches a remote balance change within a minute',
    (tester) async {
      final gateway = ScriptGateway()..ledgerView = confirmedLedger();
      await pumpScreen(
        tester,
        account: shop(ShopEntitlement.active),
        gateway: gateway,
        store: MemoryStore(),
      );
      await tester.pumpAndSettle();
      final firstCalls = gateway.ledgerCalls;
      final original = confirmedLedger();
      gateway.ledgerView = DailyLedgerView(
        state: original.state,
        entitlementStatus: original.entitlementStatus,
        canConfirm: original.canConfirm,
        businessDay: original.businessDay,
        cash: [
          const LedgerCashLine(
            method: 'cash',
            labelAr: 'نقدي',
            piastres: '2000000',
            pounds: '20000.00',
          ),
          ...original.cash.skip(1),
        ],
        stock: original.stock,
        scrap: original.scrap,
        feed: original.feed,
      );
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(gateway.ledgerCalls, greaterThan(firstCalls));
      expect(find.text('20,000'), findsWidgets);
    },
  );

  testWidgets('sign-out and revocation remove the figures', (tester) async {
    final gateway = ScriptGateway()..ledgerView = confirmedLedger();
    final shops = ListingShops([shop(ShopEntitlement.active)]);
    final auth = SignedInAuth();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AuthGate(
          supabaseStatus: SupabaseStartupStatus.ready,
          authGateway: auth,
          shopAccountGateway: shops,
          openingGateway: gateway,
          pendingOpeningStore: MemoryStore(),
          currentUserId: () => user,
          onToggleTheme: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10,000'), findsWidgets);
    auth.expire();
    await tester.pumpAndSettle();
    expect(find.text('10,000'), findsNothing);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    await auth.controller.close();

    final gateGateway = ScriptGateway()..ledgerView = confirmedLedger();
    final gateShops = ListingShops([shop(ShopEntitlement.active)]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ShopAccountsGate(
          gateway: gateShops,
          openingGateway: gateGateway,
          pendingOpeningStore: MemoryStore(),
          currentUserId: () => user,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10,000'), findsWidgets);
    gateShops.accounts = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('10,000'), findsNothing);
    expect(find.textContaining('لم يعد لديك وصول'), findsOneWidget);
  });

  testWidgets('sign-out during confirm does not surface a stale error', (
    tester,
  ) async {
    final release = Completer<ConfirmResult>();
    final gateway = ScriptGateway();
    gateway.confirmHook = () => release.future;
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pump();
    await tester.pump();
    expect(gateway.confirmCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    release.complete(
      const ConfirmCommitted(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(store.saved, isNotNull);
  });

  testWidgets('switching the signed-in user drops the previous shop figures', (
    tester,
  ) async {
    final firstShops = ListingShops([
      ShopAccount(
        id: shopId,
        name: 'متجر الأول',
        role: 'owner',
        entitlement: ShopEntitlement.active,
      ),
    ]);
    final secondShops = ListingShops([
      ShopAccount(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'متجر الثاني',
        role: 'owner',
        entitlement: ShopEntitlement.active,
      ),
    ]);
    var userId = user;
    final auth = SignedInAuth();
    Future<void> pump() {
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AuthGate(
            supabaseStatus: SupabaseStartupStatus.ready,
            authGateway: auth,
            shopAccountGateway: userId == user ? firstShops : secondShops,
            openingGateway: ScriptGateway()..ledgerView = confirmedLedger(),
            pendingOpeningStore: MemoryStore(),
            currentUserId: () => userId,
            onToggleTheme: (_) async {},
          ),
        ),
      );
    }

    await pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('أهلاً متجر الأول'), findsOneWidget);
    expect(find.text('10,000'), findsWidgets);
    userId = 'user-2';
    await pump();
    await tester.pump();
    expect(find.textContaining('أهلاً متجر الأول'), findsNothing);
    expect(find.text('10,000'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('أهلاً متجر الثاني'), findsOneWidget);
    await auth.controller.close();
  });

  testWidgets('a server expiry on a confirmed ledger is read only', (
    tester,
  ) async {
    final gateway = ScriptGateway()
      ..ledgerView = confirmedLedger().copyExpired();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    expect(find.text('الاشتراك منتهٍ. العرض للقراءة فقط.'), findsOneWidget);
    expect(find.text('10,000'), findsWidgets);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.byKey(const Key('review-zero')), findsNothing);
  });

  testWidgets('revocation during unknown recovery shows access lost', (
    tester,
  ) async {
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmUnknown()
      ..statusResult = const StatusRejected('forbidden');
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.text('غير مسموح'), findsOneWidget);
    expect(find.byKey(const Key('ledger-open-retry')), findsNothing);
    expect(gateway.confirmCalls, 1);
    expect(store.saved?.disposition, PendingDisposition.unresolved);
  });

  testWidgets('an expired shop does not reopen an editable rejected draft', (
    tester,
  ) async {
    final draft =
        (OpeningDraft.compose(
                  cash: {
                    CashMethod.cash:
                        (Piastres.parsePounds('12.50') as Accepted<Piastres>)
                            .value,
                  },
                )
                as Accepted<OpeningDraft>)
            .value;
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '44444444-4444-4444-8444-444444444444',
        payload: draft.toCanonicalJson(),
        disposition: PendingDisposition.validationRejected,
        rejectionCode: 'invalid_input',
      );
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.expired),
      gateway: ScriptGateway()
        ..ledgerView = uninitializedLedger().copyExpired(),
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-cash')), findsNothing);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.text('12.50'), findsNothing);
    expect(find.text('الاشتراك منتهٍ. العرض للقراءة فقط.'), findsOneWidget);
    expect(store.saved?.idempotencyKey, '44444444-4444-4444-8444-444444444444');
  });

  testWidgets(
    'operation items are read once per id across rebuilds and again after refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      const operationId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final base = confirmedLedger();
      final store = MemoryStore();
      final gateway = ItemCacheGateway(
        DailyLedgerView(
          state: base.state,
          entitlementStatus: base.entitlementStatus,
          canConfirm: false,
          businessDay: base.businessDay,
          cash: base.cash,
          stock: base.stock,
          scrap: base.scrap,
          feed: [
            LedgerFeedLine(
              kind: 'sale',
              labelAr: 'بيع',
              operationId: operationId,
              actorDisplayName: 'منى حسن',
              occurredAt: '2026-09-26T01:00:00+00:00',
              occurredAtCairo: '2026-09-26T04:00:00',
            ),
          ],
        ),
      );
      Future<void> pump({int generation = 0}) {
        return tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            home: DailyLedgerScreen(
              shop: shop(ShopEntitlement.active),
              gateway: gateway,
              store: store,
              userId: user,
              refreshGeneration: generation,
              newKey: () => '99999999-9999-4999-8999-999999999999',
            ),
          ),
        );
      }

      await pump();
      await tester.pumpAndSettle();
      expect(find.text('خواتم'), findsOneWidget);
      expect(gateway.operationCalls, 1);
      await pump();
      await tester.pumpAndSettle();
      expect(gateway.operationCalls, 1);
      await pump(generation: 1);
      await tester.pumpAndSettle();
      expect(gateway.operationCalls, 2);
      expect(gateway.operationIds, [operationId, operationId]);
    },
  );
}

extension on DailyLedgerView {
  DailyLedgerView copyExpired() => DailyLedgerView(
    state: state,
    entitlementStatus: 'expired',
    canConfirm: false,
    businessDay: businessDay,
    cash: cash,
    stock: stock,
    scrap: scrap,
    feed: feed,
  );
}

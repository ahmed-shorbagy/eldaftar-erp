import 'dart:async';

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

class ListingShops implements ShopAccountGateway {
  ListingShops(this.accounts);
  List<ShopAccount> accounts;

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => accounts;
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
        onSignOut: () async {},
        onToggleTheme: (_) async {},
        onChangeShop: () {},
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
  testWidgets('ledger guide resumes after skip and uses real refresh', (
    tester,
  ) async {
    final gateway = ScriptGateway();
    final guide = GuideMemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
      onboardingStore: guide,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-guide')), findsOneWidget);
    final reads = gateway.ledgerCalls;
    await tester.tap(find.byTooltip('تحديث الدفتر'));
    await tester.pumpAndSettle();
    expect(gateway.ledgerCalls, greaterThan(reads));
    expect(guide.steps.values, contains(1));
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pump();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    await tester.tap(find.byKey(const Key('ledger-help')));
    await tester.pump();
    expect(find.text('راجع الأرصدة قبل أي تأكيد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    expect(guide.complete, contains('ledger_${user}_$shopId'));
    expect(gateway.confirmCalls, 0, reason: 'Guidance never posts balances');
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
  testWidgets('review then pending then the confirmed ledger', (tester) async {
    final gateway = ScriptGateway();
    final store = MemoryStore();
    final status = Completer<StatusResult>();
    gateway.confirmHook = () async => const ConfirmUnknown();
    gateway.statusHook = () => status.future;
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.text('لم يتم تأكيد الأرصدة الافتتاحية'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cash-cash')), '10000');
    await show(tester, const Key('stock-grams-0'));
    await tester.enterText(find.byKey(const Key('stock-grams-0')), '5');
    await show(tester, const Key('stock-count-0'));
    await tester.enterText(find.byKey(const Key('stock-count-0')), '3');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.text('إجمالي النقد'), findsOneWidget);
    expect(find.text('صافي النقد'), findsNothing);
    expect(find.text('10000.00'), findsOneWidget);
    expect(find.textContaining('5.000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pump();
    expect(find.text('بانتظار تأكيد الخادم'), findsOneWidget);
    expect(gateway.confirmCalls, 1);
    gateway.ledgerView = confirmedLedger();
    status.complete(
      const StatusCompleted('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
    );
    await tester.pumpAndSettle();
    expect(find.text('تم تأكيد الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.text('إجمالي النقدية'), findsOneWidget);
    expect(find.text('10000.00 جنيه'), findsOneWidget);
    expect(find.text('رصيد افتتاحي'), findsOneWidget);
    expect(find.text('منى حسن · 26 سبتمبر 2026، 03:30:00'), findsOneWidget);
    expect(find.textContaining('T'), findsNothing);
    expect(gateway.confirmCalls, 1);
  });

  testWidgets('a rapid double tap sends one confirm', (tester) async {
    final gateway = ScriptGateway();
    final release = Completer<ConfirmResult>();
    gateway.confirmHook = () => release.future;
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    await show(tester, const Key('review-zero'));
    await tester.tap(find.byKey(const Key('review-zero')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pump();
    expect(gateway.confirmCalls, 1);
    gateway.ledgerView = confirmedLedger();
    release.complete(
      const ConfirmCommitted(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.confirmCalls, 1);
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
      await tester.pumpAndSettle();
      await show(tester, const Key('review-zero'));
      await tester.tap(find.byKey(const Key('review-zero')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-opening')));
      await tester.pump();
      expect(find.text('بانتظار تأكيد الخادم'), findsOneWidget);
      expect(gateway.confirmCalls, 1);
      gateway.ledgerView = confirmedLedger();
      status.complete(
        const StatusCompleted('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
      );
      await tester.pumpAndSettle();
      expect(find.text('تم تأكيد الأرصدة الافتتاحية'), findsOneWidget);
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
    expect(find.text('تم تأكيد الأرصدة الافتتاحية'), findsOneWidget);
  });

  testWidgets('a validation error keeps the draft and the same key', (
    tester,
  ) async {
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmRejected('invalid_input');
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-cash')), '12.50');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pumpAndSettle();
    expect(find.text('البيانات المدخلة غير صالحة'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cash-cash')))
          .controller
          ?.text,
      '12.50',
    );
    await tester.enterText(find.byKey(const Key('cash-cash')), '13.50');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pumpAndSettle();
    expect(gateway.keys, [
      '99999999-9999-4999-8999-999999999999',
      '99999999-9999-4999-8999-999999999999',
    ]);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cash-cash')))
          .controller
          ?.text,
      '13.50',
    );
  });

  testWidgets('a half-filled row is rejected before review', (tester) async {
    final gateway = ScriptGateway();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    await show(tester, const Key('stock-grams-0'));
    await tester.enterText(find.byKey(const Key('stock-grams-0')), '1');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    expect(find.text('أكمل الصف أو اتركه فارغًا'), findsOneWidget);
    expect(find.text('مراجعة الأرصدة الافتتاحية'), findsNothing);
    expect(gateway.confirmCalls, 0);
  });

  testWidgets('zero balances open review and do not post by themselves', (
    tester,
  ) async {
    final gateway = ScriptGateway();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    await show(tester, const Key('review-zero'));
    await tester.tap(find.byKey(const Key('review-zero')));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.text('0.00'), findsWidgets);
    expect(gateway.confirmCalls, 0);
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
    await tester.tap(find.byKey(const Key('shop-$shopId')));
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
    expect(find.text('لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.'), findsOneWidget);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.byKey(const Key('review-zero')), findsNothing);
  });

  testWidgets('another session confirmation appears after refresh', (
    tester,
  ) async {
    final gateway = ScriptGateway();
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-cash')), '10');
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
      generation: 1,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cash-cash')))
          .controller
          ?.text,
      '10',
    );
    gateway.ledgerView = confirmedLedger();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
      generation: 2,
    );
    await tester.pumpAndSettle();
    expect(find.text('10000.00'), findsOneWidget);
    expect(find.text('رصيد افتتاحي'), findsOneWidget);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
  });

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
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    expect(find.text('10000.00'), findsOneWidget);
    auth.expire();
    await tester.pumpAndSettle();
    expect(find.text('10000.00'), findsNothing);
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
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    expect(find.text('10000.00'), findsOneWidget);
    gateShops.accounts = [];
    await tester.tap(find.byTooltip('تحديث الدفتر'));
    await tester.pumpAndSettle();
    expect(find.text('10000.00'), findsNothing);
    expect(find.textContaining('لم يعد لديك وصول'), findsOneWidget);
  });

  testWidgets('a parent refresh keeps an open review', (tester) async {
    final gateway = ScriptGateway();
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-cash')), '12.50');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
      generation: 1,
    );
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الأرصدة الافتتاحية'), findsOneWidget);
    expect(find.text('12.50'), findsOneWidget);
    expect(gateway.confirmCalls, 0);
  });

  testWidgets('expiry removes confirm and keeps the draft', (tester) async {
    final gateway = ScriptGateway();
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-cash')), '12.50');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.expired),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.text('الاشتراك منتهٍ. العرض للقراءة فقط.'), findsOneWidget);
    expect(gateway.confirmCalls, 0);
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
    await tester.pumpAndSettle();
    await show(tester, const Key('review-zero'));
    await tester.tap(find.byKey(const Key('review-zero')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
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

  testWidgets('a rejected draft is restored with the same key', (tester) async {
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmRejected('invalid_input');
    final store = MemoryStore();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    await show(tester, const Key('stock-grams-0'));
    await tester.enterText(find.byKey(const Key('stock-grams-0')), '1.250');
    await show(tester, const Key('stock-count-0'));
    await tester.enterText(find.byKey(const Key('stock-count-0')), '2');
    await show(tester, const Key('scrap-grams-0'));
    await tester.enterText(find.byKey(const Key('scrap-grams-0')), '0.500');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pumpAndSettle();
    final key = store.saved?.idempotencyKey;
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: store,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('stock-grams-0')))
          .controller
          ?.text,
      '1.250',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('stock-count-0')))
          .controller
          ?.text,
      '2',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('scrap-grams-0')))
          .controller
          ?.text,
      '0.500',
    );
    expect(store.saved?.idempotencyKey, key);
    expect(gateway.confirmCalls, 1);
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
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    expect(find.text('متجر الأول'), findsOneWidget);
    expect(find.text('10000.00'), findsOneWidget);
    userId = 'user-2';
    await pump();
    await tester.pump();
    expect(find.text('متجر الأول'), findsNothing);
    expect(find.text('10000.00'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('متجر الثاني'), findsOneWidget);
    await auth.controller.close();
  });

  testWidgets('a max-width review line wraps at 320 pixels', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = ScriptGateway();
    await pumpScreen(
      tester,
      account: shop(ShopEntitlement.active),
      gateway: gateway,
      store: MemoryStore(),
    );
    await tester.pumpAndSettle();
    await show(tester, const Key('stock-grams-0'));
    await tester.enterText(
      find.byKey(const Key('stock-grams-0')),
      '9223372036854775.807',
    );
    await show(tester, const Key('stock-count-0'));
    await tester.enterText(
      find.byKey(const Key('stock-count-0')),
      '9223372036854775807',
    );
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    expect(find.textContaining('9223372036854775.807'), findsOneWidget);
    expect(find.text('9223372036854775807'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('10000.00'), findsOneWidget);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
    expect(find.byKey(const Key('review-zero')), findsNothing);
  });

  testWidgets('revocation during unknown recovery hides review amounts', (
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
    await tester.enterText(find.byKey(const Key('cash-cash')), '12.50');
    await show(tester, const Key('review-values'));
    await tester.tap(find.byKey(const Key('review-values')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-opening')));
    await tester.pumpAndSettle();
    expect(find.text('غير مسموح'), findsOneWidget);
    expect(find.text('12.50'), findsNothing);
    expect(find.byKey(const Key('confirm-opening')), findsNothing);
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

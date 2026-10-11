import 'dart:async';

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/shell/shell_copy.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const shopId = '11111111-1111-4111-8111-111111111111';
ShopAccount account(ShopEntitlement entitlement) => ShopAccount(
  id: shopId,
  name: 'متجر تجريبي',
  role: 'owner',
  entitlement: entitlement,
);

class FakeShops implements ShopAccountGateway {
  List<ShopAccount> accounts = [];
  bool failList = false;
  Completer<List<ShopAccount>>? listCompletion;

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async {
    if (listCompletion != null) return listCompletion!.future;
    if (failList) {
      throw const ShopAccountException(ShopAccountFailure.unavailable);
    }
    return accounts;
  }

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

class FakeAuth implements AuthGateway {
  AuthStatus current = AuthStatus.signedIn;
  final controller = StreamController<AuthStatus>.broadcast();

  @override
  AuthStatus get status => current;
  @override
  Stream<AuthStatus> get changes => controller.stream;
  @override
  Future<void> signIn(SignInRequest request) async {
    current = AuthStatus.signedIn;
    controller.add(current);
  }

  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<Governorate>> loadGovernorates() async => const [];

  @override
  Future<void> signOut() async {
    current = AuthStatus.signedOut;
    controller.add(current);
  }

  void expire() {
    current = AuthStatus.signedOut;
    controller.add(current);
  }
}

class FakeSync implements ShopSyncGateway {
  final events = StreamController<ShopSyncSnapshot>.broadcast();
  ShopSyncSnapshot? latest = const ShopSyncSnapshot(
    shopId: shopId,
    revision: 1,
  );

  @override
  Stream<ShopSyncSnapshot> watch({
    required String shopId,
    required String userId,
  }) => events.stream;

  @override
  Future<ShopSyncSnapshot?> read({required String shopId}) async => latest;

  @override
  Future<void> close() async {
    if (!events.isClosed) await events.close();
  }
}

Future<void> replayAppLifecycle(WidgetTester tester) async {
  const sequence = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  for (final state in sequence) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

Future<void> pumpGate(
  WidgetTester tester,
  FakeShops shops, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
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
      home: ShopAccountsGate(
        gateway: shops,
        onSignOut: () async {},
        onToggleTheme: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty account list explains there are no memberships', (
    tester,
  ) async {
    final shops = FakeShops();
    await pumpGate(tester, shops);
    expect(find.byKey(const Key('shop-empty')), findsOneWidget);
    expect(find.byKey(const Key('shop-empty-sign-out')), findsOneWidget);
    expect(find.byTooltip('تسجيل الخروج'), findsOneWidget);
    expect(find.text('إنشاء المتجر'), findsNothing);
    expect(find.byKey(const Key('shop-name')), findsNothing);
    expect(find.text('اختر المتجر'), findsNothing);
    expect(
      Directionality.of(tester.element(find.byKey(const Key('shop-empty')))),
      TextDirection.rtl,
    );
  });

  for (final entry in [
    (ShopEntitlement.pending, 'قيد التفعيل'),
    (ShopEntitlement.expired, 'منتهي - للقراءة فقط'),
  ]) {
    testWidgets('${entry.$1.name} account opens without a selection step', (
      tester,
    ) async {
      final shops = FakeShops()..accounts = [account(entry.$1)];
      await pumpGate(tester, shops);
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.text('اختر المتجر'), findsNothing);
      expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    });
  }

  testWidgets('active account opens the daily ledger directly', (tester) async {
    final shops = FakeShops()..accounts = [account(ShopEntitlement.active)];
    await pumpGate(tester, shops);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    expect(find.text('اختر المتجر'), findsNothing);
    expect(find.text('الدفتر اليومي'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
  });

  testWidgets('list RPC failure hides accounts and supports retry', (
    tester,
  ) async {
    final shops = FakeShops()..failList = true;
    await pumpGate(tester, shops);
    expect(find.byKey(const Key('shop-error')), findsOneWidget);
    expect(find.byKey(const Key('shop-empty')), findsNothing);
    shops.failList = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-empty')), findsOneWidget);
    expect(find.text('إنشاء المتجر'), findsNothing);
  });

  testWidgets('revocation closes the ledger on shop refresh', (tester) async {
    final shops = FakeShops()..accounts = [account(ShopEntitlement.active)];
    await pumpGate(tester, shops);
    expect(find.text('الدفتر اليومي'), findsOneWidget);
    shops.accounts = [];
    await replayAppLifecycle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يعد لديك وصول'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
  });

  testWidgets('session expiry removes the shop view', (tester) async {
    final shops = FakeShops()..accounts = [account(ShopEntitlement.active)];
    final auth = FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: AuthGate(
          supabaseStatus: SupabaseStartupStatus.ready,
          authGateway: auth,
          shopAccountGateway: shops,
          onToggleTheme: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الدفتر اليومي'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    auth.expire();
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    await auth.controller.close();
  });

  testWidgets('late shop response cannot cross an owner switch', (
    tester,
  ) async {
    final oldRequest = Completer<List<ShopAccount>>();
    final oldShops = FakeShops()..listCompletion = oldRequest;
    final newShops = FakeShops();
    var userId = 'owner-a';

    Widget gate(FakeShops shops) => MaterialApp(
      locale: const Locale('ar'),
      home: ShopAccountsGate(
        gateway: shops,
        currentUserId: () => userId,
        onSignOut: () async {},
        onToggleTheme: (_) async {},
      ),
    );

    await tester.pumpWidget(gate(oldShops));
    await tester.pump();
    userId = 'owner-b';
    await tester.pumpWidget(gate(newShops));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-empty')), findsOneWidget);

    oldRequest.complete([account(ShopEntitlement.active)]);
    await tester.pump();
    expect(find.byKey(const Key('shop-empty')), findsOneWidget);
    expect(find.byKey(const Key('shop-$shopId')), findsNothing);
  });

  testWidgets('pending and expired shops open the activation dialog once', (
    tester,
  ) async {
    for (final entitlement in [
      ShopEntitlement.pending,
      ShopEntitlement.expired,
    ]) {
      final shops = FakeShops()..accounts = [account(entitlement)];
      await pumpGate(tester, shops);
      expect(find.byKey(const Key('subscription-activation')), findsWidgets);
      expect(find.byKey(const Key('subscription-code')), findsWidgets);
      await tester.tap(find.byKey(const Key('subscription-dismiss')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('subscription-open')), findsOneWidget);
      shops.accounts = [account(entitlement)];
      await replayAppLifecycle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'pending shop follows a remote activation without reopening the dialog',
    (tester) async {
      final shops = FakeShops()..accounts = [account(ShopEntitlement.pending)];
      final sync = FakeSync();
      addTearDown(sync.close);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          home: ShopAccountsGate(
            gateway: shops,
            syncGateway: sync,
            currentUserId: () => 'owner-a',
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('subscription-activation')), findsWidgets);
      await tester.tap(find.byKey(const Key('subscription-dismiss')).last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      shops.accounts = [account(ShopEntitlement.active)];
      sync.latest = const ShopSyncSnapshot(
        shopId: shopId,
        revision: 2,
        subscriptionRevision: 1,
      );
      sync.events.add(sync.latest!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('الدفتر اليومي'), findsOneWidget);
      expect(find.text('قيد التفعيل'), findsNothing);
    },
  );

  testWidgets('pending status fits narrow and desktop in both themes', (
    tester,
  ) async {
    for (final size in [const Size(320, 640), const Size(1440, 900)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final shops = FakeShops()
          ..accounts = [account(ShopEntitlement.pending)];
        await pumpGate(tester, shops, size: size, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('قيد التفعيل'), findsOneWidget);
        expect(find.text('اختر المتجر'), findsNothing);
      }
    }
  });
}

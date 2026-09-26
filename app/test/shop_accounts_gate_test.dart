import 'dart:async';

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
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
    expect(
      Directionality.of(tester.element(find.byKey(const Key('shop-empty')))),
      TextDirection.rtl,
    );
  });

  for (final entry in [
    (ShopEntitlement.pending, 'قيد التفعيل'),
    (ShopEntitlement.expired, 'منتهي - للقراءة فقط'),
  ]) {
    testWidgets('${entry.$1.name} account is not an active shell', (
      tester,
    ) async {
      final shops = FakeShops()..accounts = [account(entry.$1)];
      await pumpGate(tester, shops);
      await tester.tap(find.byKey(const Key('shop-$shopId')));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    });
  }

  testWidgets('active account enters shell only after selection', (
    tester,
  ) async {
    final shops = FakeShops()..accounts = [account(ShopEntitlement.active)];
    await pumpGate(tester, shops);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    expect(find.text(ShellCopy.prototypeLabel), findsOneWidget);
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

  testWidgets('revocation closes selected shop on refresh', (tester) async {
    final shops = FakeShops()..accounts = [account(ShopEntitlement.active)];
    await pumpGate(tester, shops);
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    shops.accounts = [];
    await tester.tap(find.byTooltip('اختيار متجر آخر'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تحديث المتاجر'));
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
    await tester.tap(find.byKey(const Key('shop-$shopId')));
    await tester.pumpAndSettle();
    expect(find.text(ShellCopy.prototypeLabel), findsOneWidget);
    auth.expire();
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    await auth.controller.close();
  });

  testWidgets('selector fits narrow and desktop in both themes', (
    tester,
  ) async {
    for (final size in [const Size(320, 640), const Size(1440, 900)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final shops = FakeShops()
          ..accounts = [account(ShopEntitlement.expired)];
        await pumpGate(tester, shops, size: size, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('اختر المتجر'), findsOneWidget);
      }
    }
  });
}

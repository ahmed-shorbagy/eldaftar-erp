import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/subscription_activation.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const captureDir = '../tmp/batch1/captures';
const sizes = <Size>[Size(320, 640), Size(390, 844), Size(1440, 900)];

class MemoryThemeStore implements ThemePreferenceStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

class CaptureAuth implements AuthGateway {
  CaptureAuth({this.signedIn = false});
  final bool signedIn;
  final controller = StreamController<AuthStatus>.broadcast();

  @override
  AuthStatus get status =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  @override
  Stream<AuthStatus> get changes => controller.stream;
  @override
  Future<void> signIn(SignInRequest request) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Governorate>> loadGovernorates() async => const [
    Governorate(code: 'EG-C', nameAr: 'القاهرة'),
    Governorate(code: 'EG-GZ', nameAr: 'الجيزة'),
  ];
}

class CaptureShops implements ShopAccountGateway {
  CaptureShops(this.accounts);
  final List<ShopAccount> accounts;
  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => accounts;
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

Future<void> savePng(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('batch1-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$captureDir/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in sizes) {
    for (final brightness in Brightness.values) {
      final label = '${brightness.name}-${size.width.toInt()}';
      testWidgets('login shows signup action $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        if (size.width < 840) {
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
        }
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('batch1-capture'),
            child: ElDafttarApp(
              supabaseStatus: SupabaseStartupStatus.ready,
              themeController: ThemeController(
                store: MemoryThemeStore(),
                initial: brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
              ),
              authGateway: CaptureAuth(),
              shopAccountGateway: CaptureShops(const []),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('show-signup')), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('show-signup'))).bottom,
          lessThan(size.height - (size.width < 840 ? 24 : 0)),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/brand/auth-jewelry.png'),
            tester.element(find.byKey(const Key('sign-in-identifier'))),
          ),
        );
        await savePng(tester, 'login-$label.png');
      });

      testWidgets('pending activation dialog $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        if (size.width < 840) {
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
        }
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = CaptureAuth(signedIn: true);
        addTearDown(auth.controller.close);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('batch1-capture'),
            child: ElDafttarApp(
              supabaseStatus: SupabaseStartupStatus.ready,
              themeController: ThemeController(
                store: MemoryThemeStore(),
                initial: brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
              ),
              authGateway: auth,
              shopAccountGateway: CaptureShops(const [
                ShopAccount(
                  id: '11111111-1111-4111-8111-111111111111',
                  name: 'ذهب الجيزة',
                  role: 'owner',
                  entitlement: ShopEntitlement.pending,
                ),
              ]),
              currentUserId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('subscription-activation')), findsWidgets);
        await savePng(tester, 'pending-activation-$label.png');
      });

      testWidgets('expired renewal dialog $label', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        if (size.width < 840) {
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
        }
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = CaptureAuth(signedIn: true);
        addTearDown(auth.controller.close);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('batch1-capture'),
            child: ElDafttarApp(
              supabaseStatus: SupabaseStartupStatus.ready,
              themeController: ThemeController(
                store: MemoryThemeStore(),
                initial: brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
              ),
              authGateway: auth,
              shopAccountGateway: CaptureShops(const [
                ShopAccount(
                  id: '11111111-1111-4111-8111-111111111111',
                  name: 'ذهب الجيزة',
                  role: 'owner',
                  entitlement: ShopEntitlement.expired,
                ),
              ]),
              currentUserId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('subscription-activation')), findsWidgets);
        expect(find.text(SubscriptionCopy.expiredTitle), findsOneWidget);
        await savePng(tester, 'expired-activation-$label.png');
      });
    }
  }
}

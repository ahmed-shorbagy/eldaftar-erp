import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic widget captures for the auth redesign. These are not device proof.
bool fontReady = false;

const reviewSizes = <Size>[
  Size(320, 640),
  Size(390, 844),
  Size(430, 932),
  Size(1440, 900),
];

class CaptureAuth implements AuthGateway {
  CaptureAuth({
    this.governorateGate,
    this.signInGate,
    this.signInFailure,
    this.registrationGate,
    this.signedIn = false,
  });

  final Completer<List<Governorate>>? governorateGate;
  final Completer<void>? signInGate;
  final SignInFailure? signInFailure;
  final Completer<OwnerRegistrationResult>? registrationGate;
  final bool signedIn;

  @override
  AuthStatus get status =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Stream<AuthStatus> get changes => const Stream.empty();

  @override
  Future<void> signIn(SignInRequest request) async {
    final gate = signInGate;
    if (gate != null) await gate.future;
    final failure = signInFailure;
    if (failure != null) throw SignInException(failure);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) async {
    return registrationGate!.future;
  }

  @override
  Future<List<Governorate>> loadGovernorates() {
    final gate = governorateGate;
    if (gate != null) return gate.future;
    return Future.value(const [
      Governorate(code: 'EG-C', nameAr: 'القاهرة'),
      Governorate(code: 'EG-GZ', nameAr: 'الجيزة'),
    ]);
  }
}

class CaptureShops implements ShopAccountGateway {
  CaptureShops({this.pending = false});
  final bool pending;
  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => pending
      ? const [
          ShopAccount(
            id: 'synthetic-shop',
            name: 'ذهب الجيزة',
            role: 'owner',
            entitlement: ShopEntitlement.pending,
          ),
        ]
      : const [];
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

Future<void> captureGuide(WidgetTester tester, String name) async {
  await frames(tester);
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('auth-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '${Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/onboarding-review'}/$name',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

Future<void> reveal(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(
      find.byKey(const Key('auth-scroll')),
      const Offset(0, -320),
    );
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await frames(tester);
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> capture(WidgetTester tester, String name) async {
  await frames(tester);
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(
      Key(
        find.byKey(const Key('auth-capture-boundary')).evaluate().isEmpty
            ? 'auth-result-capture-boundary'
            : 'auth-capture-boundary',
      ),
    ),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    for (final directory in const ['build/owner-feedback-review/auth']) {
      final file = File('$directory/$name');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
    }
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'NotoSansArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in reviewSizes) {
    for (final brightness in Brightness.values) {
      final label = '${brightness.name}-${size.width.toInt()}';
      testWidgets('simple auth and three signup steps $label', (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          onboardingStore: CaptureGuideStore(),
        );
        expect(find.byKey(const Key('onboarding-guide')), findsNothing);
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/brand/auth-jewelry.png'),
            tester.element(find.byKey(const Key('sign-in-identifier'))),
          );
        });
        await frames(tester);
        await capture(tester, 'login-$label.png');
        await reveal(tester, const Key('show-signup'));
        await tester.tap(find.byKey(const Key('show-signup')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await frames(tester);
        await capture(tester, 'signup-account-$label.png');
        for (final pair in {
          'signup-owner-name': 'مالك تجريبي',
          'signup-email': 'owner@example.test',
          'signup-phone': '01012345678',
          'signup-password': 'example-password',
          'signup-password-confirm': 'example-password',
        }.entries) {
          await reveal(tester, Key(pair.key));
          await tester.enterText(find.byKey(Key(pair.key)), pair.value);
        }
        await reveal(tester, const Key('signup-submit'));
        await tester.tap(find.byKey(const Key('signup-submit')));
        await frames(tester);
        await capture(tester, 'signup-shop-$label.png');
        await tester.enterText(
          find.byKey(const Key('signup-business-name')),
          'محل تجريبي',
        );
        await reveal(tester, const Key('signup-governorate'));
        await tester.tap(find.byKey(const Key('signup-governorate')));
        await frames(tester);
        await tester.tap(find.text('الجيزة').last);
        await frames(tester);
        await reveal(tester, const Key('signup-submit'));
        await tester.tap(find.byKey(const Key('signup-submit')));
        await frames(tester);
        await capture(tester, 'signup-review-$label.png');
        expect(tester.takeException(), isNull);
      });
      testWidgets('auth errors with large text and keyboard $label', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, size: size, brightness: brightness, textScale: 1.4);
        await reveal(tester, const Key('sign-in-submit'));
        await tester.tap(find.byKey(const Key('sign-in-submit')));
        await frames(tester);
        await capture(tester, 'login-invalid-$label.png');
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(find.byKey(const Key('sign-in-identifier')));
        await frames(tester);
        await capture(tester, 'login-keyboard-$label.png');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  AuthGateway? gateway,
  double textScale = 1,
  bool confirmed = false,
  OnboardingStore? onboardingStore,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _captureTheme(AppTheme.light(), confirmed),
      darkTheme: _captureTheme(AppTheme.dark(), confirmed),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: RepaintBoundary(
        key: const Key('auth-result-capture-boundary'),
        child: AuthGate(
          supabaseStatus: SupabaseStartupStatus.ready,
          authGateway: gateway ?? CaptureAuth(signedIn: confirmed),
          shopAccountGateway: CaptureShops(pending: confirmed),
          onToggleTheme: (_) async {},
          onboardingStore: onboardingStore,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await frames(tester);
}

ThemeData _captureTheme(ThemeData theme, bool confirmed) => confirmed
    ? theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Tahoma'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Tahoma'),
      )
    : theme;

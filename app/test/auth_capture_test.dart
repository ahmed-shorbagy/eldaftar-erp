import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
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
      '../docs/reviews/onboarding-entry-2026-09-28/widget/$name',
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
    for (final directory in const ['build/auth-review']) {
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
    final loader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await loader.load();
    // The existing post-auth screen keeps platform typography. Match the
    // Windows Arabic face used by the repository's ledger capture harness.
    final platformFont = FontLoader('Tahoma')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(r'C:\Windows\Fonts\tahoma.ttf').readAsBytesSync(),
          ),
        ),
      );
    await platformFont.load();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconLoader.load();
    fontReady = true;
  });

  setUp(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.textScaleFactorTestValue = 1;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets(
    'captures new entry guidance in Arabic RTL at phone and desktop widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in const [Size(320, 640), Size(1440, 900)]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await _pump(
            tester,
            size: size,
            brightness: brightness,
            onboardingStore: CaptureGuideStore(),
          );
          expect(find.byKey(const Key('onboarding-guide')), findsOneWidget);
          await captureGuide(
            tester,
            'login-${brightness.name}-${size.width.toInt()}.png',
          );
          await reveal(tester, const Key('show-signup'));
          await tester.tap(find.byKey(const Key('show-signup')));
          await frames(tester);
          final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const Key('auth-scroll')),
          );
          scroll.controller!.jumpTo(0);
          await frames(tester);
          await captureGuide(
            tester,
            'signup-${brightness.name}-${size.width.toInt()}.png',
          );
        }
      }
    },
  );

  testWidgets('captures the confirmed account awaiting shop activation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in reviewSizes) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          confirmed: true,
        );
        expect(find.text('قيد التفعيل'), findsOneWidget);
        expect(find.byKey(const Key('signup-submit')), findsNothing);
        await capture(
          tester,
          'signup-confirmed-${brightness.name}-${size.width.toInt()}.png',
        );
      }
    }
  });

  testWidgets('captures login and registration at phone and desktop widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(fontReady, isTrue, reason: 'The bundled Arabic font must load');

    for (final size in reviewSizes) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final label = '${brightness.name}-${size.width.toInt()}';
        final registration = Completer<OwnerRegistrationResult>();
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          gateway: CaptureAuth(registrationGate: registration),
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-identifier')),
          'owner@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-password')),
          'example-password',
        );
        await capture(tester, 'login-email-$label.png');

        await tester.enterText(
          find.byKey(const Key('sign-in-identifier')),
          '01012345678',
        );
        await frames(tester);
        expect(find.text(AuthCopy.detectedPhone), findsOneWidget);
        await capture(tester, 'login-phone-$label.png');

        await reveal(tester, const Key('show-signup'));
        await tester.tap(find.byKey(const Key('show-signup')));
        await frames(tester);
        await tester.enterText(
          find.byKey(const Key('signup-owner-name')),
          'منى حسن',
        );
        await tester.enterText(
          find.byKey(const Key('signup-business-name')),
          'ذهب الجيزة',
        );
        await reveal(tester, const Key('signup-email'));
        await tester.enterText(
          find.byKey(const Key('signup-email')),
          'owner@example.test',
        );
        await reveal(tester, const Key('signup-phone'));
        await tester.enterText(
          find.byKey(const Key('signup-phone')),
          '01012345678',
        );
        await reveal(tester, const Key('signup-governorate'));
        await tester.tap(find.byKey(const Key('signup-governorate')));
        await frames(tester);
        await tester.tap(find.text('الجيزة').last);
        await frames(tester);
        await reveal(tester, const Key('signup-password'));
        await tester.enterText(
          find.byKey(const Key('signup-password')),
          'example-password',
        );
        final list = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('auth-scroll')),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        list.controller!.jumpTo(0);
        await tester.pumpAndSettle();
        expect(list.controller!.offset, 0);
        await capture(tester, 'signup-top-$label.png');
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await frames(tester);
        await capture(tester, 'signup-lower-$label.png');
        await reveal(tester, const Key('signup-submit'));
        await tester.tap(find.byKey(const Key('signup-submit')));
        await frames(tester);
        await capture(tester, 'signup-submitting-$label.png');
        registration.completeError(
          const RegistrationException(RegistrationFailure.unknownOutcome),
        );
        await frames(tester);
        await reveal(tester, const Key('signup-unknown'));
        await capture(tester, 'signup-pending-$label.png');
      }
    }
  });

  testWidgets('captures keyboard inset, long errors, large text, and pending', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    for (final size in reviewSizes) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final label = '${brightness.name}-${size.width.toInt()}';
        await _pump(tester, size: size, brightness: brightness);
        await tester.enterText(
          find.byKey(const Key('sign-in-identifier')),
          'owner@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-password')),
          'example-password',
        );
        await tester.tap(find.byKey(const Key('sign-in-password')));
        await frames(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await frames(tester);
        await reveal(tester, const Key('sign-in-password'));
        await capture(tester, 'login-keyboard-field-$label.png');
        await reveal(tester, const Key('sign-in-submit'));
        await capture(tester, 'login-keyboard-submit-$label.png');
        tester.view.resetViewInsets();
        await frames(tester);

        await _pump(
          tester,
          size: size,
          brightness: brightness,
          gateway: CaptureAuth(signInFailure: SignInFailure.invalidCredentials),
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-identifier')),
          'owner@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-password')),
          'example-password',
        );
        await reveal(tester, const Key('sign-in-submit'));
        await tester.tap(find.byKey(const Key('sign-in-submit')));
        await frames(tester);
        expect(find.text(AuthCopy.signInFailed), findsOneWidget);
        await reveal(tester, const Key('sign-in-error'));
        await capture(tester, 'login-error-$label.png');

        await _pump(tester, size: size, brightness: brightness, textScale: 2);
        await capture(tester, 'login-largetext-$label.png');
        await reveal(tester, const Key('show-signup'));
        await tester.tap(find.byKey(const Key('show-signup')));
        await frames(tester);
        final scaled = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('auth-scroll')),
        );
        scaled.controller!.jumpTo(0);
        await frames(tester);
        await capture(tester, 'signup-largetext-$label.png');

        final signInGate = Completer<void>();
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          gateway: CaptureAuth(signInGate: signInGate),
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-identifier')),
          'owner@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-password')),
          'example-password',
        );
        await reveal(tester, const Key('sign-in-submit'));
        await tester.tap(find.byKey(const Key('sign-in-submit')));
        await frames(tester);
        expect(find.text(AuthCopy.signInBusy), findsOneWidget);
        expect(find.textContaining('تم '), findsNothing);
        await capture(tester, 'login-pending-$label.png');
        signInGate.complete();
        await frames(tester);

        final governorates = Completer<List<Governorate>>();
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          gateway: CaptureAuth(governorateGate: governorates),
        );
        await reveal(tester, const Key('show-signup'));
        await tester.tap(find.byKey(const Key('show-signup')));
        await frames(tester);
        expect(find.text(AuthCopy.governorateLoading), findsOneWidget);
        await capture(tester, 'signup-loading-$label.png');
        governorates.complete(const [
          Governorate(code: 'EG-GZ', nameAr: 'الجيزة'),
        ]);
        await frames(tester);

        await _pump(tester, size: size, brightness: brightness);
        await reveal(tester, const Key('show-signup'));
        await tester.tap(find.byKey(const Key('show-signup')));
        await frames(tester);
        await reveal(tester, const Key('signup-submit'));
        await tester.tap(find.byKey(const Key('signup-submit')));
        await frames(tester);
        expect(find.text(AuthCopy.ownerInvalid), findsOneWidget);
        final invalid = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('auth-scroll')),
        );
        invalid.controller!.jumpTo(0);
        await frames(tester);
        await capture(tester, 'signup-invalid-$label.png');
      }
    }
  });
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

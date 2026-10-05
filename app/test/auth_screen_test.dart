import 'dart:async';

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:flutter_test/flutter_test.dart';

const shopId = '11111111-1111-4111-8111-111111111111';

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class MemoryOnboardingStore implements OnboardingStore {
  final completed = <String>{};
  final steps = <String, int>{};

  @override
  Future<bool> isComplete(String path) async => completed.contains(path);

  @override
  Future<int> readStep(String path) async => steps[path] ?? 0;

  @override
  Future<void> saveStep(String path, int step) async {
    steps[path] = step;
  }

  @override
  Future<void> markComplete(String path) async {
    completed.add(path);
  }
}

class ScriptedAuth implements AuthGateway {
  AuthStatus current = AuthStatus.signedOut;
  final controller = StreamController<AuthStatus>.broadcast();
  final registrations = <OwnerRegistration>[];
  final signIns = <SignInRequest>[];
  Completer<OwnerRegistrationResult>? registration;
  Completer<void>? signInGate;
  SignInFailure? signInFailure;
  bool emitSignedInImmediately = false;
  bool failGovernorates = false;
  Completer<List<Governorate>>? governorateGate;
  List<Governorate> governorates = const [
    Governorate(code: 'EG-GZ', nameAr: 'الجيزة'),
  ];

  @override
  AuthStatus get status => current;

  @override
  Stream<AuthStatus> get changes => controller.stream;

  @override
  Future<void> signIn(SignInRequest request) async {
    signIns.add(request);
    final gate = signInGate;
    if (gate != null) await gate.future;
    final failure = signInFailure;
    if (failure != null) throw SignInException(failure);
    current = AuthStatus.signedIn;
    controller.add(current);
  }

  @override
  Future<void> signOut() async {
    current = AuthStatus.signedOut;
    controller.add(current);
  }

  @override
  Future<List<Governorate>> loadGovernorates() {
    if (governorateGate != null) return governorateGate!.future;
    if (failGovernorates) {
      throw const GovernorateLoadException(GovernorateLoadFailure.unavailable);
    }
    return Future.value(governorates);
  }

  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) {
    registrations.add(registration);
    if (emitSignedInImmediately) controller.add(AuthStatus.signedIn);
    return (this.registration ?? Completer<OwnerRegistrationResult>()).future
        .then((result) {
          current = AuthStatus.signedIn;
          controller.add(current);
          return result;
        });
  }

  Future<void> close() => controller.close();
}

class ScriptedShops implements ShopAccountGateway {
  List<ShopAccount> accounts = const [];

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => accounts;
}

Future<ScriptedAuth> pumpAuth(
  WidgetTester tester, {
  ScriptedAuth? auth,
  ScriptedShops? shops,
  MemoryThemePreferenceStore? store,
  OnboardingStore? onboardingStore,
  Size size = const Size(420, 1200),
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  double keyboardInset = 0,
  bool reduceMotion = false,
  FakeViewPadding systemPadding = FakeViewPadding.zero,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  tester.view.padding = systemPadding;
  tester.view.viewPadding = systemPadding;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(
        disableAnimations: reduceMotion,
        reduceMotion: reduceMotion,
      );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final gateway = auth ?? ScriptedAuth();
  addTearDown(gateway.close);
  await tester.pumpWidget(
    ElDafttarApp(
      supabaseStatus: SupabaseStartupStatus.ready,
      themeController: ThemeController(store: store, initial: mode),
      authGateway: gateway,
      shopAccountGateway: shops ?? ScriptedShops(),
      onboardingStore: onboardingStore,
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

Future<void> openSignup(WidgetTester tester) async {
  final button = find.byKey(const Key('show-signup'));
  for (var attempt = 0; attempt < 8 && button.evaluate().isEmpty; attempt++) {
    await tester.drag(
      find.byKey(const Key('auth-scroll')),
      const Offset(0, -320),
    );
    await tester.pump();
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> fillSignup(WidgetTester tester, {String country = 'EG'}) async {
  for (final field in {
    'signup-owner-name': 'منى حسن',
    'signup-email': 'Owner@Example.TEST',
    'signup-phone': country == 'EG' ? '01012345678' : '0501234567',
    'signup-password': 'example-password',
    'signup-password-confirm': 'example-password',
  }.entries) {
    await tester.ensureVisible(find.byKey(Key(field.key)));
    await tester.enterText(find.byKey(Key(field.key)), field.value);
  }
  if (country != 'EG') {
    await tester.ensureVisible(find.byKey(const Key('signup-phone')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('signup-phone')),
        matching: find.byType(CountryButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('السعودية').last);
    await tester.pumpAndSettle();
  }
  await nextSignup(tester);
  await tester.enterText(
    find.byKey(const Key('signup-business-name')),
    'ذهب الجيزة',
  );
  if (country == 'EG') {
    await tester.tap(find.byKey(const Key('signup-governorate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الجيزة').last);
    await tester.pumpAndSettle();
  } else {
    await tester.enterText(find.byKey(const Key('signup-region')), 'الرياض');
  }
  await nextSignup(tester);
}

Future<void> nextSignup(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('signup-submit')));
  await tester.tap(find.byKey(const Key('signup-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets(
    'phone picker searches Arabic countries and pasting switches dial code',
    (tester) async {
      await pumpAuth(tester);
      await openSignup(tester);
      await tester.ensureVisible(find.byKey(const Key('signup-phone')));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('signup-phone')),
          matching: find.byType(CountryButton),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'ابحث عن الدولة أو كودها',
      );
      await tester.enterText(search, 'سع');
      await tester.pump();
      await tester.enterText(search, 'السعودية');
      await tester.pumpAndSettle();
      expect(find.text('المملكة العربية السعودية'), findsOneWidget);
      await tester.tap(find.text('المملكة العربية السعودية'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('signup-phone')),
        '+971501234567',
      );
      await tester.pumpAndSettle();
      final field = tester.widget<PhoneFormField>(
        find.byKey(const Key('signup-phone')),
      );
      expect(field.controller!.value.isoCode, IsoCode.AE);
      expect(field.controller!.value.international, '+971501234567');
      expect(field.enabled, isTrue);
    },
  );
  testWidgets(
    'empty account step validates only visible fields without a request',
    (tester) async {
      final auth = await pumpAuth(tester);
      await openSignup(tester);
      await nextSignup(tester);
      expect(auth.registrations, isEmpty);
      expect(find.text(AuthCopy.ownerInvalid), findsOneWidget);
      expect(find.text(AuthCopy.emailInvalid), findsOneWidget);
      expect(find.text(AuthCopy.phoneInvalid), findsOneWidget);
      expect(find.byKey(const Key('signup-business-name')), findsNothing);
    },
  );
  testWidgets(
    'signup requires separate email and phone fields and matching passwords',
    (tester) async {
      final auth = await pumpAuth(tester);
      await openSignup(tester);
      await tester.enterText(
        find.byKey(const Key('signup-email')),
        '01012345678',
      );
      await tester.enterText(
        find.byKey(const Key('signup-phone')),
        'owner@example.test',
      );
      await tester.ensureVisible(find.byKey(const Key('signup-password')));
      await tester.enterText(
        find.byKey(const Key('signup-password')),
        'example-password',
      );
      await tester.enterText(
        find.byKey(const Key('signup-password-confirm')),
        'different-password',
      );
      await nextSignup(tester);
      expect(find.text(AuthCopy.emailInvalid), findsOneWidget);
      expect(find.text(AuthCopy.phoneInvalid), findsOneWidget);
      expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
      expect(auth.registrations, isEmpty);
    },
  );
  testWidgets(
    'all signup steps preserve input and require final confirmation',
    (tester) async {
      final auth = await pumpAuth(tester);
      await openSignup(tester);
      await fillSignup(tester);
      expect(auth.registrations, isEmpty);
      expect(find.text('ذهب الجيزة'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('signup-back')));
      await tester.tap(find.byKey(const Key('signup-back')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('signup-business-name')),
      );
      expect(field.controller!.text, 'ذهب الجيزة');
      await nextSignup(tester);
      await nextSignup(tester);
      expect(auth.registrations, hasLength(1));
      expect(auth.registrations.single.phone, '+201012345678');
    },
  );
  testWidgets(
    'international country sets phone code and manual region in the server request',
    (tester) async {
      final auth = await pumpAuth(tester);
      await openSignup(tester);
      await fillSignup(tester, country: 'SA');
      await nextSignup(tester);
      expect(auth.registrations.single.phone, '+966501234567');
      expect(auth.registrations.single.governorateCode, 'SA:الرياض');
    },
  );
  testWidgets('signup never unlocks shop access on an early auth event', (
    tester,
  ) async {
    final auth = ScriptedAuth()
      ..registration = Completer()
      ..emitSignedInImmediately = true;
    await pumpAuth(tester, auth: auth);
    await openSignup(tester);
    await fillSignup(tester);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    expect(find.byKey(const Key('auth-progress')), findsOneWidget);
    expect(find.byKey(const Key('ledger-title')), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('signup-submit')),
    );
    expect(button.onPressed, isNull);
    auth.registration!.completeError(
      const RegistrationException(RegistrationFailure.unknownOutcome),
    );
    await tester.pumpAndSettle();
  });
  testWidgets('unknown registration retries original key and profile', (
    tester,
  ) async {
    final auth = ScriptedAuth()..registration = Completer();
    await pumpAuth(tester, auth: auth);
    await openSignup(tester);
    await fillSignup(tester);
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    auth.registration!.completeError(
      const RegistrationException(RegistrationFailure.unknownOutcome),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-unknown')), findsOneWidget);
    auth.registration = Completer();
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    expect(auth.registrations, hasLength(2));
    expect(
      auth.registrations[0].idempotencyKey,
      auth.registrations[1].idempotencyKey,
    );
    expect(auth.registrations[0].samePayloadAs(auth.registrations[1]), isTrue);
    auth.registration!.completeError(
      const RegistrationException(RegistrationFailure.unknownOutcome),
    );
    await tester.pumpAndSettle();
  });
  testWidgets(
    'login classifies phone or email, supports password paste, rejects duplicate submit',
    (tester) async {
      final auth = ScriptedAuth()..signInGate = Completer();
      await pumpAuth(tester, auth: auth);
      await tester.enterText(
        find.byKey(const Key('sign-in-identifier')),
        '+966501234567',
      );
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'example-password',
      );
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pump();
      expect(auth.signIns.single.identifier, '+966501234567');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sign-in-submit')))
            .onPressed,
        isNull,
      );
      auth.signInGate!.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'failed login shows readable Arabic failure and stays signed out',
    (tester) async {
      final auth = ScriptedAuth()
        ..signInFailure = SignInFailure.invalidCredentials;
      await pumpAuth(tester, auth: auth);
      await tester.enterText(
        find.byKey(const Key('sign-in-identifier')),
        'owner@example.test',
      );
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'example-password',
      );
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-error')), findsOneWidget);
      expect(find.byKey(const Key('ledger-title')), findsNothing);
    },
  );
  testWidgets(
    'theme choice persists and onboarding never appears or writes its store',
    (tester) async {
      final guide = MemoryOnboardingStore();
      final theme = MemoryThemePreferenceStore();
      await pumpAuth(tester, store: theme, onboardingStore: guide);
      expect(find.byKey(const Key('auth-help')), findsNothing);
      expect(find.byKey(const Key('onboarding-guide')), findsNothing);
      await tester.tap(find.byKey(const Key('auth-theme-toggle')));
      await tester.pumpAndSettle();
      expect(theme.value, 'dark');
      await openSignup(tester);
      expect(find.byKey(const Key('onboarding-guide')), findsNothing);
      expect(guide.steps, isEmpty);
    },
  );
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final width in [320.0, 390.0, 1440.0]) {
      testWidgets('forms fit RTL $mode $width with large text and keyboard', (
        tester,
      ) async {
        await pumpAuth(
          tester,
          mode: mode,
          size: Size(width, 900),
          textScale: 1.3,
          keyboardInset: 260,
        );
        await tester.ensureVisible(find.byKey(const Key('sign-in-submit')));
        expect(
          find.byKey(const Key('sign-in-submit')).hitTestable(),
          findsOneWidget,
        );
        await openSignup(tester);
        await tester.ensureVisible(
          find.byKey(const Key('signup-password-confirm')),
        );
        expect(
          find.byKey(const Key('signup-password-confirm')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

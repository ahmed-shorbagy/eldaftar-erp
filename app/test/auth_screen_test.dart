import 'dart:async';

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/shell/shell_copy.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
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

Future<void> fillSignup(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('signup-owner-name')));
  await tester.enterText(find.byKey(const Key('signup-owner-name')), 'منى حسن');
  await tester.enterText(
    find.byKey(const Key('signup-business-name')),
    'ذهب الجيزة',
  );
  await tester.enterText(
    find.byKey(const Key('signup-email')),
    'Owner@Example.TEST',
  );
  await tester.enterText(
    find.byKey(const Key('signup-phone')),
    '(010) 1234-5678',
  );
  await tester.ensureVisible(find.byKey(const Key('signup-governorate')));
  await tester.tap(find.byKey(const Key('signup-governorate')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('الجيزة').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('signup-password')));
  await tester.enterText(
    find.byKey(const Key('signup-password')),
    'example-password',
  );
}

TextDirection? fieldDirection(WidgetTester tester, Key key) {
  return editableField(tester, key).textDirection;
}

TextField editableField(WidgetTester tester, Key key) {
  return tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
  );
}

void main() {
  testWidgets('signup rejects an empty form before calling the gateway', (
    tester,
  ) async {
    final auth = await pumpAuth(tester);
    await openSignup(tester);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    expect(auth.registrations, isEmpty);
    expect(find.text(AuthCopy.ownerInvalid), findsOneWidget);
    expect(find.text(AuthCopy.businessInvalid), findsOneWidget);
    expect(find.text(AuthCopy.contactInvalid), findsNWidgets(2));
    expect(find.text(AuthCopy.governorateInvalid), findsOneWidget);
    expect(find.text(AuthCopy.passwordInvalid), findsOneWidget);
  });

  testWidgets('signup accepts the phone and email in either field', (
    tester,
  ) async {
    final auth = ScriptedAuth()..registration = Completer();
    await pumpAuth(tester, auth: auth);
    await openSignup(tester);
    await fillSignup(tester);
    await tester.enterText(
      find.byKey(const Key('signup-email')),
      '01012345678',
    );
    await tester.enterText(
      find.byKey(const Key('signup-phone')),
      'Owner@Example.TEST',
    );
    await tester.pump();
    expect(find.text(AuthCopy.phoneLabel), findsWidgets);
    expect(find.text(AuthCopy.emailLabel), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();

    expect(auth.registrations, hasLength(1));
    expect(auth.registrations.single.email, 'owner@example.test');
    expect(auth.registrations.single.phone, '+201012345678');
    auth.registration!.complete(
      const OwnerRegistrationResult(userId: shopId, shopId: shopId),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('invalid phone does not start registration', (tester) async {
    final auth = await pumpAuth(tester);
    await openSignup(tester);
    await fillSignup(tester);
    await tester.enterText(find.byKey(const Key('signup-phone')), '12345');
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    expect(auth.registrations, isEmpty);
    expect(find.text(AuthCopy.phoneInvalid), findsOneWidget);
  });

  testWidgets(
    'duplicate taps do not send a second signup while one is in flight',
    (tester) async {
      final auth = ScriptedAuth()..registration = Completer();
      await pumpAuth(tester, auth: auth);
      await openSignup(tester);
      await fillSignup(tester);
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();

      expect(find.text(AuthCopy.signUpBusy), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('signup-submit')))
            .onPressed,
        isNull,
      );
      expect(auth.registrations, hasLength(1));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();
      expect(auth.registrations, hasLength(1));
      auth.registration!.complete(
        const OwnerRegistrationResult(userId: shopId, shopId: shopId),
      );
      await tester.pumpAndSettle();
    },
  );

  for (final failure in [
    RegistrationFailure.unknownOutcome,
    RegistrationFailure.unavailable,
  ]) {
    testWidgets('${failure.name} retry keeps the key and normalized payload', (
      tester,
    ) async {
      final auth = ScriptedAuth()..registration = Completer();
      await pumpAuth(tester, auth: auth);
      await openSignup(tester);
      await fillSignup(tester);
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();
      auth.registration!.completeError(RegistrationException(failure));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signup-unknown')), findsOneWidget);
      expect(find.text(AuthCopy.signupUnknown), findsOneWidget);
      expect(find.textContaining('تم إنشاء'), findsNothing);
      expect(find.textContaining('تم حفظ'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('signup-email')))
            .enabled,
        isFalse,
      );
      tester
              .widget<TextFormField>(find.byKey(const Key('signup-email')))
              .controller!
              .text =
          'other@example.test';
      auth.registration = Completer();
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();

      expect(auth.registrations, hasLength(2));
      expect(
        auth.registrations[0].idempotencyKey,
        auth.registrations[1].idempotencyKey,
      );
      expect(auth.registrations[1].email, 'owner@example.test');
      expect(auth.registrations[1].phone, '+201012345678');
      expect(auth.registrations[1].ownerName, 'منى حسن');
      expect(auth.registrations[1].businessName, 'ذهب الجيزة');
      expect(auth.registrations[1].governorateCode, 'EG-GZ');
      expect(auth.registrations[1].password, auth.registrations[0].password);
      expect(IdempotencyKey.isV4(auth.registrations[0].idempotencyKey), isTrue);
      auth.registration!.completeError(RegistrationException(failure));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'server rejection stays on the form and an early auth event does not open a shop',
    (tester) async {
      final auth = ScriptedAuth()
        ..emitSignedInImmediately = true
        ..registration = Completer();
      await pumpAuth(tester, auth: auth);
      await openSignup(tester);
      await fillSignup(tester);
      await tester.ensureVisible(find.byKey(const Key('signup-submit')));
      await tester.tap(find.byKey(const Key('signup-submit')));
      await tester.pump();

      expect(find.text(AuthCopy.signUpBusy), findsOneWidget);
      expect(find.text('اختر المتجر'), findsNothing);
      auth.registration!.completeError(
        const RegistrationException(RegistrationFailure.identifierTaken),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signup-error')), findsOneWidget);
      expect(find.text(AuthCopy.signupIdentifierTaken), findsOneWidget);
      expect(find.byKey(const Key('signup-unknown')), findsNothing);
      expect(find.text('قيد التفعيل'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('signup-owner-name')))
            .enabled,
        isTrue,
      );
    },
  );

  testWidgets('confirmed registration opens the pending membership list', (
    tester,
  ) async {
    final auth = ScriptedAuth()..registration = Completer();
    final shops = ScriptedShops()
      ..accounts = [
        const ShopAccount(
          id: shopId,
          name: 'ذهب الجيزة',
          role: 'owner',
          entitlement: ShopEntitlement.pending,
        ),
      ];
    await pumpAuth(tester, auth: auth, shops: shops);
    await openSignup(tester);
    await fillSignup(tester);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();
    auth.registration!.complete(
      const OwnerRegistrationResult(userId: shopId, shopId: shopId),
    );
    await tester.pumpAndSettle();

    expect(find.text('قيد التفعيل'), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsNothing);
    expect(find.byKey(const Key('signup-submit')), findsNothing);
  });

  testWidgets('governorate failure keeps the signup draft and can be retried', (
    tester,
  ) async {
    final auth = ScriptedAuth()..failGovernorates = true;
    await pumpAuth(tester, auth: auth);
    await openSignup(tester);

    expect(find.byKey(const Key('governorate-error')), findsOneWidget);
    expect(find.byKey(const Key('signup-governorate')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('signup-owner-name')),
      'اسم قيد الكتابة',
    );
    auth.governorateGate = Completer<List<Governorate>>();
    auth.failGovernorates = false;
    await tester.tap(find.byKey(const Key('governorate-retry')));
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('signup-owner-name')))
          .controller!
          .text,
      'اسم قيد الكتابة',
    );
    auth.governorateGate!.complete(auth.governorates);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('signup-owner-name')))
          .controller!
          .text,
      'اسم قيد الكتابة',
    );
    await tester.ensureVisible(find.byKey(const Key('signup-governorate')));
    await tester.tap(find.byKey(const Key('signup-governorate')));
    await tester.pumpAndSettle();
    expect(find.text('الجيزة'), findsWidgets);
  });

  testWidgets(
    'contact fields are left-to-right and the theme control does not store the password',
    (tester) async {
      final store = MemoryThemePreferenceStore();
      await pumpAuth(tester, store: store);
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'example-password',
      );
      expect(
        fieldDirection(tester, const Key('sign-in-identifier')),
        TextDirection.ltr,
      );
      await tester.tap(find.byTooltip(ShellCopy.toggleToDark));
      await tester.pumpAndSettle();
      expect(store.value, 'dark');
      expect(store.value, isNot(contains('example-password')));

      await openSignup(tester);
      expect(
        fieldDirection(tester, const Key('signup-phone')),
        TextDirection.ltr,
      );
      expect(
        fieldDirection(tester, const Key('signup-email')),
        TextDirection.ltr,
      );
      await tester.enterText(find.byKey(const Key('signup-owner-name')), 'منى');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        Focus.of(
          tester.element(find.byKey(const Key('signup-business-name'))),
        ).hasFocus,
        isTrue,
      );
    },
  );

  testWidgets('signup lays out at phone and desktop widths', (tester) async {
    for (final size in const [Size(320, 640), Size(1440, 900)]) {
      await pumpAuth(tester, size: size);
      await openSignup(tester);
      expect(tester.takeException(), isNull);
      final password = find.byKey(const Key('signup-password'));
      for (
        var attempt = 0;
        attempt < 8 && password.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(
          find.byKey(const Key('auth-scroll')),
          const Offset(0, -280),
        );
        await tester.pump();
      }
      expect(password, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'typing switches between email and phone without a separate choice',
    (tester) async {
      final auth = await pumpAuth(tester);
      await tester.enterText(
        find.byKey(const Key('sign-in-identifier')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const Key('sign-in-password')),
        'example-password',
      );
      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pumpAndSettle();
      expect(find.text(AuthCopy.emailInvalid), findsOneWidget);
      expect(find.text(AuthCopy.emailLabel), findsOneWidget);
      expect(auth.signIns, isEmpty);

      await tester.enterText(
        find.byKey(const Key('sign-in-identifier')),
        '01012345678',
      );
      await tester.pumpAndSettle();
      expect(find.text(AuthCopy.emailInvalid), findsNothing);
      expect(find.text(AuthCopy.detectedPhone), findsOneWidget);
      expect(
        controllerText(tester, const Key('sign-in-password')),
        'example-password',
      );
      expect(find.byKey(const Key('sign-in-kind-phone')), findsNothing);

      await tester.tap(find.byKey(const Key('sign-in-submit')));
      await tester.pumpAndSettle();
      expect(auth.signIns, hasLength(1));
      expect(auth.signIns.single.kind, SignInIdentifier.phone);
      expect(auth.signIns.single.identifier, '+201012345678');
    },
  );

  testWidgets('password reveal, autofill hints, and paste stay available', (
    tester,
  ) async {
    await pumpAuth(tester);
    final email = editableField(tester, const Key('sign-in-identifier'));
    final password = editableField(tester, const Key('sign-in-password'));
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(email.autofillHints, [
      AutofillHints.username,
      AutofillHints.email,
      AutofillHints.telephoneNumber,
    ]);
    expect(email.enableInteractiveSelection, isTrue);
    expect(email.keyboardType, TextInputType.emailAddress);
    expect(email.textInputAction, TextInputAction.next);
    expect(password.autofillHints, [AutofillHints.password]);
    expect(password.obscureText, isTrue);
    expect(password.enableInteractiveSelection, isTrue);
    expect(password.keyboardType, TextInputType.visiblePassword);
    expect(password.textInputAction, TextInputAction.done);
    expect(password.inputFormatters, isNull);
    expect(find.byTooltip(AuthCopy.showPassword), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-in-identifier')));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Owner@Example.TEST',
        selection: TextSelection.collapsed(offset: 18),
      ),
    );
    await tester.pump();
    expect(
      controllerText(tester, const Key('sign-in-identifier')),
      'Owner@Example.TEST',
    );

    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'example-password',
    );
    await tester.tap(find.byKey(const Key('password-visibility')));
    await tester.pump();
    expect(
      editableField(tester, const Key('sign-in-password')).obscureText,
      isFalse,
    );
    expect(find.byTooltip(AuthCopy.hidePassword), findsOneWidget);
    expect(
      controllerText(tester, const Key('sign-in-password')),
      'example-password',
    );
    expect(
      fieldDirection(tester, const Key('sign-in-password')),
      TextDirection.ltr,
    );

    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      '01012345678',
    );
    await tester.pump();
    expect(find.text(AuthCopy.phoneLabel), findsOneWidget);
    expect(
      fieldDirection(tester, const Key('sign-in-identifier')),
      TextDirection.ltr,
    );

    await openSignup(tester);
    expect(editableField(tester, const Key('signup-email')).autofillHints, [
      AutofillHints.email,
      AutofillHints.telephoneNumber,
    ]);
    expect(editableField(tester, const Key('signup-phone')).autofillHints, [
      AutofillHints.email,
      AutofillHints.telephoneNumber,
    ]);
    expect(
      editableField(tester, const Key('signup-email')).keyboardType,
      TextInputType.emailAddress,
    );
    expect(editableField(tester, const Key('signup-password')).autofillHints, [
      AutofillHints.newPassword,
    ]);
    expect(find.byKey(const Key('governorate-refresh')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('signup-submit'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .widget<ConstrainedBox>(find.byKey(const Key('auth-measure')))
          .constraints
          .maxWidth,
      480,
    );
  });

  testWidgets('empty signup focuses and reveals the first invalid field', (
    tester,
  ) async {
    await pumpAuth(tester, size: const Size(320, 640));
    await openSignup(tester);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();

    final owner = find.byKey(const Key('signup-owner-name'));
    expect(owner.hitTestable(), findsOneWidget);
    expect(Focus.of(tester.element(owner)).hasFocus, isTrue);
    expect(find.text(AuthCopy.ownerInvalid).hitTestable(), findsOneWidget);
    expect(find.text(AuthCopy.businessInvalid), findsOneWidget);
    expect(find.text(AuthCopy.contactInvalid), findsNWidgets(2));
    expect(find.text(AuthCopy.governorateInvalid), findsOneWidget);
    expect(find.text(AuthCopy.passwordInvalid), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('auth-field-alert')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });

  testWidgets('registration back keeps the draft', (tester) async {
    await pumpAuth(tester);
    await openSignup(tester);
    await tester.enterText(
      find.byKey(const Key('signup-owner-name')),
      'اسم قيد الكتابة',
    );
    await tester.enterText(
      find.byKey(const Key('signup-business-name')),
      'ذهب الجيزة',
    );
    await tester.enterText(
      find.byKey(const Key('signup-email')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('signup-password')),
      'example-password',
    );
    await tester.ensureVisible(find.byKey(const Key('signup-back')));
    await tester.tap(find.byKey(const Key('signup-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
    expect(
      controllerText(tester, const Key('sign-in-identifier')),
      'owner@example.test',
    );
    expect(
      controllerText(tester, const Key('sign-in-password')),
      'example-password',
    );

    await openSignup(tester);
    expect(
      controllerText(tester, const Key('signup-owner-name')),
      'اسم قيد الكتابة',
    );
    expect(
      controllerText(tester, const Key('signup-business-name')),
      'ذهب الجيزة',
    );
    expect(
      controllerText(tester, const Key('signup-email')),
      'owner@example.test',
    );
    expect(
      controllerText(tester, const Key('signup-password')),
      'example-password',
    );
  });

  testWidgets(
    'keyboard inset and large text can reach the field and the submit control',
    (tester) async {
      await pumpAuth(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        keyboardInset: 300,
      );
      await openSignup(tester);
      expect(tester.takeException(), isNull);

      final password = find.byKey(const Key('signup-password'));
      final submit = find.byKey(const Key('signup-submit'));
      await tester.ensureVisible(password);
      await tester.pumpAndSettle();
      expect(password.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('signup-owner-name')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('signup-owner-name')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sign-in-identifier')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate sign-in taps do not send a second request', (
    tester,
  ) async {
    final auth = ScriptedAuth()..signInGate = Completer<void>();
    await pumpAuth(tester, auth: auth);
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'example-password',
    );
    await tester.ensureVisible(find.byKey(const Key('sign-in-submit')));
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump();

    expect(find.text(AuthCopy.signInBusy), findsOneWidget);
    expect(find.textContaining('تم '), findsNothing);
    expect(find.byKey(const Key('auth-progress')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('sign-in-submit')))
          .onPressed,
      isNull,
    );
    expect(auth.signIns, hasLength(1));
    await tester.tap(
      find.byKey(const Key('sign-in-submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(auth.signIns, hasLength(1));

    auth.signInGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-submit')), findsNothing);
    expect(find.byKey(const Key('shop-empty')), findsOneWidget);
  });

  testWidgets('a long sign-in failure wraps in a live region', (tester) async {
    final auth = ScriptedAuth()
      ..signInFailure = SignInFailure.invalidCredentials;
    await pumpAuth(tester, auth: auth, size: const Size(320, 640));
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'example-password',
    );
    await tester.ensureVisible(find.byKey(const Key('sign-in-submit')));
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pumpAndSettle();

    final message = tester.widget<Text>(find.byKey(const Key('sign-in-error')));
    expect(message.data, AuthCopy.signInFailed);
    expect(message.softWrap, isTrue);
    expect(message.maxLines, isNull);
    expect(
      message.overflow,
      anyOf(isNull, TextOverflow.clip, TextOverflow.visible),
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('auth-server-status')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.textContaining('تم '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion still focuses the first invalid field', (
    tester,
  ) async {
    await pumpAuth(tester, size: const Size(320, 640), reduceMotion: true);
    await openSignup(tester);
    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.tap(find.byKey(const Key('signup-submit')));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      Focus.of(
        tester.element(find.byKey(const Key('signup-owner-name'))),
      ).hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('safe area keeps the last control above the system inset', (
    tester,
  ) async {
    const height = 844.0;
    await pumpAuth(
      tester,
      size: const Size(390, height),
      systemPadding: const FakeViewPadding(top: 48, bottom: 34),
    );

    final media = MediaQuery.paddingOf(tester.element(find.byType(Scaffold)));
    expect(media.top, 48);
    expect(media.bottom, 34);
    expect(
      tester.getTopLeft(find.text(AuthCopy.signInTitle)).dy,
      greaterThanOrEqualTo(48),
    );
    final link = find.byKey(const Key('show-signup'));
    await tester.ensureVisible(link);
    expect(tester.getBottomLeft(link).dy, lessThanOrEqualTo(height - 34));
    expect(
      tester.getSize(find.byKey(const Key('sign-in-submit'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('auth-theme-toggle'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Android back during edge scrolling keeps the draft and disposes safely',
    (tester) async {
      await pumpAuth(tester, size: const Size(390, 800));
      await openSignup(tester);
      await tester.enterText(
        find.byKey(const Key('signup-owner-name')),
        'اسم قيد الكتابة',
      );
      await tester.fling(
        find.byKey(const Key('auth-scroll')),
        const Offset(0, 800),
        4000,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
      await tester.pumpAndSettle();
      await openSignup(tester);
      expect(
        controllerText(tester, const Key('signup-owner-name')),
        'اسم قيد الكتابة',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 800));
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets('320 login keeps compact branding and both actions on screen', (
    tester,
  ) async {
    await pumpAuth(tester, size: const Size(320, 640));
    expect(find.byKey(const Key('brand-mark')).hitTestable(), findsOneWidget);
    expect(find.text(ShellCopy.appTitle).hitTestable(), findsOneWidget);
    expect(find.text(ShellCopy.brandTagline).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('sign-in-submit')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('show-signup')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native splash hands off directly to the login form', (
    tester,
  ) async {
    final auth = ScriptedAuth();
    addTearDown(auth.close);
    await tester.pumpWidget(
      ElDafttarApp(
        supabaseStatus: SupabaseStartupStatus.ready,
        themeController: ThemeController(
          store: MemoryThemePreferenceStore(),
          initial: ThemeMode.light,
        ),
        authGateway: auth,
        shopAccountGateway: ScriptedShops(),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('brand-splash')), findsNothing);
    expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
  });

  testWidgets('entry guide uses real fields, can skip and reopen from Help', (
    tester,
  ) async {
    final onboarding = MemoryOnboardingStore();
    final auth = await pumpAuth(tester, onboardingStore: onboarding);
    expect(find.byKey(const Key('onboarding-guide')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-action')));
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('sign-in-identifier')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(find.text('أدخل كلمة المرور'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pump();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    expect(onboarding.completed, isNot(contains('auth_signin')));
    expect(onboarding.steps['auth_signin'], 1);
    await tester.tap(find.byKey(const Key('auth-help')));
    await tester.pump();
    expect(find.byKey(const Key('onboarding-guide')), findsOneWidget);
    expect(find.text('أدخل كلمة المرور'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-action')));
    await tester.pump();
    expect(find.text('راجع ثم ادخل'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-action')));
    await tester.pump();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    expect(onboarding.completed, contains('auth_signin'));
    expect(auth.signIns, isEmpty, reason: 'Guidance never submits credentials');
  });

  testWidgets('screen reader hears the detected contact and the password', (
    tester,
  ) async {
    await pumpAuth(tester);
    final semantics = tester.ensureSemantics();
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      '01012345678',
    );
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const Key('sign-in-identifier')))
          .getSemanticsData()
          .label,
      contains(AuthCopy.phoneLabel),
    );
    expect(find.text(AuthCopy.detectedPhone), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('sign-in-password')))
          .getSemanticsData()
          .label,
      contains(AuthCopy.passwordLabel),
    );
    semantics.dispose();
  });

  testWidgets('system back returns from registration and preserves the draft', (
    tester,
  ) async {
    await pumpAuth(tester);
    await openSignup(tester);
    await tester.enterText(
      find.byKey(const Key('signup-owner-name')),
      'اسم قيد الكتابة',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
    await openSignup(tester);
    expect(
      controllerText(tester, const Key('signup-owner-name')),
      'اسم قيد الكتابة',
    );
  });
}

String controllerText(WidgetTester tester, Key key) {
  return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
}

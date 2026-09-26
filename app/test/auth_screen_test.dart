import 'dart:async';

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
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

class ScriptedAuth implements AuthGateway {
  AuthStatus current = AuthStatus.signedOut;
  final controller = StreamController<AuthStatus>.broadcast();
  final registrations = <OwnerRegistration>[];
  Completer<OwnerRegistrationResult>? registration;
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
  Size size = const Size(420, 1200),
  ThemeMode mode = ThemeMode.light,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gateway = auth ?? ScriptedAuth();
  addTearDown(gateway.close);
  await tester.pumpWidget(
    ElDafttarApp(
      supabaseStatus: SupabaseStartupStatus.ready,
      themeController: ThemeController(store: store, initial: mode),
      authGateway: gateway,
      shopAccountGateway: shops ?? ScriptedShops(),
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
  return tester
      .widget<TextField>(
        find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
      )
      .textDirection;
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
    expect(find.text(AuthCopy.emailInvalid), findsOneWidget);
    expect(find.text(AuthCopy.phoneInvalid), findsOneWidget);
    expect(find.text(AuthCopy.governorateInvalid), findsOneWidget);
    expect(find.text(AuthCopy.passwordInvalid), findsOneWidget);
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
        fieldDirection(tester, const Key('sign-in-email')),
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
}

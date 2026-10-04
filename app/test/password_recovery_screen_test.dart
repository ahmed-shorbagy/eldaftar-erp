import 'dart:async';

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/domain/password_recovery.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
import 'package:eldafttar/src/features/auth/presentation/password_recovery_screen.dart';
import 'package:eldafttar/src/features/auth/presentation/recovery_copy.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThemeStore implements ThemePreferenceStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _Auth implements AuthGateway {
  AuthStatus current = AuthStatus.signedOut;
  final controller = StreamController<AuthStatus>.broadcast();
  final signIns = <SignInRequest>[];

  @override
  AuthStatus get status => current;

  @override
  Stream<AuthStatus> get changes => controller.stream;

  @override
  Future<void> signIn(SignInRequest request) async {
    signIns.add(request);
    current = AuthStatus.signedIn;
    controller.add(current);
  }

  @override
  Future<void> signOut() async {
    current = AuthStatus.signedOut;
    controller.add(current);
  }

  @override
  Future<List<Governorate>> loadGovernorates() async => const [
    Governorate(code: 'EG-GZ', nameAr: 'الجيزة'),
  ];

  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) async {
    return const OwnerRegistrationResult(
      userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      shopId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
  }
}

class _Shops implements ShopAccountGateway {
  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => const [
    ShopAccount(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'ذهب الجيزة السري',
      role: 'owner',
      entitlement: ShopEntitlement.pending,
    ),
  ];
}

class _Recovery implements PasswordRecoveryGateway {
  bool pending = false;
  final events = StreamController<bool>.broadcast();
  RecoveryFailure? failure;
  RecoveryFailure? link;
  Completer<void>? gate;
  int requests = 0;
  int resets = 0;
  bool interrupt = false;

  @override
  bool get recoveryPending => pending;

  @override
  Stream<bool> get recoveryChanges => events.stream;

  @override
  RecoveryFailure? get linkFailure => link;

  @override
  Future<void> requestEmailReset(String email) async {
    if (AccountEmail.tryCanonical(email) == null) {
      throw const RecoveryException(RecoveryFailure.invalidEmail);
    }
    requests++;
    final wait = gate;
    if (wait != null) await wait.future;
    final error = failure;
    if (error != null) throw RecoveryException(error);
  }

  @override
  Future<void> completeReset(String password) async {
    resets++;
    final wait = gate;
    if (wait != null) await wait.future;
    if (interrupt) {
      throw const RecoveryException(RecoveryFailure.resetInterrupted);
    }
    final error = failure;
    if (error != null) throw RecoveryException(error);
    pending = false;
    events.add(false);
  }

  @override
  Future<void> abandonRecovery() async {
    pending = false;
    events.add(false);
  }

  @override
  Future<void> acceptCallback(Uri uri) async {}

  @override
  void clearLinkFailure() => link = null;
}

Future<_Recovery> _pumpRecovery(
  WidgetTester tester, {
  _Auth? auth,
  _Recovery? recovery,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gateway = recovery ?? _Recovery();
  addTearDown(gateway.events.close);
  final signIn = auth ?? _Auth();
  addTearDown(signIn.controller.close);
  await tester.pumpWidget(
    ElDafttarApp(
      supabaseStatus: SupabaseStartupStatus.ready,
      themeController: ThemeController(store: _ThemeStore()),
      authGateway: signIn,
      recoveryGateway: gateway,
      shopAccountGateway: _Shops(),
    ),
  );
  await tester.pump();
  return gateway;
}

void main() {
  testWidgets('recovery inputs have Arabic accessible labels', (tester) async {
    final semantics = tester.ensureSemantics();
    final recovery = await _pumpRecovery(tester);
    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pump();
    void expectNamedInput(String key, String label) {
      final node = tester.getSemantics(find.byKey(Key(key)));
      expect(node, containsSemantics(isTextField: true));
      expect(node.getSemanticsData().label.split('\n').first, label);
    }

    expectNamedInput('recovery-email', AuthCopy.emailLabel);

    recovery.pending = true;
    recovery.events.add(true);
    await tester.pump();
    await tester.pump();
    expectNamedInput('recovery-new-password', AuthCopy.passwordLabel);
    expectNamedInput('recovery-confirm-password', RecoveryCopy.confirmLabel);
    semantics.dispose();
  });

  testWidgets('login stays available and recovery is a separate route', (
    tester,
  ) async {
    final recovery = await _pumpRecovery(tester);
    expect(find.byKey(const Key('forgot-password')), findsOneWidget);
    expect(find.text(RecoveryCopy.forgotPassword), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('sign-in-submit')));
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'example-password',
    );
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ShopAccountsGate), findsOneWidget);
    expect(find.text('ذهب الجيزة السري'), findsOneWidget);

    await _pumpRecovery(tester, recovery: recovery);
    await tester.tap(find.byKey(const Key('show-signup')));
    await tester.pump();
    expect(find.byKey(const Key('forgot-password')), findsNothing);
    expect(find.byKey(const Key('signup-submit')), findsOneWidget);
  });

  testWidgets(
    'request disables duplicates and hides whether the account exists',
    (tester) async {
      final recovery = await _pumpRecovery(tester, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('recovery-email')), 'bad');
      await tester.tap(find.byKey(const Key('recovery-request-submit')));
      await tester.pump();
      expect(find.text(RecoveryCopy.emailInvalid), findsWidgets);
      expect(recovery.requests, 0);

      recovery.gate = Completer<void>();
      await tester.enterText(
        find.byKey(const Key('recovery-email')),
        'Owner@Example.TEST',
      );
      await tester.tap(find.byKey(const Key('recovery-request-submit')));
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('recovery-request-submit')),
      );
      expect(button.onPressed, isNull);
      expect(
        tester.getSize(find.byKey(const Key('recovery-request-submit'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const Key('recovery-request-submit')));
      await tester.pump();
      expect(recovery.requests, 1);
      recovery.gate!.complete();
      recovery.gate = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(RecoveryCopy.requestSuccess), findsOneWidget);
      expect(find.textContaining('غير موجود'), findsNothing);

      recovery.failure = RecoveryFailure.unavailable;
      await tester.tap(find.byKey(const Key('recovery-back')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('recovery-email')),
        'owner@example.test',
      );
      await tester.tap(find.byKey(const Key('recovery-request-submit')));
      await tester.pump();
      expect(find.text(RecoveryCopy.requestUnavailable), findsOneWidget);
    },
  );

  testWidgets('reset blocks shop data, accepts paste, and survives a retry', (
    tester,
  ) async {
    final auth = _Auth()..current = AuthStatus.signedIn;
    final recovery = _Recovery()..pending = true;
    await _pumpRecovery(tester, auth: auth, recovery: recovery);
    expect(find.byType(ShopAccountsGate), findsNothing);
    expect(find.text('ذهب الجيزة السري'), findsNothing);
    expect(find.byKey(const Key('recovery-new-password')), findsOneWidget);

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('recovery-new-password')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.enableInteractiveSelection, isTrue);
    expect(field.autofillHints, contains(AutofillHints.newPassword));
    await tester.enterText(
      find.byKey(const Key('recovery-new-password')),
      'example-password',
    );
    await tester.enterText(
      find.byKey(const Key('recovery-confirm-password')),
      'other-password',
    );
    await tester.tap(find.byKey(const Key('recovery-reset-submit')));
    await tester.pump();
    expect(find.text(RecoveryCopy.mismatch), findsOneWidget);
    expect(recovery.resets, 0);

    recovery.gate = Completer<void>();
    await tester.enterText(
      find.byKey(const Key('recovery-confirm-password')),
      'example-password',
    );
    await tester.tap(find.byKey(const Key('recovery-reset-submit')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('recovery-reset-submit')))
          .onPressed,
      isNull,
    );
    expect(
      tester.getSize(find.byKey(const Key('recovery-reset-submit'))).height,
      greaterThanOrEqualTo(48),
    );
    recovery.interrupt = true;
    recovery.gate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(RecoveryCopy.resetInterrupted), findsOneWidget);
    expect(find.byType(ShopAccountsGate), findsNothing);

    recovery.interrupt = false;
    recovery.gate = null;
    await tester.tap(find.byKey(const Key('recovery-reset-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(RecoveryCopy.resetSuccess), findsOneWidget);
    expect(find.byType(ShopAccountsGate), findsNothing);
    expect(find.byKey(const Key('sign-in-submit')), findsOneWidget);
  });

  testWidgets(
    'an invalid link and abandoning reset stay on the sign-in screen',
    (tester) async {
      final recovery = _Recovery()..link = RecoveryFailure.expiredOrInvalidLink;
      await _pumpRecovery(tester, recovery: recovery);
      expect(find.text(RecoveryCopy.resetExpired), findsOneWidget);
      expect(find.byType(ShopAccountsGate), findsNothing);

      recovery.pending = true;
      recovery.events.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(PasswordResetScreen), findsOneWidget);
      expect(find.byType(ShopAccountsGate), findsNothing);
      expect(find.text('ذهب الجيزة السري'), findsNothing);
      await tester.tap(find.byKey(const Key('recovery-abandon')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
      expect(recovery.pending, isFalse);
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/domain/password_recovery.dart';
import 'package:eldafttar/src/features/auth/presentation/recovery_copy.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic widget renders. These are not device or hosted recovery proof.
const _sizes = <Size>[Size(320, 640), Size(1440, 900)];

class _ThemeStore implements ThemePreferenceStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _Auth implements AuthGateway {
  final controller = StreamController<AuthStatus>.broadcast();

  @override
  AuthStatus get status => AuthStatus.signedOut;

  @override
  Stream<AuthStatus> get changes => controller.stream;

  @override
  Future<void> signIn(SignInRequest request) async {}

  @override
  Future<void> signOut() async {}

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
  Future<List<ShopAccount>> listMyShopAccounts() async => const [];
}

class _Recovery implements PasswordRecoveryGateway {
  _Recovery({
    this.pending = false,
    this.link,
    this.requestError,
    this.resetError,
  });

  bool pending;
  RecoveryFailure? link;
  RecoveryFailure? requestError;
  RecoveryFailure? resetError;
  final events = StreamController<bool>.broadcast();

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
    final error = requestError;
    if (error != null) throw RecoveryException(error);
  }

  @override
  Future<void> completeReset(String password) async {
    final error = resetError;
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

String get _captureDir {
  final override = Platform.environment['ELDAFTTAR_CAPTURE_DIR']?.trim();
  final dir = (override == null || override.isEmpty)
      ? 'build/recovery-review'
      : override;
  final normalized = dir.replaceAll('\\', '/').toLowerCase();
  if (normalized == 'docs' ||
      normalized.startsWith('docs/') ||
      normalized.contains('/docs/') ||
      normalized.contains('auth-review')) {
    throw StateError(
      'Recovery captures write only under build/recovery-review.',
    );
  }
  return dir;
}

Future<void> _capture(WidgetTester tester, String name, String boundary) async {
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  final object = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(Key(boundary)),
  );
  await tester.runAsync(() async {
    final image = await object.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    expect(bytes.length, greaterThan(8), reason: name);
    final file = File('$_captureDir/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
    image.dispose();
  });
}

Future<_Recovery> _pump(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  bool pending = false,
  RecoveryFailure? link,
  RecoveryFailure? requestError,
  RecoveryFailure? resetError,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final recovery = _Recovery(
    pending: pending,
    link: link,
    requestError: requestError,
    resetError: resetError,
  );
  final auth = _Auth();
  final theme = ThemeController(
    store: _ThemeStore(),
    initial: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  );
  addTearDown(recovery.events.close);
  addTearDown(auth.controller.close);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ElDafttarApp(
      supabaseStatus: SupabaseStartupStatus.ready,
      themeController: theme,
      authGateway: auth,
      recoveryGateway: recovery,
      shopAccountGateway: _Shops(),
    ),
  );
  await tester.pump();
  return recovery;
}

String _label(Size size, Brightness brightness) {
  final mode = brightness == Brightness.dark ? 'dark' : 'light';
  return '${size.width.toInt()}-$mode';
}

Future<void> _openRequest(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('forgot-password')));
  await tester.tap(find.byKey(const Key('forgot-password')));
  await tester.pump();
  expect(find.byKey(const Key('recovery-email')), findsOneWidget);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final arabic = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await arabic.load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final iconBytes = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
  });

  for (final size in _sizes) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = _label(size, brightness);

      testWidgets('captures the recovery request form $label', (tester) async {
        await _pump(tester, size: size, brightness: brightness);
        await _openRequest(tester);
        await _capture(
          tester,
          'recovery-request-$label.png',
          'recovery-capture-boundary',
        );
      });

      testWidgets('captures recovery request success $label', (tester) async {
        await _pump(tester, size: size, brightness: brightness);
        await _openRequest(tester);
        await tester.enterText(
          find.byKey(const Key('recovery-email')),
          'owner@example.test',
        );
        await tester.ensureVisible(
          find.byKey(const Key('recovery-request-submit')),
        );
        await tester.tap(find.byKey(const Key('recovery-request-submit')));
        await tester.pump();
        await tester.pump();
        expect(find.text(RecoveryCopy.requestSuccess), findsOneWidget);
        expect(find.textContaining('غير موجود'), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('recovery-status')));
        await _capture(
          tester,
          'recovery-request-success-$label.png',
          'recovery-capture-boundary',
        );
      });

      testWidgets('captures recovery request failure $label', (tester) async {
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          requestError: RecoveryFailure.unavailable,
        );
        await _openRequest(tester);
        await tester.enterText(
          find.byKey(const Key('recovery-email')),
          'owner@example.test',
        );
        await tester.ensureVisible(
          find.byKey(const Key('recovery-request-submit')),
        );
        await tester.tap(find.byKey(const Key('recovery-request-submit')));
        await tester.pump();
        await tester.pump();
        expect(find.text(RecoveryCopy.requestUnavailable), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('recovery-status')));
        await _capture(
          tester,
          'recovery-request-failure-$label.png',
          'recovery-capture-boundary',
        );
      });

      testWidgets('captures the password reset form $label', (tester) async {
        await _pump(tester, size: size, brightness: brightness, pending: true);
        expect(find.byKey(const Key('recovery-new-password')), findsOneWidget);
        await _capture(
          tester,
          'recovery-reset-$label.png',
          'recovery-capture-boundary',
        );
      });

      testWidgets('captures a rejected recovery password $label', (
        tester,
      ) async {
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          pending: true,
          resetError: RecoveryFailure.rejectedPassword,
        );
        await tester.enterText(
          find.byKey(const Key('recovery-new-password')),
          'example-password',
        );
        await tester.enterText(
          find.byKey(const Key('recovery-confirm-password')),
          'example-password',
        );
        await tester.ensureVisible(
          find.byKey(const Key('recovery-reset-submit')),
        );
        await tester.tap(find.byKey(const Key('recovery-reset-submit')));
        await tester.pump();
        await tester.pump();
        expect(find.text(RecoveryCopy.resetRejected), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('recovery-status')));
        await _capture(
          tester,
          'recovery-reset-error-$label.png',
          'recovery-capture-boundary',
        );
      });

      testWidgets('captures an invalid recovery link on sign-in $label', (
        tester,
      ) async {
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          link: RecoveryFailure.expiredOrInvalidLink,
        );
        expect(find.text(RecoveryCopy.resetExpired), findsOneWidget);
        expect(find.byKey(const Key('recovery-new-password')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('auth-recovery-notice')),
        );
        await _capture(
          tester,
          'recovery-invalid-link-$label.png',
          'auth-capture-boundary',
        );
      });
    }
  }
}

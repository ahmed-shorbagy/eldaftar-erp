import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_gate.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

bool tahomaReady = false;

class CaptureAuth implements AuthGateway {
  @override
  AuthStatus get status => AuthStatus.signedOut;

  @override
  Stream<AuthStatus> get changes => const Stream.empty();

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
  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => const [];
}

ThemeData withTahoma(ThemeData theme) {
  if (!tahomaReady) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Tahoma'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Tahoma'),
  );
}

Future<void> reveal(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  for (var attempt = 0; attempt < 8 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(
      find.byKey(const Key('auth-scroll')),
      const Offset(0, -320),
    );
    await tester.pump();
  }
  await tester.ensureVisible(finder);
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> capture(WidgetTester tester, String name) async {
  await frames(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('auth-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/auth-review/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final file = File(r'C:\Windows\Fonts\tahoma.ttf');
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader('Tahoma')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    final icons = File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );
    final iconBytes = await icons.readAsBytes();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
    await iconLoader.load();
    tahomaReady = true;
  });

  testWidgets('captures login and signup in light and dark at 320 and 1440', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(
      tahomaReady,
      isTrue,
      reason: 'Tahoma should be available on Windows',
    );

    for (final size in const [Size(320, 640), Size(1440, 900)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final label = '${brightness.name}-${size.width.toInt()}';
        await _pump(tester, size: size, brightness: brightness);
        await tester.enterText(
          find.byKey(const Key('sign-in-email')),
          'owner@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('sign-in-password')),
          'example-password',
        );
        await capture(tester, 'login-email-$label.png');

        await reveal(tester, const Key('sign-in-kind-phone'));
        await tester.tap(find.byKey(const Key('sign-in-kind-phone')));
        await frames(tester);
        await tester.enterText(
          find.byKey(const Key('sign-in-phone')),
          '01012345678',
        );
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
        final list = tester.widget<ListView>(
          find.byKey(const Key('auth-scroll')),
        );
        list.controller!.jumpTo(0);
        await frames(tester);
        expect(tester.takeException(), isNull);
        await capture(tester, 'signup-top-$label.png');
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await frames(tester);
        expect(tester.takeException(), isNull);
        await capture(tester, 'signup-lower-$label.png');
      }
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
}) async {
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
      theme: withTahoma(AppTheme.light()),
      darkTheme: withTahoma(AppTheme.dark()),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: AuthGate(
        supabaseStatus: SupabaseStartupStatus.ready,
        authGateway: CaptureAuth(),
        shopAccountGateway: CaptureShops(),
        onToggleTheme: (_) async {},
      ),
    ),
  );
  await frames(tester);
}

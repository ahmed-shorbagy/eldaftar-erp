// Local device review harness. Production lib/main.dart must not import this
// library. It talks only to an in-memory gateway and uses synthetic values.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_screen.dart';
import 'package:eldafttar/src/shell/shell_copy.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reviews the Arabic auth screen with a fake gateway', (
    tester,
  ) async {
    await tester.pumpWidget(const AuthReviewHost());
    await tester.pumpAndSettle();

    expect(find.text(AuthCopy.signInTitle), findsOneWidget);
    expect(find.byKey(const Key('sign-in-identifier')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      'owner@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'example-password',
    );
    await tester.pumpAndSettle();
    await shot(tester, 'login-email-light');
    await tester.enterText(
      find.byKey(const Key('sign-in-identifier')),
      '01012345678',
    );
    await tester.pumpAndSettle();
    await shot(tester, 'login-phone-light');

    await tester.tap(find.byTooltip(ShellCopy.toggleToDark));
    await tester.pumpAndSettle();
    await shot(tester, 'login-phone-dark');

    await tester.ensureVisible(find.byKey(const Key('show-signup')));
    await tester.tap(find.byKey(const Key('show-signup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('signup-owner-name')),
      'منى حسن',
    );
    await tester.enterText(
      find.byKey(const Key('signup-business-name')),
      'ذهب الجيزة',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    tester
        .widget<SingleChildScrollView>(find.byKey(const Key('auth-scroll')))
        .controller!
        .jumpTo(0);
    await tester.pumpAndSettle();
    await shot(tester, 'signup-top-dark');

    await tester.ensureVisible(find.byKey(const Key('signup-submit')));
    await tester.pumpAndSettle();
    await shot(tester, 'signup-lower-dark');

    expect(find.textContaining('تم إنشاء'), findsNothing);
    expect(find.textContaining('تم حفظ'), findsNothing);
  });
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  try {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('auth-capture-boundary')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/auth-$name.png');
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    image.dispose();
    // ignore: avoid_print
    print('AUTH_REVIEW_SHOT ${file.path}');
  } catch (error) {
    // ignore: avoid_print
    print('AUTH_REVIEW_SHOT_FAILED $name $error');
  }
}

class AuthReviewHost extends StatefulWidget {
  const AuthReviewHost({super.key, this.preview = false});
  final bool preview;

  @override
  State<AuthReviewHost> createState() => _AuthReviewHostState();
}

class _AuthReviewHostState extends State<AuthReviewHost> {
  ThemeMode _mode = ThemeMode.light;
  final _gateway = _ReviewAuthGateway();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: widget.preview
          ? (context, child) {
              final scheme = Theme.of(context).colorScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: scheme.primaryContainer,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'معاينة تجريبية — بيانات غير حقيقية',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: child!),
                ],
              );
            }
          : null,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: AuthScreen(
        gateway: _gateway,
        onToggleTheme: (brightness) async {
          setState(() {
            _mode = brightness == Brightness.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          });
        },
        onHold: (_) {},
        onSessionSettled: () {},
      ),
    );
  }
}

class _ReviewAuthGateway implements AuthGateway {
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

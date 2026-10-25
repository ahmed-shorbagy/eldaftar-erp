import 'package:eldafttar/src/features/app_version/application/app_version_evaluator.dart';
import 'package:eldafttar/src/features/app_version/domain/app_version_gateway.dart';
import 'package:eldafttar/src/features/app_version/domain/app_version_policy.dart';
import 'package:eldafttar/src/features/app_version/presentation/app_version_gate.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePolicyGateway implements AppVersionGateway {
  FakePolicyGateway(this.snapshot, {this.fail = false});

  AppVersionSnapshot snapshot;
  bool fail;
  int calls = 0;

  @override
  Future<AppVersionSnapshot> getPolicy() async {
    calls++;
    if (fail) {
      throw const AppVersionException(AppVersionFailure.unavailable);
    }
    return snapshot;
  }
}

Future<void> pumpGate(
  WidgetTester tester, {
  required AppVersionGateway gateway,
  String version = '1.0.0',
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: AppVersionGate(
        gateway: gateway,
        currentVersion: version,
        platform: AppVersionPlatform.android,
        child: const Scaffold(
          body: Text('داخل التطبيق', key: Key('app-inside')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('compareAppVersions orders semantic triples', () {
    expect(compareAppVersions('1.0.0', '1.0.1'), -1);
    expect(compareAppVersions('1.0.1', '1.0.1'), 0);
    expect(compareAppVersions('2.0.0', '1.9.9'), 1);
  });

  test('evaluateAppVersionBlock blocks only when below minimum', () {
    const snapshot = AppVersionSnapshot(
      platforms: [
        AppVersionPlatformPolicy(
          platform: AppVersionPlatform.android,
          minVersion: '1.2.0',
          messageAr: 'يلزم التحديث',
          updateUrl: 'https://example.test/app',
        ),
      ],
    );
    expect(
      evaluateAppVersionBlock(
        snapshot: snapshot,
        currentVersion: '1.2.0',
        platform: AppVersionPlatform.android,
      ),
      isNull,
    );
    final block = evaluateAppVersionBlock(
      snapshot: snapshot,
      currentVersion: '1.1.9',
      platform: AppVersionPlatform.android,
    );
    expect(block?.requiredVersion, '1.2.0');
    expect(block?.updateUrl, 'https://example.test/app');
  });

  testWidgets('below-min version shows blocker and hides the app', (
    tester,
  ) async {
    final gateway = FakePolicyGateway(
      const AppVersionSnapshot(
        platforms: [
          AppVersionPlatformPolicy(
            platform: AppVersionPlatform.android,
            minVersion: '2.0.0',
            messageAr: 'حدّث التطبيق الآن',
            updateUrl: 'https://example.test/update',
          ),
        ],
      ),
    );
    await pumpGate(tester, gateway: gateway, version: '1.0.0');
    expect(find.byKey(const Key('forced-update-title')), findsOneWidget);
    expect(find.text('حدّث التطبيق الآن'), findsOneWidget);
    expect(find.byKey(const Key('forced-update-open')), findsOneWidget);
    expect(find.byKey(const Key('app-inside')), findsNothing);
  });

  testWidgets('equal version opens the app', (tester) async {
    final gateway = FakePolicyGateway(
      const AppVersionSnapshot(
        platforms: [
          AppVersionPlatformPolicy(
            platform: AppVersionPlatform.android,
            minVersion: '1.0.0',
            messageAr: 'يلزم التحديث',
          ),
        ],
      ),
    );
    await pumpGate(tester, gateway: gateway, version: '1.0.0');
    expect(find.byKey(const Key('app-inside')), findsOneWidget);
    expect(find.byKey(const Key('forced-update-title')), findsNothing);
  });

  testWidgets('fetch failure without prior block shows retry banner', (
    tester,
  ) async {
    final gateway = FakePolicyGateway(
      const AppVersionSnapshot(platforms: []),
      fail: true,
    );
    await pumpGate(tester, gateway: gateway);
    expect(find.byKey(const Key('app-inside')), findsOneWidget);
    expect(find.byKey(const Key('app-version-fetch-banner')), findsOneWidget);
  });

  testWidgets('forced update fits phone and desktop in both themes', (
    tester,
  ) async {
    for (final size in [const Size(320, 640), const Size(1440, 900)]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final gateway = FakePolicyGateway(
          const AppVersionSnapshot(
            platforms: [
              AppVersionPlatformPolicy(
                platform: AppVersionPlatform.android,
                minVersion: '9.0.0',
                messageAr: 'يلزم التحديث',
              ),
            ],
          ),
        );
        await pumpGate(
          tester,
          gateway: gateway,
          size: size,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('forced-update-title')), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('forced-update-title'))),
          ),
          TextDirection.rtl,
        );
      }
    }
  });
}

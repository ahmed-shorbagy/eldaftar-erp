import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/shell/shell_copy.dart';
import 'package:eldafttar/src/theme/app_tokens.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

Future<ThemeController> pumpShell(
  WidgetTester tester, {
  required SupabaseStartupStatus status,
  ThemeMode initial = ThemeMode.system,
  MemoryThemePreferenceStore? store,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final themeStore = store ?? MemoryThemePreferenceStore();
  final controller = ThemeController(store: themeStore, initial: initial);
  await tester.pumpWidget(
    ElDafttarApp(supabaseStatus: status, themeController: controller),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('missing public config shows the Arabic setup message in RTL', (
    tester,
  ) async {
    await pumpShell(tester, status: SupabaseStartupStatus.missingConfiguration);

    expect(find.text(ShellCopy.appTitle), findsOneWidget);
    expect(find.text(ShellCopy.prototypeLabel), findsOneWidget);
    expect(find.text(ShellCopy.missingTitle), findsOneWidget);
    expect(find.text(ShellCopy.missingBody), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
    expect(find.text(ShellCopy.readyTitle), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('0'), findsNothing);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.locale, const Locale('ar'));
    expect(materialApp.theme?.useMaterial3, isTrue);
    expect(materialApp.darkTheme?.useMaterial3, isTrue);

    final context = tester.element(find.text(ShellCopy.missingTitle));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('ready and failed states stay labeled as a prototype', (
    tester,
  ) async {
    await pumpShell(tester, status: SupabaseStartupStatus.ready);
    expect(find.text(ShellCopy.prototypeLabel), findsOneWidget);
    expect(find.text(ShellCopy.readyTitle), findsOneWidget);
    expect(find.text(ShellCopy.readyBody), findsOneWidget);
    expect(find.textContaining('--dart-define'), findsNothing);

    await pumpShell(tester, status: SupabaseStartupStatus.failed);
    expect(find.text(ShellCopy.failedTitle), findsOneWidget);
    expect(find.text(ShellCopy.failedBody), findsOneWidget);
    expect(find.text(ShellCopy.missingTitle), findsNothing);
  });

  testWidgets('theme toggle switches light and dark and persists the choice', (
    tester,
  ) async {
    final store = MemoryThemePreferenceStore();
    await pumpShell(
      tester,
      status: SupabaseStartupStatus.missingConfiguration,
      store: store,
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.byTooltip(ShellCopy.toggleToDark));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(store.value, 'dark');
    expect(find.byTooltip(ShellCopy.toggleToLight), findsOneWidget);

    await tester.tap(find.byTooltip(ShellCopy.toggleToLight));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(store.value, 'light');
  });

  testWidgets('status text uses the theme on-surface color in both themes', (
    tester,
  ) async {
    await pumpShell(
      tester,
      status: SupabaseStartupStatus.missingConfiguration,
      initial: ThemeMode.light,
    );
    _expectReadableStatus(tester, AppTokens.lightOnSurface);

    await pumpShell(
      tester,
      status: SupabaseStartupStatus.missingConfiguration,
      initial: ThemeMode.dark,
    );
    _expectReadableStatus(tester, AppTokens.darkOnSurface);
  });

  testWidgets('shell lays out on a narrow phone and a wide desktop', (
    tester,
  ) async {
    for (final size in const [Size(320, 640), Size(1440, 900)]) {
      await pumpShell(
        tester,
        status: SupabaseStartupStatus.missingConfiguration,
        size: size,
        textScale: 1.4,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(ShellCopy.missingTitle), findsOneWidget);
      expect(find.text(ShellCopy.prototypeBody), findsOneWidget);
    }
  });
}

void _expectReadableStatus(WidgetTester tester, Color onSurface) {
  final title = tester.widget<Text>(find.text(ShellCopy.missingTitle));
  final body = tester.widget<Text>(find.text(ShellCopy.missingBody));
  final prototype = tester.widget<Text>(find.text(ShellCopy.prototypeBody));
  final context = tester.element(find.text(ShellCopy.missingTitle));
  final scheme = Theme.of(context).colorScheme;

  expect(title.style?.color, onSurface);
  expect(body.style?.color, onSurface);
  expect(prototype.style?.color, scheme.onPrimaryContainer);
  expect(Theme.of(context).colorScheme.onSurface, onSurface);
}

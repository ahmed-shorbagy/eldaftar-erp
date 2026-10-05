// Device-only visual review. All data and gateway calls are synthetic.
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/shell/shell_copy.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/owner_feedback_ledger_review_test.dart' show ReviewGateway;
import '../test/daily_ledger_widget_test.dart' show MemoryStore;

const _capture = Key('native-ledger-review');
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native ledger, floating actions and item selection in Arabic', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-quick-actions')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    await _shot(tester, 'ledger-dark');
    await tester.tap(find.byKey(const Key('ledger-quick-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-new-sale')), findsOneWidget);
    await _shot(tester, 'quick-actions-dark');
    Navigator.of(
      tester.element(find.byKey(const Key('ledger-new-sale'))),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(ShellCopy.toggleToLight));
    await tester.pumpAndSettle();
    await _shot(tester, 'ledger-light');
    await tester.tap(find.byKey(const Key('ledger-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger-new-sale')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-select-غويشة')), findsOneWidget);
    expect(find.byKey(const Key('trade-select-name')), findsNothing);
    await _shot(tester, 'sale-categories-light');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  // The device runner removes its app; export synthetic review pixels first.
  // ignore: avoid_print
  print(
    'LEDGER_REVIEW_BASE64 $name ${base64Encode(data!.buffer.asUint8List())}',
  );
}

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  ThemeMode _mode = ThemeMode.dark;
  final _gateway = ReviewGateway();
  final _store = MemoryStore();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: _mode,
    builder: (context, child) => RepaintBoundary(key: _capture, child: child!),
    home: ShopWorkspace(
      shop: const ShopAccount(
        id: 'shop-1',
        name: 'محل تجريبي',
        role: 'owner',
        entitlement: ShopEntitlement.active,
      ),
      gateway: _gateway,
      store: _store,
      userId: 'owner-1',
      onSignOut: () async {},
      onToggleTheme: (brightness) async => setState(
        () => _mode = brightness == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark,
      ),
    ),
  );
}

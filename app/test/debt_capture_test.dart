import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'debt_widget_test.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

/// Flutter tests run with app/ as the working directory.
const _out = 'build/debts';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

Widget _host({
  required Widget child,
  required Brightness brightness,
  required GlobalKey capture,
  double textScale = 1,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child ?? const SizedBox.shrink(),
    ),
    home: RepaintBoundary(key: capture, child: child),
  );
}

Future<void> _openSized(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

DebtScreen _screen({
  required DebtGateway gateway,
  required MemoryLocker store,
  bool readOnly = false,
  String Function()? newKey,
}) {
  return DebtScreen(
    gateway: gateway,
    store: store,
    userId: userId,
    shopId: shopId,
    readOnly: readOnly,
    newKey: newKey,
  );
}

Future<void> _fillDeclare(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('debt-party')), 'طرف جديد');
  await tester.enterText(find.byKey(const Key('debt-reason')), 'سبب تاريخي');
  await tester.enterText(find.byKey(const Key('debt-amount')), '10.50');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      final suffix = '${width.toInt()}-${brightness.name}';

      testWidgets('debt list detail and settlement review $suffix', (
        tester,
      ) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(gateway: FakeDebts(), store: MemoryLocker()),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('طرف تاريخي'), findsOneWidget);
        await _capture(tester, capture, 'list-$suffix');
        await tester.tap(find.byKey(Key('debt-item-$sourceId')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-remaining')), findsOneWidget);
        await _capture(tester, capture, 'detail-$suffix');
        await tester.ensureVisible(find.byKey(const Key('debt-settle')));
        await tester.tap(find.byKey(const Key('debt-settle')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('يحرك النقد أو الذهب'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('بلا قيد').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('debt-settle-amount')),
          '5',
        );
        await tester.enterText(
          find.byKey(const Key('debt-settle-reason')),
          'تسوية بلا حركة',
        );
        await tester.ensureVisible(find.byKey(const Key('debt-submit')));
        await tester.tap(find.byKey(const Key('debt-submit')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-review')), findsOneWidget);
        expect(find.textContaining('سداد بلا قيد'), findsOneWidget);
        await _capture(tester, capture, 'review-$suffix');
      });

      testWidgets('debt form $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(gateway: FakeDebts(), store: MemoryLocker()),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('debt-open-declare')));
        await tester.pumpAndSettle();
        await _fillDeclare(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-party')), findsOneWidget);
        await _capture(tester, capture, 'form-$suffix');
      });

      testWidgets('debt pending $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(
              gateway: FakeDebts(),
              store: MemoryLocker()
                ..stored = PendingFinancialCommand(
                  key: key,
                  kind: 'debt_declare',
                  body: {
                    'p_idempotency_key': key,
                    'p_payload': {
                      'version': 1,
                      'kind': 'debt_declare',
                      'direction': 'shop_owes',
                      'unit': 'money',
                      'karat': null,
                      'amount': '1050',
                      'party_name': 'طرف جديد',
                      'contact_phone': '',
                      'reason': 'سبب تاريخي',
                      'external_reference': null,
                    },
                  },
                ),
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-pending')), findsOneWidget);
        expect(find.byKey(const Key('debt-retry')), findsOneWidget);
        await _capture(tester, capture, 'pending-$suffix');
      });

      testWidgets('debt error $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(
              gateway: FakeDebts(failRead: true),
              store: MemoryLocker(),
              readOnly: true,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-error')), findsOneWidget);
        expect(find.byKey(const Key('debt-open-declare')), findsNothing);
        await _capture(tester, capture, 'error-$suffix');
      });

      testWidgets('debt success $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(
              gateway: FakeDebts(),
              store: MemoryLocker(),
              newKey: () => key,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('debt-open-declare')));
        await tester.pumpAndSettle();
        await _fillDeclare(tester);
        await tester.tap(find.byKey(const Key('debt-submit')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-review')), findsOneWidget);
        await tester.tap(find.byKey(const Key('debt-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('debt-success')), findsOneWidget);
        await _capture(tester, capture, 'success-$suffix');
      });

      testWidgets('debt keyboard $suffix', (tester) async {
        await _openSized(tester, width);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(gateway: FakeDebts(), store: MemoryLocker()),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('debt-open-declare')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('debt-party')), 'طرف جديد');
        await tester.ensureVisible(find.byKey(const Key('debt-submit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(tester, capture, 'keyboard-$suffix');
      });

      testWidgets('debt text scale $suffix', (tester) async {
        await _openSized(tester, width);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(
          () => tester.platformDispatcher.textScaleFactorTestValue = 1,
        );
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: _screen(gateway: FakeDebts(), store: MemoryLocker()),
            brightness: brightness,
            capture: capture,
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('طرف تاريخي'), findsOneWidget);
        expect(find.text('بحث'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, capture, 'text-scale-$suffix');
      });
    }
  }
}

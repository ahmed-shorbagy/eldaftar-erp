import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repair_widget_test.dart';
import 'repair_review_regression_test.dart' show MissingBackend;

/// Flutter tests run with app/ as the working directory.
const _out = 'build/repairs';

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
      testWidgets('repair unavailable $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: MissingBackend(),
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await _capture(tester, capture, 'unavailable-$suffix');
      });

      testWidgets('repair populated workflow $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        final gateway = FakeRepairs(summary: sample());
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: gateway,
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await _capture(tester, capture, 'list-$suffix');
        await tester.tap(find.text('عميل الإصلاح'));
        await tester.pumpAndSettle();
        await _capture(tester, capture, 'detail-$suffix');
        await tester.ensureVisible(
          find.byKey(const Key('repair-handover-open')),
        );
        await tester.tap(find.byKey(const Key('repair-handover-open')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('repair-handover-final')),
          '200',
        );
        await tester.tap(find.byKey(const Key('repair-collection-part')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('repair-collected')), '80');
        await tester.tap(find.byKey(const Key('repair-tender-method-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('نقدي').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('repair-tender-amount-0')),
          '80',
        );
        await _capture(tester, capture, 'paid-form-$suffix');
        await tester.ensureVisible(
          find.byKey(const Key('repair-handover-review')),
        );
        await tester.tap(find.byKey(const Key('repair-handover-review')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('repair-handover-summary')),
          findsOneWidget,
        );
        await _capture(tester, capture, 'partial-review-$suffix');
        await tester.tap(find.byTooltip('رجوع'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('repair-handover-open')),
        );
        await tester.tap(find.byKey(const Key('repair-handover-open')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('repair-handover-final')),
          '200',
        );
        await tester.tap(find.byKey(const Key('repair-collection-none')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repair-handover-review')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('repair-handover-summary')),
          findsOneWidget,
        );
        await _capture(tester, capture, 'unpaid-review-$suffix');
        await tester.tap(find.byTooltip('رجوع'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('repair-cancel')));
        await tester.tap(find.byKey(const Key('repair-cancel')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('repair-cancel-reason')),
          'إعادة القطعة للعميل',
        );
        await _capture(tester, capture, 'cancel-review-$suffix');
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              key: ValueKey('archived-$suffix'),
              gateway: FakeRepairs(summary: sample(status: 'delivered')),
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('عميل الإصلاح'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('repair-archive')));
        await tester.tap(find.byKey(const Key('repair-archive')));
        await tester.pumpAndSettle();
        await _capture(tester, capture, 'archive-review-$suffix');
      });

      testWidgets('repair review $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        final gateway = FakeRepairs();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: gateway,
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
              newKey: () => key,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repair-new')));
        await tester.pumpAndSettle();
        await _fillIntake(tester);
        await tester.tap(find.byKey(const Key('repair-intake-submit')));
        await tester.pumpAndSettle();
        expect(find.textContaining('1,255 ملليجرام'), findsOneWidget);
        await _capture(tester, capture, 'review-$suffix');
      });

      testWidgets('repair pending $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: FakeRepairs(summary: sample()),
              store: MemoryLocker()
                ..stored = PendingFinancialCommand(
                  key: key,
                  kind: 'repair_intake',
                  body: {
                    'p_idempotency_key': key,
                    'p_payload': {
                      'version': 1,
                      'kind': 'repair_intake',
                      'customer_name': 'عميل',
                      'customer_phone': '',
                      'item_description': 'خاتم',
                      'measured_milligrams': '1255',
                      'karat': 21,
                      'issue': 'مفصص',
                      'intake_notes': '',
                      'estimated_fee_piastres': null,
                    },
                  },
                ),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('repair-pending-retry')), findsOneWidget);
        await _capture(tester, capture, 'pending-$suffix');
      });

      testWidgets('repair success $suffix', (tester) async {
        await _openSized(tester, width);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: FakeRepairs(),
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
              newKey: () => key,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repair-new')));
        await tester.pumpAndSettle();
        await _fillIntake(tester);
        await tester.tap(find.byKey(const Key('repair-intake-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repair-intake-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('repair-success')), findsOneWidget);
        await _capture(tester, capture, 'success-$suffix');
      });

      testWidgets('repair keyboard $suffix', (tester) async {
        await _openSized(tester, width);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: FakeRepairs(),
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repair-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('repair-customer-name')),
          'عميل الإصلاح',
        );
        await tester.ensureVisible(
          find.byKey(const Key('repair-intake-submit')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(tester, capture, 'keyboard-$suffix');
      });

      testWidgets('repair text scale $suffix', (tester) async {
        await _openSized(tester, width);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(
          () => tester.platformDispatcher.textScaleFactorTestValue = 1,
        );
        final capture = GlobalKey();
        await tester.pumpWidget(
          _host(
            child: RepairScreen(
              gateway: FakeRepairs(summary: sample(status: 'delivered')),
              store: MemoryLocker(),
              userId: userId,
              shopId: shopId,
              readOnly: false,
            ),
            brightness: brightness,
            capture: capture,
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('عميل الإصلاح'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, capture, 'text-scale-$suffix');
      });
    }
  }
}

Future<void> _openSized(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _fillIntake(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('repair-customer-name')),
    'عميل الإصلاح',
  );
  await tester.enterText(find.byKey(const Key('repair-item')), 'خاتم');
  await tester.enterText(find.byKey(const Key('repair-grams')), '1.255');
  await tester.tap(find.byKey(const Key('repair-karat')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('21').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('repair-issue')), 'مفصص');
  await tester.enterText(find.byKey(const Key('repair-estimate')), '150');
}

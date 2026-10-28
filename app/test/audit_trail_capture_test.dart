import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/audit_trail/domain/audit_trail.dart';
import 'package:eldafttar/src/features/audit_trail/presentation/audit_trail_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audit_trail_screen_test.dart' show FakeAuditTrailGateway, entryOf;

final String captureDir =
    Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/audit-trail-review';

const reviewSizes = <(Size, String)>[
  (Size(320, 640), '320'),
  (Size(390, 844), '390'),
  (Size(1440, 900), '1440'),
];

Widget harness({
  required Brightness brightness,
  required Widget child,
  double textScale = 1,
}) => MaterialApp(
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
  home: RepaintBoundary(
    key: const Key('audit-capture-boundary'),
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ),
);

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('audit-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$captureDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('Arabic RTL audit screen stays readable in both themes', (
    tester,
  ) async {
    final gateway = FakeAuditTrailGateway(
      first: [
        entryOf('row-1', label: 'حذف عملية', family: AuditTrailFamily.delete),
        entryOf(
          'row-2',
          actor: null,
          label: 'خصم مخزون',
          family: AuditTrailFamily.deduction,
          sequence: '12',
        ),
        entryOf('row-3', label: 'تعديل عملية', family: AuditTrailFamily.change),
      ],
    );
    for (final brightness in Brightness.values) {
      for (final size in reviewSizes) {
        await tester.binding.setSurfaceSize(size.$1);
        await tester.pumpWidget(
          harness(
            brightness: brightness,
            child: AuditTrailScreen(gateway: gateway),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('سجل العمليات'), findsWidgets);
        expect(
          Directionality.of(tester.element(find.text('حذف عملية'))),
          TextDirection.rtl,
        );
        await capture(tester, 'audit-${brightness.name}-${size.$2}');
      }
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await tester.pumpWidget(
        harness(
          brightness: brightness,
          textScale: 1.7,
          child: AuditTrailScreen(gateway: gateway),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'audit-${brightness.name}-320-text17');
    }
    await tester.binding.setSurfaceSize(null);
  });
}

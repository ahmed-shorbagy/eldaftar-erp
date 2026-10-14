import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'customer_saved_number_test.dart';
import 'customer_saved_number_widget_test.dart';
import 'customer_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'repair_command_flow_test.dart' show MemoryLocker;

Future<void> savedCapture(
  WidgetTester t,
  GlobalKey key,
  String name, {
  bool settle = true,
}) async {
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(t.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await t.runAsync(() async {
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/customer-saved-number/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final sdk = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${brightness.name}-$scale';
        testWidgets('saved-number RTL states $suffix', (t) async {
          size(t, width: width);
          final key = GlobalKey();
          final g = SavedFake();
          final store = MemoryLocker();
          await t.pumpWidget(
            customerHost(
              RepaintBoundary(key: key, child: savedScreen(g, store)),
              brightness: brightness,
              scale: scale,
            ),
          );
          await savedCapture(t, key, 'list-unknown-$suffix');
          expect(
            Directionality.of(t.element(find.text('العملاء').first)),
            TextDirection.rtl,
          );
          await t.tap(find.byKey(const Key('customer-$customerId')));
          await t.pumpAndSettle();
          await showSavedControl(t);
          await t.drag(find.byType(ListView).last, const Offset(0, 300));
          await savedCapture(t, key, 'detail-unknown-$suffix');
          await showSavedControl(t);
          final scheme = Theme.of(
            t.element(find.byKey(const Key('saved-number-$numberId'))),
          ).colorScheme;
          final a = scheme.onSurface.computeLuminance(),
              b = scheme.surface.computeLuminance();
          expect(
            ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            t.getSize(find.byKey(const Key('saved-number-$numberId'))).height,
            greaterThanOrEqualTo(48),
          );
          final held = Completer<void>();
          g.readHold = held.future;
          await t.tap(find.byKey(const Key('saved-number-$numberId')));
          await savedCapture(t, key, 'preparing-$suffix', settle: false);
          held.complete();
          await t.pumpAndSettle();
          g.readHold = null;
          await savedCapture(t, key, 'choices-$suffix');
          expect(
            t.widget<Text>(find.text('+201011111111').first).textDirection,
            TextDirection.ltr,
          );
          await reviewSaved(t);
          await savedCapture(t, key, 'review-$suffix');
          g.rejected = 'stale_number';
          await t.tap(find.byKey(const Key('customer-confirm')));
          await t.pumpAndSettle();
          await savedCapture(t, key, 'failure-$suffix');
          await t.tap(find.byTooltip('رجوع'));
          await t.pumpAndSettle();
          await showSavedControl(t);
          await t.tap(find.byKey(const Key('saved-number-$numberId')));
          await t.pumpAndSettle();
          await reviewSaved(t);
          g.rejected = null;
          g.unknown = true;
          await t.tap(find.byKey(const Key('customer-confirm')));
          await t.pumpAndSettle();
          await savedCapture(t, key, 'pending-$suffix');
          g.unknown = false;
          await t.tap(find.byKey(const Key('customer-retry')));
          await t.pumpAndSettle();
          await savedCapture(t, key, 'confirmed-$suffix');
          await t.tap(find.text('عرض ملف العميل'));
          await t.pumpAndSettle();
          await showSavedControl(t);
          await t.drag(find.byType(ListView).last, const Offset(0, 300));
          await savedCapture(t, key, 'detail-saved-$suffix');
          await t.tap(find.byTooltip('رجوع'));
          await t.pumpAndSettle();
          await savedCapture(t, key, 'list-saved-$suffix');
          g.row['phones'] = savedPhones('not_saved');
          await t.tap(find.byKey(const Key('customer-$customerId')));
          await t.pumpAndSettle();
          await showSavedControl(t);
          await t.drag(find.byType(ListView).last, const Offset(0, 300));
          await savedCapture(t, key, 'detail-not-saved-$suffix');
          await t.tap(find.byTooltip('رجوع'));
          await t.pumpAndSettle();
          await savedCapture(t, key, 'list-not-saved-$suffix');
        });
      }
    }
  }
}

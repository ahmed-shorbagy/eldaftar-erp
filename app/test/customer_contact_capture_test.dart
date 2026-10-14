import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/domain/customer_contact.dart';
import 'customer_contact_test.dart';
import 'customer_contact_widget_test.dart';
import 'customer_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;

Future<void> contactCapture(
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
    final file = File('build/customer-contact/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cairo = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(cairo)))).load();
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
        testWidgets('contact RTL states $suffix', (t) async {
          size(t, width: width);
          final key = GlobalKey();
          final g = ContactFake()..row = customerJson(phones: contactPhones());
          final l = ContactLauncherFake();
          await t.pumpWidget(
            customerHost(
              RepaintBoundary(key: key, child: contactScreen(g, l)),
              brightness: brightness,
              scale: scale,
            ),
          );
          await contactCapture(t, key, 'list-$suffix');
          expect(
            Directionality.of(t.element(find.text('العملاء').first)),
            TextDirection.rtl,
          );
          await t.tap(find.byKey(const Key('customer-$customerId')));
          await contactCapture(t, key, 'detail-$suffix');
          await t.ensureVisible(find.text('واتساب'));
          await t.tap(find.text('واتساب'));
          await contactCapture(t, key, 'choice-$suffix');
          // Number controls remain independent 48px targets with Arabic primary semantics.
          final radio = find.byType(RadioListTile<String>).first;
          await t.ensureVisible(radio);
          await t.pumpAndSettle();
          expect(t.getSize(radio).height, greaterThanOrEqualTo(48));
          final texts = find.text('+201011111111');
          expect(t.widget<Text>(texts.first).textDirection, TextDirection.ltr);
          final scheme = Theme.of(t.element(radio)).colorScheme;
          double contrast(Color a, Color b) {
            final x = a.computeLuminance(), y = b.computeLuminance();
            return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
          }

          expect(
            contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          await t.ensureVisible(find.byKey(const Key('customer-contact-open')));
          final held = Completer<void>();
          l.hold = held.future;
          await t.tap(find.byKey(const Key('customer-contact-open')));
          await contactCapture(t, key, 'loading-$suffix', settle: false);
          held.complete();
          await t.pumpAndSettle();
          await contactCapture(t, key, 'opened-$suffix');
          l.hold = null;
          l.outcome = ContactHandoff.unavailable;
          await t.ensureVisible(find.byKey(const Key('customer-contact-open')));
          await t.tap(find.byKey(const Key('customer-contact-open')));
          await contactCapture(t, key, 'unavailable-$suffix');
          await t.ensureVisible(find.text('فتح رابط واتساب خارجيًا'));
          await contactCapture(t, key, 'fallback-$suffix');
          l.outcome = ContactHandoff.failed;
          await t.tap(find.text('فتح رابط واتساب خارجيًا'));
          await contactCapture(t, key, 'failure-$suffix');
          l.outcome = ContactHandoff.denied;
          await t.ensureVisible(find.byKey(const Key('customer-contact-open')));
          await t.tap(find.byKey(const Key('customer-contact-open')));
          await contactCapture(t, key, 'denied-$suffix');
          l.outcome = ContactHandoff.permanentlyDenied;
          await t.ensureVisible(find.byKey(const Key('customer-contact-open')));
          await t.tap(find.byKey(const Key('customer-contact-open')));
          await contactCapture(t, key, 'blocked-$suffix');
          expect(g.sent, isEmpty);
        });
      }
    }
  }
}

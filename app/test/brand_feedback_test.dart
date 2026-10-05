import 'dart:io';
import 'dart:ui' as ui;
import 'package:eldafttar/src/theme/brand_mark.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('ledger and diamond brand exports ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Center(
            child: RepaintBoundary(key: key, child: const BrandMark(size: 512)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('brand-mark')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['ELDAFTTAR_EXPORT_BRAND'] == '1') {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final png = await picture.toByteData(format: ui.ImageByteFormat.png);
          File(
            'assets/brand/native_splash${dark ? '_dark' : ''}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          picture.dispose();
          if (!dark) {
            final launcher = await boundary.toImage(pixelRatio: 2);
            final bytes = await launcher.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'assets/brand/launcher.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            launcher.dispose();
          }
        });
      }
    });
  }
}

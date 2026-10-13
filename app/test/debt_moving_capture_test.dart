import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'debt_settlement_regression_test.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      for (final mode in ['money', 'gold-in', 'gold-out']) {
        testWidgets('moving settlement $mode $width $theme', (tester) async {
          final capture = GlobalKey();
          await prepareSettlement(
            tester,
            SettlementGateway(mode),
            width: width,
            theme: theme,
            capture: capture,
          );
          expect(tester.takeException(), isNull);
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await boundary.toImage();
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/debts/moving-$mode-${width.toInt()}-${theme.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        });
      }
    }
  }
}

import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_app_bar.dart';
import 'package:eldafttar/src/theme/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ledger app bar shows shop image and falls back to BrandMark', (
    tester,
  ) async {
    Future<void> pump(Uint8List? bytes) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: LedgerAppBar(
              shopName: 'متجر الاختبار',
              shopImageBytes: bytes,
              topInset: 0,
            ),
          ),
        ),
      );
    }

    await pump(null);
    expect(find.byKey(const Key('workspace-menu')), findsNothing);
    expect(find.byKey(const Key('ledger-default-logo')), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byKey(const Key('ledger-shop-image')), findsNothing);
    expect(find.text('أهلاً متجر الاختبار'), findsOneWidget);

    final photo = img.Image(width: 32, height: 32);
    img.fill(photo, color: img.ColorRgba8(120, 80, 40, 255));
    final bytes = Uint8List.fromList(img.encodeJpg(photo, quality: 90));
    await pump(bytes);
    expect(find.byKey(const Key('ledger-shop-image')), findsOneWidget);
    expect(find.byType(BrandMark), findsNothing);

    await pump(Uint8List.fromList(const [1, 2, 3, 4]));
    await tester.pump();
    expect(find.byKey(const Key('ledger-default-logo')), findsOneWidget);
    expect(find.byKey(const Key('workspace-menu')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: LedgerAppBar(
            shopName: 'متجر الاختبار',
            topInset: 0,
            collapsed: true,
          ),
        ),
      ),
    );
    expect(find.text('أهلاً متجر الاختبار'), findsOneWidget);
    expect(find.byKey(const Key('workspace-menu')), findsNothing);
  });
}

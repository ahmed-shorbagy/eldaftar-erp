import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/pending_invoice_sends_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _boundary = Key('pending-invoice-capture');
const _operation = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/NotoSansArabic.ttf').readAsBytes();
    await (FontLoader(
      'NotoSansArabic',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(icons)))).load();
  });

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      final suffix = '${dark ? 'dark' : 'light'}-${width.toInt()}';
      testWidgets('captures pending invoices $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = HttpOpeningGateway(
          client: MockClient(
            (request) async => http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'items': [
                    {
                      'operation_id': _operation,
                      'kind': 'sale',
                      'shop_sequence': '42',
                      'occurred_at_cairo': '2026-09-29T09:00:00',
                      'customer_name': 'عميل تجريبي',
                    },
                  ],
                  'next_before_sequence': null,
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          supabaseUrl: 'https://example.test',
          publishableKey: 'test',
          accessToken: () => 'test-token',
          currentUserId: () => 'test-owner',
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: _boundary,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: PendingInvoiceSendsScreen(
                  gateway: gateway,
                  userId: 'test-owner',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('بيع رقم 42'), findsOneWidget);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_boundary),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/pending-invoice-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/pending-$suffix.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

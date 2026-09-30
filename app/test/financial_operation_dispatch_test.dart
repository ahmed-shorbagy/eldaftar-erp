import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _boundary = Key('operation-dispatch-capture');

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
  testWidgets('invoice cannot be marked sent before a handoff', (tester) async {
    tester.view.physicalSize = const Size(320, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = HttpOpeningGateway(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/get_daily_ledger_operation')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'operation_id': _operationId,
                'kind': 'sale',
                'shop_sequence': '42',
                'shop_name': 'متجر تجريبي',
                'actor_display_name': 'المالك',
                'payload': {
                  'total_piastres': '6000000',
                  'customer_name': 'عميل تجريبي',
                  'customer_phone': '01012345678',
                  'note': '',
                  'items': [
                    {
                      'item_name': 'خاتم',
                      'category': 'worked_jewelry',
                      'karat': 21,
                      'milligrams': '10000',
                      'count': '1',
                      'line_price_piastres': null,
                    },
                  ],
                  'tenders': [
                    {'method': 'cash', 'piastres': '6000000'},
                  ],
                },
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/get_invoice_dispatch_state')) {
          return http.Response(
            jsonEncode({'operation_id': _operationId, 'status': 'unconfirmed'}),
            200,
          );
        }
        fail('Unexpected RPC ${request.url.path}');
      }),
      supabaseUrl: 'https://example.test',
      publishableKey: 'test',
      accessToken: () => 'test-token',
      currentUserId: () => 'test-owner',
    );
    Widget screen(bool dark) => MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: RepaintBoundary(
        key: _boundary,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: FinancialOperationScreen(
            gateway: gateway,
            userId: 'test-owner',
            line: const LedgerFeedLine(
              kind: 'sale',
              labelAr: 'بيع',
              operationId: _operationId,
              actorDisplayName: 'المالك',
              occurredAt: '2026-09-29T06:00:00+00:00',
              occurredAtCairo: '2026-09-29T09:00:00',
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(find.text('لم يؤكد الإرسال'), findsOneWidget);
    final confirm = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('تأكيد الإرسال بعد إرساله'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(confirm.onPressed, isNull);
    for (final width in [320.0, 1440.0]) {
      for (final dark in [false, true]) {
        tester.view.physicalSize = Size(width, 820);
        await tester.pumpWidget(screen(dark));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -450));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_boundary),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/operation-dispatch-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/operation-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

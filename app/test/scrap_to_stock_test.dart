import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/scrap_to_stock_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scrap = [
  LedgerScrapLine(
    karat: 21,
    labelAr: 'كسر عيار 21',
    milligrams: '500',
    grams: '0.500',
  ),
];

class _Gateway implements ScrapToStockGateway, OpeningGateway {
  bool pendingSavedBeforePost = false;
  Map<String, Object?>? payload;

  @override
  Future<FinancialCommandResult> convertScrapToStock({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    pendingSavedBeforePost =
        (await const PendingFinancialCommands().read(
          'owner-a',
          'shop-a',
        ))?.key ==
        idempotencyKey;
    this.payload = payload;
    return const FinancialCommitted(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      replayed: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('sends exact integer payload and retries the same command', () async {
    const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    var requests = 0;
    final expectedBody = {
      'p_idempotency_key': key,
      'p_payload': {
        'version': 1,
        'kind': 'scrap_to_stock',
        'category': 'coin',
        'karat': 21,
        'milligrams': '375',
        'count': '2',
        'item_name': 'جنيه ذهب',
        'note': 'تحويل داخلي',
      },
    };
    final gateway = HttpOpeningGateway(
      client: MockClient((request) async {
        requests++;
        expect(
          request.url.path,
          '/rest/v1/rpc/post_daily_ledger_scrap_to_stock',
        );
        expect(jsonDecode(request.body), expectedBody);
        return http.Response(
          jsonEncode({
            'ok': true,
            'operation_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'replayed': false,
          }),
          200,
        );
      }),
      supabaseUrl: 'https://example.test',
      publishableKey: 'test',
      accessToken: () => 'token',
      currentUserId: () => 'owner-a',
    );
    expect(
      await gateway.convertScrapToStock(
        callerUserId: 'owner-a',
        idempotencyKey: key,
        payload: expectedBody['p_payload']! as Map<String, Object?>,
      ),
      isA<FinancialCommitted>(),
    );
    expect(
      await gateway.retryPending(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'scrap_to_stock',
          body: expectedBody,
        ),
      ),
      isA<FinancialCommitted>(),
    );
    expect(requests, 2);
  });

  testWidgets('blocks excess scrap then confirms reviewed exact effects', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ScrapToStockScreen(
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-a',
            shopId: 'shop-a',
            scrap: _scrap,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('scrap-stock-name')), 'خاتم');
    await tester.enterText(find.byKey(const Key('scrap-stock-grams')), '0.501');
    await tester.ensureVisible(find.byKey(const Key('scrap-stock-review')));
    tester
        .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
        .onPressed!();
    await tester.pump();
    expect(find.text('راجع الوزن المتاح والعدد واسم الصنف.'), findsOneWidget);
    expect(gateway.payload, isNull);

    await tester.enterText(find.byKey(const Key('scrap-stock-grams')), '0.375');
    await tester.enterText(find.byKey(const Key('scrap-stock-count')), '2');
    await tester.ensureVisible(find.byKey(const Key('scrap-stock-review')));
    tester
        .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.textContaining('ينقص الكسر: 0.375 جرام'), findsOneWidget);
    expect(find.textContaining('يزيد المخزون: 0.375 جرام'), findsOneWidget);
    expect(find.text('النقدية لا تتغير.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scrap-stock-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.pendingSavedBeforePost, isTrue);
    expect(gateway.payload?['milligrams'], '375');
    expect(gateway.payload?['count'], '2');
    expect(gateway.payload?['karat'], 21);
  });

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('fits scrap-to-stock review at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = _Gateway();
        const boundaryKey = Key('scrap-stock-capture');
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: ScrapToStockScreen(
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'owner-a',
                  shopId: 'shop-a',
                  scrap: _scrap,
                ),
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('scrap-stock-name')),
          'خاتم',
        );
        await tester.enterText(
          find.byKey(const Key('scrap-stock-grams')),
          '0.125',
        );
        tester
            .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
            .onPressed!();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('scrap-stock-confirm')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '${Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/scrap-to-stock-review'}/'
            'scrap-to-stock-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

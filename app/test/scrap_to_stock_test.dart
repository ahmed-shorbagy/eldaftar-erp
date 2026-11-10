import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
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

import 'batch2_trade_support.dart';

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
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
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
    await tester.tap(find.byKey(const Key('scrap-stock-item-خواتم')));
    await tester.pump();
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
    expect(
      find.textContaining('ينقص الكسر: 0.38 جرام (375 ملليجرام) · عيار 21'),
      findsOneWidget,
    );
    expect(find.textContaining('يزيد مخزون خواتم عيار 21:'), findsOneWidget);
    expect(find.text('النقدية لا تتغير.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scrap-stock-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.pendingSavedBeforePost, isTrue);
    expect(gateway.payload?['milligrams'], '375');
    expect(gateway.payload?['count'], '2');
    expect(gateway.payload?['karat'], 21);
    expect(gateway.payload?['note'], '');
    expect(gateway.payload?['item_name'], 'خواتم');
    expect(gateway.payload?['category'], 'worked_jewelry');
    expect(find.text('ملاحظة اختيارية'), findsNothing);
    expect(find.text('مشغولات'), findsNothing);
  });

  testWidgets('karat 21 lists jewelry, coins, and other without مشغولات', (
    tester,
  ) async {
    await _pumpScrap(tester, scrap: _scrap);
    for (final label in [
      'خواتم',
      'حلقان',
      'سلاسل',
      'تعاليق',
      'جنيهات',
      'أخرى',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('سبائك'), findsNothing);
    expect(find.text('مشغولات'), findsNothing);
    expect(find.text('ملاحظة اختيارية'), findsNothing);
  });

  testWidgets('karat 24 lists only bullion', (tester) async {
    await _pumpScrap(
      tester,
      scrap: const [
        LedgerScrapLine(
          karat: 24,
          labelAr: 'كسر عيار 24',
          milligrams: '8000',
          grams: '8.000',
        ),
      ],
    );
    expect(find.text('سبائك'), findsOneWidget);
    expect(find.text('خواتم'), findsNothing);
    expect(find.text('أخرى'), findsNothing);
    expect(find.text('جنيهات'), findsNothing);
    expect(find.text('مشغولات'), findsNothing);
  });

  testWidgets('review without an item asks for one', (tester) async {
    await _pumpScrap(tester, scrap: _scrap);
    tester
        .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
        .onPressed!();
    await tester.pump();
    expect(find.text('اختر الصنف.'), findsOneWidget);
  });

  testWidgets('خاتم at 21 sends worked jewelry and an empty note', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _pumpScrap(
      tester,
      gateway: gateway,
      scrap: const [
        LedgerScrapLine(
          karat: 21,
          labelAr: 'كسر عيار 21',
          milligrams: '5000',
          grams: '5.000',
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('scrap-stock-item-خواتم')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('scrap-stock-grams')), '2.000');
    await tester.ensureVisible(find.byKey(const Key('scrap-stock-review')));
    tester
        .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrap-stock-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payload?['category'], 'worked_jewelry');
    expect(gateway.payload?['karat'], 21);
    expect(gateway.payload?['milligrams'], '2000');
    expect(gateway.payload?['item_name'], 'خواتم');
    expect(gateway.payload?['note'], '');
  });

  testWidgets('a shop product chosen from أخرى keeps its name', (tester) async {
    final gateway = _Gateway();
    final catalog = Batch2Catalog(
      productsPage: const ReadPage.ready([
        CatalogProduct(
          id: 'product-1',
          name: 'دبلة خاصة',
          category: 'worked_jewelry',
          karat: 21,
          createdAt: '2026-11-08T00:00:00Z',
        ),
      ], null),
    );
    await _pumpScrap(
      tester,
      gateway: gateway,
      catalog: catalog,
      scrap: const [
        LedgerScrapLine(
          karat: 21,
          labelAr: 'كسر عيار 21',
          milligrams: '5000',
          grams: '5.000',
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrap-stock-item-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-new-category-دبلة خاصة')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scrap-stock-grams')), '1.000');
    tester
        .widget<FilledButton>(find.byKey(const Key('scrap-stock-review')))
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrap-stock-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payload?['item_name'], 'دبلة خاصة');
    expect(gateway.payload?['category'], 'worked_jewelry');
    expect(gateway.payload?['note'], '');
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
        await tester.tap(find.byKey(const Key('scrap-stock-item-خواتم')));
        await tester.pump();
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

Future<void> _pumpScrap(
  WidgetTester tester, {
  required List<LedgerScrapLine> scrap,
  _Gateway? gateway,
  InventoryGateway? catalog,
}) async {
  final resolved = gateway ?? _Gateway();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ScrapToStockScreen(
          gateway: resolved,
          statusGateway: resolved,
          userId: 'owner-a',
          shopId: 'shop-a',
          scrap: scrap,
          catalog: catalog,
        ),
      ),
    ),
  );
  await tester.pump();
}

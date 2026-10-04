import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/linked_return_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _operation = <String, Object?>{
  'operation_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'shop_id': 'shop-a',
  'shop_sequence': '15',
  'kind': 'purchase',
  'purchase_payable_remaining_piastres': '200000',
  'payload': <String, Object?>{
    'total_piastres': '500000',
    'items': <Object?>[
      <String, Object?>{
        'category': 'worked_jewelry',
        'karat': 21,
        'milligrams': '2500',
        'count': '1',
        'item_name': 'سوار',
      },
    ],
  },
};

class _Gateway implements LinkedReturnGateway, OpeningGateway {
  bool pendingSavedBeforePost = false;
  String? note;

  @override
  Future<FinancialCommandResult> returnOperation({
    required String callerUserId,
    required String idempotencyKey,
    required String originalOperationId,
    required String note,
  }) async {
    pendingSavedBeforePost =
        (await const PendingFinancialCommands().read(
          'owner-a',
          'shop-a',
        ))?.key ==
        idempotencyKey;
    this.note = note;
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

  test('return RPC and durable retry use the exact same envelope', () async {
    const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    final expected = {
      'p_idempotency_key': key,
      'p_original_operation_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'p_note': 'سبب',
    };
    var requests = 0;
    final gateway = HttpOpeningGateway(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/rest/v1/rpc/post_daily_ledger_return');
        expect(jsonDecode(request.body), expected);
        return http.Response(
          jsonEncode({
            'ok': true,
            'operation_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'replayed': requests > 1,
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
      await gateway.returnOperation(
        callerUserId: 'owner-a',
        idempotencyKey: key,
        originalOperationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        note: 'سبب',
      ),
      isA<FinancialCommitted>(),
    );
    expect(
      await gateway.retryPending(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'purchase_return',
          body: expected,
        ),
      ),
      isA<FinancialCommitted>(),
    );
    expect(requests, 2);
  });

  Future<_Gateway> pumpReturn(
    WidgetTester tester, {
    required double width,
    required bool dark,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    final gateway = _Gateway();
    const boundaryKey = Key('linked-return-capture');
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
            child: LinkedReturnScreen(
              gateway: gateway,
              statusGateway: gateway,
              userId: 'owner-a',
              shopId: 'shop-a',
              operation: _operation,
            ),
          ),
        ),
      ),
    );
    return gateway;
  }

  testWidgets('reviews paid cash, cancelled payable, gold, and saves retry', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = await pumpReturn(tester, width: 320, dark: true);
    expect(find.text('النقد المرتجع: 3000.00 جنيه'), findsOneWidget);
    expect(find.text('يلغى المستحق المتبقي: 2000.00 جنيه'), findsOneWidget);
    expect(find.textContaining('2.500 جرام'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('return-note')), 'إلغاء متفق');
    tester
        .widget<FilledButton>(find.byKey(const Key('return-review')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('بعد التأكيد لا تُحذف العملية الأصلية.'), findsOneWidget);
    tester
        .widget<FilledButton>(find.byKey(const Key('return-confirm')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(gateway.pendingSavedBeforePost, isTrue);
    expect(gateway.note, 'إلغاء متفق');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('fits linked return review at $width dark=$dark', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpReturn(tester, width: width, dark: dark);
        tester
            .widget<FilledButton>(find.byKey(const Key('return-review')))
            .onPressed!();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('return-confirm')), findsOneWidget);
        expect(find.textContaining('3000.00 جنيه'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('linked-return-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '${Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/linked-return-review'}/'
            'linked-return-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

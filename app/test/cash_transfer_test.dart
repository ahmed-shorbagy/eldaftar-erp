import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/cash_transfer_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cash = [
  LedgerCashLine(
    method: 'cash',
    labelAr: 'نقدي',
    piastres: '10000',
    pounds: '100.00',
  ),
  LedgerCashLine(
    method: 'instant_transfer',
    labelAr: 'تحويل فوري',
    piastres: '2000',
    pounds: '20.00',
  ),
  LedgerCashLine(
    method: 'wallet',
    labelAr: 'محفظة',
    piastres: '0',
    pounds: '0.00',
  ),
  LedgerCashLine(
    method: 'card',
    labelAr: 'بطاقة',
    piastres: '0',
    pounds: '0.00',
  ),
];

class _Gateway implements CashTransferGateway, OpeningGateway {
  bool pendingSavedBeforePost = false;
  String? amount;

  @override
  Future<FinancialCommandResult> transferCash({
    required String callerUserId,
    required String idempotencyKey,
    required String fromMethod,
    required String toMethod,
    required String amountPiastres,
    required String note,
  }) async {
    pendingSavedBeforePost =
        (await const PendingFinancialCommands().read(
          'owner-a',
          'shop-a',
        ))?.key ==
        idempotencyKey;
    amount = amountPiastres;
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

  test(
    'cash transfer sends exact integer payload and retries same command',
    () async {
      const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      var requests = 0;
      final expectedBody = {
        'p_idempotency_key': key,
        'p_payload': {
          'version': 1,
          'kind': 'cash_transfer',
          'from_method': 'cash',
          'to_method': 'card',
          'amount_piastres': '2500',
          'note': 'تسوية',
        },
      };
      final gateway = HttpOpeningGateway(
        client: MockClient((request) async {
          requests++;
          expect(
            request.url.path,
            '/rest/v1/rpc/post_daily_ledger_cash_transfer',
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
      final result = await gateway.transferCash(
        callerUserId: 'owner-a',
        idempotencyKey: key,
        fromMethod: 'cash',
        toMethod: 'card',
        amountPiastres: '2500',
        note: 'تسوية',
      );
      expect(result, isA<FinancialCommitted>());
      final retried = await gateway.retryPending(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'cash_transfer',
          body: expectedBody,
        ),
      );
      expect(retried, isA<FinancialCommitted>());
      expect(requests, 2);
    },
  );

  testWidgets('reviews exact net effect and saves retry before posting', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CashTransferScreen(
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-a',
            shopId: 'shop-a',
            cash: _cash,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('transfer-amount')), '101');
    await tester.tap(find.byKey(const Key('transfer-review')));
    await tester.pump();
    expect(find.textContaining('راجع الوسيلتين'), findsOneWidget);
    expect(gateway.amount, isNull);
    await tester.enterText(find.byKey(const Key('transfer-amount')), '25');
    await tester.tap(find.byKey(const Key('transfer-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('75.00 جنيه'), findsOneWidget);
    expect(find.textContaining('45.00 جنيه'), findsOneWidget);
    expect(find.text('إجمالي النقدية والذهب لا يتغيران.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('transfer-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.amount, '2500');
    expect(gateway.pendingSavedBeforePost, isTrue);
  });

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('captures cash transfer review $width $dark', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const boundaryKey = Key('transfer-capture');
        final gateway = _Gateway();
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
                child: CashTransferScreen(
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'owner-a',
                  shopId: 'shop-a',
                  cash: _cash,
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byKey(const Key('transfer-amount')), '25');
        await tester.tap(find.byKey(const Key('transfer-review')));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/transfer-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/transfer-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

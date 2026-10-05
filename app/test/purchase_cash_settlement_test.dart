import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_issue.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/quantities.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/purchase_cash_settlement_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements PurchaseSettlementGateway, OpeningGateway {
  bool pendingSavedBeforePost = false;
  final tenders = <List<Map<String, Object?>>>[];

  @override
  Future<FinancialCommandResult> settlePurchaseCash({
    required String callerUserId,
    required String idempotencyKey,
    required String purchaseOperationId,
    required List<Map<String, Object?>> tenders,
  }) async {
    pendingSavedBeforePost =
        (await const PendingFinancialCommands().read(
          'owner-a',
          'shop-a',
        ))?.key ==
        idempotencyKey;
    this.tenders.add(tenders);
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

  testWidgets('settlement reviews cash and does not move gold', (tester) async {
    final gateway = _Gateway();
    final remaining = Piastres.parsePounds('40000') as Accepted<Piastres>;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: PurchaseCashSettlementScreen(
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-a',
            shopId: 'shop-a',
            purchaseOperationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            remaining: remaining.value,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('settlement-amount')), '50000');
    await tester.tap(find.byKey(const Key('settlement-review')));
    await tester.pump();
    expect(find.textContaining('لا يتجاوز المستحق'), findsOneWidget);
    expect(gateway.tenders, isEmpty);
    await tester.enterText(find.byKey(const Key('settlement-amount')), '20000');
    await tester.tap(find.byKey(const Key('settlement-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('يبقى مستحقاً: 20,000'), findsOneWidget);
    expect(find.text('لا يتغير الذهب أو عدد القطع.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settlement-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.tenders.single.single['piastres'], '2000000');
    expect(gateway.pendingSavedBeforePost, isTrue);
  });

  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('captures settlement review $width $dark', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = _Gateway();
        final remaining = Piastres.parsePounds('40000') as Accepted<Piastres>;
        const boundaryKey = Key('settlement-capture');
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
                child: PurchaseCashSettlementScreen(
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'owner-a',
                  shopId: 'shop-a',
                  purchaseOperationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  remaining: remaining.value,
                ),
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('settlement-amount')),
          '20000',
        );
        await tester.tap(find.byKey(const Key('settlement-review')));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/settlement-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/settlement-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}

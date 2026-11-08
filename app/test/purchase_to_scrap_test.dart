import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('ring purchase is booked as scrap and keeps the piece name', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'خاتم');
    expect(find.byKey(const Key('trade-count-0')), findsNothing);
    await enterTradeField(tester, const Key('trade-grams-0'), '3.50');
    await enterTradeField(tester, const Key('trade-purchase-price'), '1000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '1000');
    await reviewTrade(tester);
    expect(find.textContaining('يزيد كسر عيار 18'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final line =
        (gateway.payloads.single['items'] as List).single
            as Map<String, Object?>;
    expect(line['category'], 'scrap');
    expect(line['karat'], 18);
    expect(line['item_name'], 'خاتم');
    expect(line['count'], isNull);
    expect(line['milligrams'], '3500');
  });

  testWidgets('purchased bars stay bullion stock', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'سبائك');
    await tester.tap(find.byKey(const Key('nominal-select-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nominal-apply')));
    await tester.pumpAndSettle();
    await enterTradeField(tester, const Key('trade-purchase-price'), '500');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '500');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final line =
        (gateway.payloads.single['items'] as List).single
            as Map<String, Object?>;
    expect(line['category'], 'bullion');
    expect(line['karat'], 24);
    expect(line['count'], isNotNull);
  });

  testWidgets('a sold ring stays worked jewelry', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '3.50');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '1000');
    await reviewTrade(tester);
    expect(find.textContaining('ينقص مخزون خاتم'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final line =
        (gateway.payloads.single['items'] as List).single
            as Map<String, Object?>;
    expect(line['category'], 'worked_jewelry');
    expect(line['item_name'], 'خاتم');
    expect(line['count'], '1');
  });

  testWidgets('editing an old jewelry purchase does not rewrite its category', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    Map<String, Object?>? reviewed;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: FinancialTradeScreen(
            kind: FinancialKind.purchase,
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-1',
            shopId: 'shop-1',
            initialPayload: {
              'version': 1,
              'kind': 'purchase',
              'total_piastres': '10000',
              'tenders': [
                {'method': 'cash', 'piastres': '10000'},
              ],
              'items': [
                {
                  'category': 'worked_jewelry',
                  'karat': 21,
                  'milligrams': '3500',
                  'count': '1',
                  'item_name': 'خاتم',
                  'line_price_piastres': null,
                },
              ],
              'description': '',
              'customer_name': '',
              'customer_phone': '',
              'note': '',
            },
            onDraftReviewed: (draft) async {
              reviewed = draft.toJson();
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('مشغولات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-category-0')));
    await tester.pumpAndSettle();
    expect(find.text('مشغولات'), findsWidgets);
    await tester.tap(find.text('مشغولات').last);
    await tester.pumpAndSettle();
    await reviewTrade(tester);
    final line = (reviewed!['items'] as List).single as Map<String, Object?>;
    expect(line['category'], 'worked_jewelry');
    expect(line['karat'], 21);
    expect(line['item_name'], 'خاتم');
    expect(line['count'], '1');
    expect(gateway.payloads, isEmpty);
  });
}

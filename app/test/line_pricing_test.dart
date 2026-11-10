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

  testWidgets('priced sale submits a line price for every item', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await tester.tap(find.byKey(const Key('trade-line-pricing')));
    await tester.pumpAndSettle();
    await chooseTradeItem(tester, 'خواتم');
    await _addItem(tester, 'حلقان');
    await enterTradeField(tester, const Key('trade-grams-0'), '3.50');
    await enterTradeField(tester, const Key('trade-line-price-0'), '5000');
    await enterTradeField(tester, const Key('trade-grams-1'), '2.00');
    await enterTradeField(tester, const Key('trade-line-price-1'), '3000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '8000');
    expect(find.byKey(const Key('trade-line-price-sum')), findsOneWidget);
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final items = gateway.payloads.single['items'] as List;
    expect(items[0]['line_price_piastres'], '500000');
    expect(items[1]['line_price_piastres'], '300000');
  });

  testWidgets('a line-price mismatch is shown and is not submitted', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await tester.tap(find.byKey(const Key('trade-line-pricing')));
    await tester.pumpAndSettle();
    await chooseTradeItem(tester, 'خواتم');
    await _addItem(tester, 'حلقان');
    await enterTradeField(tester, const Key('trade-grams-0'), '3.50');
    await enterTradeField(tester, const Key('trade-line-price-0'), '5000');
    await enterTradeField(tester, const Key('trade-grams-1'), '2.00');
    await enterTradeField(tester, const Key('trade-line-price-1'), '3000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '7000');
    await reviewTrade(tester);
    expect(find.text('أسعار الأصناف لا تساوي الإجمالي.'), findsOneWidget);
    expect(find.byKey(const Key('trade-confirm')), findsNothing);
    expect(gateway.payloads, isEmpty);
  });

  testWidgets('line pricing off submits null prices', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    expect(find.byKey(const Key('trade-line-price-0')), findsNothing);
    await chooseTradeItem(tester, 'خواتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.00');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '100');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(
      (gateway.payloads.single['items'] as List).single['line_price_piastres'],
      isNull,
    );
  });

  testWidgets('the line-pricing switch is restored for the same shop', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await tester.tap(find.byKey(const Key('trade-line-pricing')));
    await tester.pumpAndSettle();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('trade-line-pricing')))
          .value,
      isTrue,
    );
    expect(find.byKey(const Key('trade-line-price-0')), findsOneWidget);
  });

  testWidgets('editing a priced operation shows line prices without saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final gateway = Batch2TradeGateway();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: FinancialTradeScreen(
          kind: FinancialKind.sale,
          gateway: gateway,
          statusGateway: gateway,
          userId: 'owner-1',
          shopId: 'shop-1',
          initialPayload: {
            'version': 1,
            'kind': 'sale',
            'total_piastres': '800000',
            'tenders': [
              {'method': 'cash', 'piastres': '800000'},
            ],
            'items': [
              {
                'category': 'worked_jewelry',
                'karat': 18,
                'milligrams': '3500',
                'count': '1',
                'item_name': 'خواتم',
                'line_price_piastres': '500000',
              },
            ],
            'description': '',
            'customer_name': '',
            'customer_phone': '',
            'note': '',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('trade-line-pricing')))
          .value,
      isTrue,
    );
    expect(find.byKey(const Key('trade-edit-line-price-0')), findsNothing);
    expect(find.byKey(const Key('trade-line-price-0')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('trade_line_pricing_shop-1'), isNull);
  });
}

Future<void> _addItem(WidgetTester tester, String label) async {
  await revealTrade(tester, find.byKey(const Key('trade-add-item')));
  await tester.tap(find.byKey(const Key('trade-add-item')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('trade-new-category-$label')));
  await tester.pumpAndSettle();
}

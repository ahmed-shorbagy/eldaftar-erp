import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
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

  testWidgets('yes keeps the coin line as coin stock', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'جنيهات');
    await tester.tap(find.byKey(const Key('nominal-select-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nominal-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-stock-question')), findsOneWidget);
    await keepPurchaseAsStock(tester);
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '7000');
    await reviewTrade(tester);
    expect(find.textContaining('يزيد مخزون الجنيهات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final line =
        (gateway.payloads.single['items'] as List).single
            as Map<String, Object?>;
    expect(line['category'], 'coin');
    expect(line['karat'], 21);
    expect(line['count'], isNotNull);
  });

  testWidgets('no plus 21 sends a scrap line at 21 with the same weight', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'جنيهات');
    await tester.tap(find.byKey(const Key('nominal-select-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nominal-apply')));
    await tester.pumpAndSettle();
    final grams = tester
        .widget<TextField>(find.byKey(const Key('trade-grams-0')))
        .controller!
        .text;
    await bookPurchaseAsScrap(tester, 21);
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '7000');
    await reviewTrade(tester);
    expect(find.textContaining('يزيد الكسر عيار 21'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final line =
        (gateway.payloads.single['items'] as List).single
            as Map<String, Object?>;
    expect(line['category'], 'scrap');
    expect(line['karat'], 21);
    expect(line['item_name'], 'كسر');
    expect(line['count'], isNull);
    expect(line['milligrams'], isNotNull);
    expect(grams.isNotEmpty, isTrue);
  });

  testWidgets('sale never asks the stock-or-scrap question', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'جنيهات');
    await tester.tap(find.byKey(const Key('nominal-select-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nominal-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-stock-question')), findsNothing);
  });
}

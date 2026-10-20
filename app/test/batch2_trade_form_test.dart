import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
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

  testWidgets('fast sale reviews two-decimal gold and exact net grams', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    expect(find.byKey(const Key('trade-next')), findsNothing);
    expect(find.byKey(const Key('trade-line-price-0')), findsNothing);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.255');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-grams-0')))
          .controller!
          .text,
      isEmpty,
    );
    await enterTradeField(tester, const Key('trade-grams-0'), '1.26');
    await enterTradeField(
      tester,
      const Key('trade-tender-amount-0'),
      '4200.25',
    );
    await revealTrade(tester, find.byKey(const Key('trade-paid-total')));
    expect(
      tester.widget<Text>(find.byKey(const Key('trade-paid-total'))).data,
      'الإجمالي: 4,200.25',
    );
    await reviewTrade(tester);
    expect(find.text('4,200.25'), findsWidgets);
    expect(find.textContaining('1.26 جرام'), findsWidgets);
    expect(find.textContaining('ينقص مخزون'), findsOneWidget);
    expect(gateway.keys, isEmpty);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(find.textContaining('1.26 جرام'), findsWidgets);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    expect(gateway.keys, hasLength(1));
    expect(gateway.pendingExistedAtPost, isTrue);
    expect(gateway.payloads.single['total_piastres'], '420025');
    expect(
      (gateway.payloads.single['items'] as List).single['milligrams'],
      '1260',
    );
    expect(tester.takeException(), isNull);
  });

  for (final kind in [FinancialKind.sale, FinancialKind.purchase]) {
    testWidgets('simple ${kind.name} omits removed pricing fields', (
      tester,
    ) async {
      final gateway = Batch2TradeGateway();
      await pumpTradeScreen(
        tester,
        gateway: gateway,
        statusGateway: gateway,
        kind: kind,
      );
      await chooseTradeItem(tester, 'خاتم');
      await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
      if (kind == FinancialKind.purchase) {
        await enterTradeField(
          tester,
          const Key('trade-purchase-price'),
          '1040.02',
        );
      }
      await enterTradeField(
        tester,
        const Key('trade-tender-amount-0'),
        '1040.02',
      );
      expect(find.byKey(const Key('trade-price-disclosure')), findsNothing);
      expect(find.byKey(const Key('trade-base-price')), findsNothing);
      expect(find.byKey(const Key('trade-workmanship')), findsNothing);
      await reviewTrade(tester);
      expect(gateway.payloads, isEmpty);
      await tester.tap(find.byKey(const Key('trade-confirm')));
      await tester.pumpAndSettle();
      expect(gateway.payloads.single['total_piastres'], '104002');
      expect(gateway.payloads.single['pricing'], isNull);
      expect(gateway.pendingExistedAtPost, isTrue);
    });
  }

  testWidgets('purchase omits customer entry for partial and zero payment', (
    tester,
  ) async {
    final partial = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: partial,
      statusGateway: partial,
      kind: FinancialKind.purchase,
    );
    expect(find.byKey(const Key('trade-seller-name')), findsNothing);
    expect(find.byKey(const Key('trade-customer-disclosure')), findsNothing);
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '10.000');
    await enterTradeField(tester, const Key('trade-purchase-price'), '60000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '20000');
    await reviewTrade(tester);
    expect(find.textContaining('يبقى مستحقاً للعميل: 40,000'), findsOneWidget);
    expect(find.textContaining('تنتقل الملكية إلى المتجر'), findsOneWidget);
    expect(find.textContaining('يزيد مخزون خاتم'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(partial.payloads.single['purchase_obligation_piastres'], '4000000');
    expect(partial.payloads.single['total_piastres'], '6000000');
    expect(partial.payloads.single['customer_name'], '');

    final unpaid = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: unpaid,
      statusGateway: unpaid,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'كسر');
    expect(find.byKey(const Key('trade-count-0')), findsNothing);
    await enterTradeField(tester, const Key('trade-grams-0'), '2.500');
    await enterTradeField(tester, const Key('trade-purchase-price'), '1500');
    await reviewTrade(tester);
    expect(find.textContaining('يبقى مستحقاً للعميل: 1,500'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(unpaid.payloads.single['tenders'], isEmpty);
    expect(unpaid.payloads.single['customer_name'], '');
    expect(unpaid.payloads.single['purchase_obligation_piastres'], '150000');
    expect(unpaid.payloads.single['total_piastres'], '150000');
  });

  testWidgets(
    'multi-denomination picker uses active shop overrides and paginated additions',
    (tester) async {
      final catalog = Batch2Catalog(
        coinPage: ReadPage.ready([
          tradeCoin(
            id: 'coin-1',
            label: 'جنيه',
            nominalMilligrams: BigInt.from(8500),
          ),
          tradeCoin(
            id: 'coin-old',
            label: 'عملة قديمة',
            nominalMilligrams: BigInt.from(1000),
            active: false,
          ),
        ], 'coins-2'),
      );
      catalog.laterCoins = {
        'coins-2': ReadPage.ready([
          tradeCoin(
            id: 'coin-2',
            label: 'جنيه كبير',
            nominalMilligrams: BigInt.from(15500),
          ),
        ], null),
      };
      final shop = Batch2TradeGateway();
      await pumpTradeScreen(
        tester,
        gateway: shop,
        statusGateway: shop,
        kind: FinancialKind.purchase,
        catalog: catalog,
      );
      await chooseTradeItem(tester, 'جنيهات');
      expect(find.text('عملة قديمة'), findsNothing);
      expect(find.text('8.500 جرام للقطعة'), findsOneWidget);
      final pound = find.ancestor(
        of: find.text('جنيه'),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(pound);
      await tester.tap(pound);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nominal-count-2')), '2');
      await tester.tap(find.byKey(const Key('nominal-apply')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-grams-0')))
            .controller!
            .text,
        '17',
      );
      await revealTrade(tester, find.byKey(const Key('trade-nominal-more-0')));
      await tester.tap(find.byKey(const Key('trade-nominal-more-0')));
      await tester.pumpAndSettle();
      await revealTrade(tester, find.byKey(const Key('trade-nominals-0')));
      await tester.tap(find.byKey(const Key('trade-nominals-0')));
      await tester.pumpAndSettle();
      final large = find.ancestor(
        of: find.text('جنيه كبير'),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(large);
      await tester.tap(large);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nominal-apply')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-grams-0')))
            .controller!
            .text,
        '15.5',
      );
      expect(catalog.coinCursors, contains('coins-2'));
      await enterTradeField(tester, const Key('trade-grams-0'), '15.25');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-grams-0')))
            .controller!
            .text,
        '15.25',
      );
    },
  );

  testWidgets('other opens a text-only predefined grid without inventory', (
    tester,
  ) async {
    final catalog = Batch2Catalog(
      productsPage: ReadPage.ready([
        tradeProduct(id: 'p1', name: 'خاتم ملكي', karat: 21),
      ], 'products-2'),
    );
    catalog.laterProducts = {
      'products-2': ReadPage.ready([
        tradeProduct(id: 'p2', name: 'سلسلة نادرة', karat: 18),
      ], null),
    };
    final gateway = Batch2TradeGateway();
    var openedInventory = false;
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
      catalog: catalog,
      inventoryPage: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () {
              openedInventory = true;
              Navigator.of(context).pop();
            },
            child: const Text('رجوع من المخزون'),
          ),
        ),
      ),
    );
    await chooseTradeItem(tester, 'أخرى');
    expect(find.byKey(const Key('trade-other-grid')), findsOneWidget);
    expect(find.byKey(const Key('trade-catalog-table')), findsNothing);
    expect(find.byKey(const Key('trade-open-inventory')), findsNothing);
    expect(find.byKey(const Key('trade-select-name')), findsNothing);
    expect(find.byKey(const Key('trade-select-غويشة')), findsOneWidget);
    await revealTrade(tester, find.byKey(const Key('trade-select-غويشة')));
    await tester.tap(find.byKey(const Key('trade-select-غويشة')));
    await tester.pumpAndSettle();
    expect(openedInventory, isFalse);
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '50');
    await reviewTrade(tester);
    expect(find.textContaining('غويشة'), findsWidgets);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(
      (gateway.payloads.single['items'] as List).single['item_name'],
      'غويشة',
    );
    expect(
      (gateway.payloads.single['items'] as List).single['category'],
      'worked_jewelry',
    );
  });

  testWidgets('other grid rejects an empty selection without typing', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'أخرى');
    expect(find.byKey(const Key('trade-other-grid')), findsOneWidget);
    expect(find.byKey(const Key('trade-select-name')), findsNothing);
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '50');
    await reviewTrade(tester);
    expect(find.text('اختر الصنف.'), findsOneWidget);
    await revealTrade(tester, find.byKey(const Key('trade-select-طقم')));
    await tester.tap(find.byKey(const Key('trade-select-طقم')));
    await tester.pumpAndSettle();
    await reviewTrade(tester);
    expect(find.textContaining('طقم'), findsWidgets);
  });

  testWidgets('unknown sale keeps one key and ignores a duplicate tap', (
    tester,
  ) async {
    final gate = Completer<FinancialCommandResult>();
    final gateway = Batch2TradeGateway()
      ..result = const FinancialUnknown()
      ..statusResult = const StatusUnknown()
      ..postGate = gate;
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '10');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('جارٍ حفظ العملية…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pump();
    expect(gateway.keys, hasLength(1));
    expect(find.byKey(const Key('trade-success')), findsNothing);
    gate.complete(const FinancialUnknown());
    await tester.pumpAndSettle();
    expect(find.textContaining('حالة العملية غير مؤكدة'), findsOneWidget);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    gateway.postGate = null;
    gateway.statusResult = const StatusAbsent();
    await tester.tap(find.byKey(const Key('trade-check-status')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم نتأكد من حفظ العملية'), findsOneWidget);
    final edit = tester.widget<TextButton>(find.byKey(const Key('trade-edit')));
    expect(edit.onPressed, isNull);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[0], gateway.keys[1]);
    expect(gateway.payloads[0], gateway.payloads[1]);
    expect(find.byKey(const Key('trade-success')), findsNothing);
  });

  testWidgets('invoice opens only after a confirmed sale operation', (
    tester,
  ) async {
    final missingTime = Batch2DispatchGateway()
      ..operationBody = confirmedSaleOperation(
        occurredAt: null,
        occurredAtCairo: null,
      );
    await pumpTradeScreen(
      tester,
      gateway: missingTime,
      statusGateway: missingTime,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'حلق');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
    await enterTradeField(
      tester,
      const Key('trade-tender-amount-0'),
      '4200.25',
    );
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    await reviewTrade(tester);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(find.byKey(const Key('trade-invoice-manual')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-send-invoice')));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل الفاتورة المؤكدة.'), findsOneWidget);
    expect(find.text('إرسال عبر واتساب'), findsNothing);
    expect(missingTime.operationIds, [tradeOperationId]);

    final ready = Batch2DispatchGateway()
      ..operationBody = confirmedSaleOperation();
    await pumpTradeScreen(
      tester,
      gateway: ready,
      statusGateway: ready,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'حلق');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
    await enterTradeField(
      tester,
      const Key('trade-tender-amount-0'),
      '4200.25',
    );
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-send-invoice')));
    await tester.pumpAndSettle();
    expect(find.text('مشاركة فاتورة PDF'), findsOneWidget);
    expect(find.textContaining('\u20663:04\u2069 م'), findsOneWidget);
    expect(find.textContaining('أكتوبر'), findsNothing);
    expect(find.textContaining('رقم العملية: 42'), findsOneWidget);
    expect(ready.operationIds, [tradeOperationId, tradeOperationId]);

    final reconciled = Batch2DispatchGateway()
      ..result = const FinancialUnknown()
      ..statusResult = const StatusUnknown()
      ..operationBody = confirmedSaleOperation(operationId: tradeCompletedId);
    await pumpTradeScreen(
      tester,
      gateway: reconciled,
      statusGateway: reconciled,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'حلق');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '10');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    reconciled.statusResult = const StatusCompleted(tradeCompletedId);
    await tester.tap(find.byKey(const Key('trade-check-status')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-send-invoice')));
    await tester.pumpAndSettle();
    expect(reconciled.operationIds, [tradeCompletedId, tradeCompletedId]);
    expect(find.textContaining('\u20663:04\u2069 م'), findsOneWidget);
    expect(find.textContaining('أكتوبر'), findsNothing);
  });

  testWidgets('purchase confirmation does not offer invoice dispatch', (
    tester,
  ) async {
    final gateway = Batch2DispatchGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-purchase-price'), '100');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '100');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
  });

  testWidgets('expense and scrap keep the stepped flow', (tester) async {
    final expense = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: expense,
      statusGateway: expense,
      kind: FinancialKind.expense,
    );
    expect(find.byKey(const Key('trade-customer-disclosure')), findsNothing);
    await enterTradeField(tester, const Key('trade-description'), 'نقل');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '10');
    await reviewTrade(tester);
    expect(find.byKey(const Key('trade-confirm')), findsOneWidget);
    expect(find.textContaining('لا يتغير الذهب'), findsOneWidget);

    final scrap = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: scrap,
      statusGateway: scrap,
      kind: FinancialKind.scrapSale,
    );
    expect(find.byKey(const Key('trade-select-كسر')), findsNothing);
    expect(find.byKey(const Key('trade-line-price-0')), findsOneWidget);
    await enterTradeField(tester, const Key('trade-grams-0'), '0.37');
    await tester.tap(find.byKey(const Key('trade-next')));
    await tester.pumpAndSettle();
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '125.25');
    await reviewTrade(tester);
    expect(find.textContaining('ينقص كسر عيار 18'), findsOneWidget);
    expect(find.textContaining('0.37 جرام'), findsWidgets);
  });

  testWidgets('exchange keeps the stepped sale form', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
      exchangeReturnPayload: const {'note': 'استبدال'},
    );
    expect(find.text('البديل في الاستبدال'), findsOneWidget);
    expect(find.byKey(const Key('trade-next')), findsOneWidget);
    expect(find.byKey(const Key('trade-customer-disclosure')), findsNothing);
    expect(find.byKey(const Key('trade-line-price-0')), findsNothing);
  });
}

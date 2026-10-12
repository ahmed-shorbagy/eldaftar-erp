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
    expect(find.textContaining('وزن الذهب: 1.26 جرام'), findsOneWidget);
    expect(
      find.textContaining('ينقص المخزون بمقدار 1.26 جرام (1,255 ملليجرام)'),
      findsOneWidget,
    );
    expect(gateway.keys, isEmpty);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(find.textContaining('وزن الذهب: 1.26 جرام'), findsOneWidget);
    expect(find.byKey(const Key('trade-send-invoice')), findsNothing);
    expect(gateway.keys, hasLength(1));
    expect(gateway.pendingExistedAtPost, isTrue);
    expect(gateway.payloads.single['total_piastres'], '420025');
    expect(
      (gateway.payloads.single['items'] as List).single['milligrams'],
      '1255',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional price components stay in the disclosure', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
    await revealTrade(tester, find.byKey(const Key('trade-price-disclosure')));
    await tester.tap(find.byKey(const Key('trade-price-disclosure')));
    await tester.pumpAndSettle();
    for (final entry in {
      'trade-base-price': '1000.01',
      'trade-workmanship': '50.02',
      'trade-discount': '20.04',
      'trade-other-charges': '10.03',
      'trade-other-label': 'تغليف',
      'trade-tender-amount-0': '1040.02',
    }.entries) {
      await enterTradeField(tester, Key(entry.key), entry.value);
    }
    await revealTrade(tester, find.byKey(const Key('trade-price-disclosure')));
    await tester.tap(find.byKey(const Key('trade-price-disclosure')));
    await tester.pumpAndSettle();
    await reviewTrade(tester);
    expect(find.text('المصنعية: 50.02'), findsOneWidget);
    expect(find.textContaining('الخصم: 20.04'), findsOneWidget);
    expect(gateway.payloads, isEmpty);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payloads.single['total_piastres'], '104002');
    expect(
      (gateway.payloads.single['pricing'] as Map)['discount_piastres'],
      '2004',
    );
  });

  testWidgets('purchase customer stays optional for partial and zero payment', (
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
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    expect(find.byKey(const Key('trade-customer-disclosure')), findsOneWidget);
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '10.000');
    await enterTradeField(tester, const Key('trade-purchase-price'), '60000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '20000');
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('trade-customer-disclosure')),
        matching: find.byKey(const Key('trade-customer-name')),
      ),
      findsOneWidget,
    );
    await enterTradeField(
      tester,
      const Key('trade-customer-name'),
      'تاجر تجريبي',
    );
    await reviewTrade(tester);
    expect(find.textContaining('يبقى مستحقاً للعميل: 40,000'), findsOneWidget);
    expect(find.textContaining('تنتقل الملكية إلى المتجر'), findsOneWidget);
    expect(find.textContaining('يزيد الذهب بمقدار 10.00 جرام'), findsOneWidget);
    expect(find.textContaining('العميل: تاجر تجريبي'), findsWidgets);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(partial.payloads.single['purchase_obligation_piastres'], '4000000');
    expect(partial.payloads.single['total_piastres'], '6000000');
    expect(partial.payloads.single['customer_name'], 'تاجر تجريبي');

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

  testWidgets('coin and bullion presets are editable and shop values win', (
    tester,
  ) async {
    final plain = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: plain,
      statusGateway: plain,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'سبائك');
    expect(find.text('سبيكة · 0.25'), findsOneWidget);
    expect(find.text('أوزان مقترحة — الوزن قابل للتعديل.'), findsOneWidget);
    await revealTrade(tester, find.byKey(const Key('trade-nominal-0-سبيكة')));
    await tester.tap(find.byKey(const Key('trade-nominal-0-سبيكة')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-grams-0')))
          .controller
          ?.text,
      '0.250',
    );
    await enterTradeField(tester, const Key('trade-grams-0'), '0.255');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '100');
    await reviewTrade(tester);
    expect(
      find.textContaining('بمقدار 0.26 جرام (255 ملليجرام)'),
      findsOneWidget,
    );
    expect(plain.payloads, isEmpty);
    await revealTrade(tester, find.byKey(const Key('trade-confirm')));
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    final postedItem = (plain.payloads.single['items'] as List).single as Map;
    expect(postedItem['item_name'], 'سبيكة');
    expect(postedItem['milligrams'], '255');

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
      denomPage: ReadPage.ready([
        tradeDenom(
          id: 'bar-1',
          label: 'سبيكة',
          nominalMilligrams: BigInt.from(5000),
        ),
      ], 'bars-2'),
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
    catalog.laterDenoms = {
      'bars-2': ReadPage.ready([
        tradeDenom(
          id: 'bar-2',
          label: 'سبيكة كبيرة',
          nominalMilligrams: BigInt.from(12500),
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
    expect(find.text('جنيه · 8.50'), findsOneWidget);
    expect(find.text('جنيه · 10.00'), findsNothing);
    expect(find.textContaining('عملة قديمة'), findsNothing);
    expect(find.textContaining('جنيه كبير'), findsNothing);
    await revealTrade(tester, find.byKey(const Key('trade-nominal-0-جنيه')));
    await tester.tap(find.byKey(const Key('trade-nominal-0-جنيه')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-grams-0')))
          .controller
          ?.text,
      '8.500',
    );
    await revealTrade(tester, find.byKey(const Key('trade-nominal-more-0')));
    await tester.tap(find.byKey(const Key('trade-nominal-more-0')));
    await tester.pumpAndSettle();
    expect(find.text('جنيه كبير · 15.50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-nominal-0-جنيه كبير')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-grams-0')))
          .controller
          ?.text,
      '15.500',
    );
    await enterTradeField(tester, const Key('trade-grams-0'), '15.125');
    await chooseTradeItem(tester, 'سبائك');
    expect(find.text('سبيكة · 5.00'), findsOneWidget);
    expect(find.text('سبيكة · 0.25'), findsNothing);
    await revealTrade(tester, find.byKey(const Key('trade-nominal-more-0')));
    await tester.tap(find.byKey(const Key('trade-nominal-more-0')));
    await tester.pumpAndSettle();
    expect(find.text('سبيكة كبيرة · 12.50'), findsOneWidget);
    expect(catalog.coinCursors, contains('coins-2'));
    expect(catalog.denomCursors, contains('bars-2'));
  });

  testWidgets('other selects catalog rows and still allows a manual name', (
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
    final loadsBefore = catalog.productCursors.length;
    await chooseTradeItem(tester, 'أخرى');
    expect(find.byKey(const Key('trade-catalog-table')), findsOneWidget);
    expect(find.byKey(const Key('trade-product-p1')), findsOneWidget);
    expect(find.byKey(const Key('trade-product-p2')), findsNothing);
    await revealTrade(tester, find.byKey(const Key('trade-product-p1')));
    await tester.tap(find.byKey(const Key('trade-product-p1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-select-name')))
          .controller
          ?.text,
      'خاتم ملكي',
    );
    await revealTrade(tester, find.byKey(const Key('trade-catalog-more')));
    await tester.tap(find.byKey(const Key('trade-catalog-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-product-p2')), findsOneWidget);
    await revealTrade(tester, find.byKey(const Key('trade-product-p2')));
    await tester.tap(find.byKey(const Key('trade-product-p2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-select-name')))
          .controller
          ?.text,
      'سلسلة نادرة',
    );
    final beforeInventory = catalog.productCursors.length;
    await revealTrade(tester, find.byKey(const Key('trade-open-inventory')));
    await tester.tap(find.byKey(const Key('trade-open-inventory')));
    await tester.pumpAndSettle();
    expect(find.text('رجوع من المخزون'), findsOneWidget);
    await tester.tap(find.text('رجوع من المخزون'));
    await tester.pumpAndSettle();
    expect(openedInventory, isTrue);
    expect(catalog.productCursors.length, greaterThan(beforeInventory));
    expect(loadsBefore, greaterThan(0));

    final manual = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: manual,
      statusGateway: manual,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'أخرى');
    expect(find.byKey(const Key('trade-catalog-manual')), findsOneWidget);
    expect(find.byKey(const Key('trade-catalog-table')), findsNothing);
    await enterTradeField(tester, const Key('trade-select-name'), 'قطعة خاصة');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '50');
    await reviewTrade(tester);
    expect(find.textContaining('قطعة خاصة'), findsWidgets);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(
      (manual.payloads.single['items'] as List).single['item_name'],
      'قطعة خاصة',
    );
  });

  testWidgets('catalog failure offers retry and keeps manual entry', (
    tester,
  ) async {
    final catalog = Batch2Catalog()..productFailures = 1;
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
      catalog: catalog,
    );
    await chooseTradeItem(tester, 'أخرى');
    expect(find.byKey(const Key('trade-catalog-retry')), findsOneWidget);
    catalog.productsPage = ReadPage.ready([
      tradeProduct(id: 'p1', name: 'خاتم ملكي'),
    ], null);
    await tester.tap(find.byKey(const Key('trade-catalog-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-product-p1')), findsOneWidget);
    await enterTradeField(tester, const Key('trade-select-name'), 'اسم يدوي');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('trade-select-name')))
          .controller
          ?.text,
      'اسم يدوي',
    );
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
    expect(
      find.text('تعذر تحميل بيانات الفاتورة. حاول مرة أخرى.'),
      findsOneWidget,
    );
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
    expect(find.text('إرسال عبر واتساب'), findsOneWidget);
    expect(find.textContaining('12 أكتوبر 2026، 15:04:05'), findsOneWidget);
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
    expect(find.textContaining('12 أكتوبر 2026، 15:04:05'), findsOneWidget);
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
    expect(find.byKey(const Key('trade-next')), findsOneWidget);
    expect(find.byKey(const Key('trade-line-price-0')), findsNothing);
    await chooseTradeItem(tester, 'كسر');
    await tester.tap(find.byKey(const Key('trade-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-line-price-0')), findsOneWidget);
    await enterTradeField(tester, const Key('trade-grams-0'), '0.375');
    await tester.tap(find.byKey(const Key('trade-next')));
    await tester.pumpAndSettle();
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '125.25');
    await tester.tap(find.byKey(const Key('trade-next')));
    await tester.pumpAndSettle();
    await reviewTrade(tester);
    expect(
      find.textContaining('ينقص الكسر بمقدار 0.38 جرام (375 ملليجرام)'),
      findsOneWidget,
    );
    expect(find.textContaining('وزن الذهب: 0.38 جرام'), findsOneWidget);
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

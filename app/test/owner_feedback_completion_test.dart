import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'financial_trade_screen_test.dart'
    show FakeFinancialGateway, pumpTrade, beginTrade, nextTrade;
import 'ledger_feed_merge_test.dart' show pageJson, line, shop;
import 'owner_feedback_ledger_review_test.dart' show ReviewGateway;

Future<void> host(
  WidgetTester tester, {
  String shop = 'feedback-shop',
  DailyLedgerView? view,
  VoidCallback? onSale,
  bool canReturn = false,
  ValueChanged<LedgerFeedLine>? onOperation,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConfirmedLedgerDashboard(
            shopId: shop,
            ledger: view ?? confirmedLedger(),
            onSale: onSale ?? () {},
            canReturn: canReturn,
            onOperation: onOperation,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'floating actions persist a clamped drag and offer a tap alternative',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      var sales = 0;
      await host(tester, onSale: () => sales++);
      final bubble = find.byKey(const Key('ledger-quick-actions'));
      final original = tester.getCenter(bubble);
      expect(
        tester.getRect(bubble).bottom,
        lessThanOrEqualTo(844 - 24 - 80 - 8),
      );
      await tester.drag(bubble, const Offset(900, -900));
      await tester.pumpAndSettle();
      final moved = tester.getCenter(bubble);
      expect(moved, isNot(original));
      expect(tester.getRect(bubble).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(bubble).right, lessThanOrEqualTo(390));
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'ledger_action_position_feedback-shop',
        ),
        ['1.0', '0.0'],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await host(tester, onSale: () => sales++);
      expect(tester.getCenter(bubble), moved);
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('موضع زر الإجراءات'));
      await tapVisible(tester, find.text('أسفل اليسار'));
      expect(tester.getCenter(bubble), original);
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('ledger-new-sale')));
      expect(sales, 1);
      expect(find.byKey(const Key('ledger-new-sale')), findsNothing);
      await host(tester, shop: 'another-shop');
      expect(tester.getCenter(bubble), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cash and gold can be hidden and metrics reordered across reopen',
    (tester) async {
      await host(tester);
      expect(find.byKey(const Key('ledger-metric-operations')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-more-metrics')));
      expect(find.byKey(const Key('ledger-detail-operations')), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('ledger-customize')));
      await tapVisible(tester, find.byKey(const Key('ledger-show-total_cash')));
      await tapVisible(tester, find.byKey(const Key('ledger-show-total_gold')));
      await tapVisible(tester, find.byTooltip('نقل المشتريات إلى الأعلى'));
      await tapVisible(tester, find.byTooltip('نقل المشتريات إلى الأعلى'));
      await tapVisible(tester, find.byTooltip('نقل المشتريات إلى الأعلى'));
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('ledger_layout_feedback-shop')!;
      expect(saved, contains('hidden:metric:total_cash'));
      expect(saved, contains('hidden:metric:total_gold'));
      expect(
        saved.where((value) => value.startsWith('metric:')).first,
        'metric:purchase',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await host(tester);
      expect(find.byKey(const Key('ledger-total-cash')), findsNothing);
      expect(find.byKey(const Key('ledger-total-gold')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-customize')));
      await tapVisible(tester, find.byKey(const Key('ledger-show-total_cash')));
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
    },
  );

  testWidgets(
    'empty returns stay absent and populated returns can be hidden independently',
    (tester) async {
      await host(tester);
      expect(find.text('دفتر المرتجعات'), findsNothing);
      expect(find.text('باقي الحركات'), findsNothing);
      final view = await ReviewGateway().ledger(
        callerUserId: 'synthetic-owner',
      );
      await host(tester, view: view);
      await tapVisible(tester, find.byKey(const Key('ledger-other-movements')));
      expect(find.byKey(const Key('ledger-filter-return')), findsOneWidget);
      expect(find.text('المسجل: مالك تجريبي'), findsWidgets);
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('ledger-customize')));
      await tapVisible(tester, find.byKey(const Key('ledger-show-returns')));
      await tester.pumpWidget(const SizedBox.shrink());
      await host(tester, view: view);
      expect(find.text('دفتر المرتجعات'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-other-movements')));
      expect(find.text('دفتر المرتجعات'), findsNothing);
      expect(find.byKey(const Key('ledger-filter-sale')), findsOneWidget);
      expect(find.byKey(const Key('ledger-filter-purchase')), findsOneWidget);
    },
  );

  testWidgets(
    'all eight metrics can be prioritized, hidden and restored per shop',
    (tester) async {
      await host(tester);
      expect(find.byKey(const Key('ledger-metric-sale_gold')), findsOneWidget);
      expect(find.byKey(const Key('ledger-metric-operations')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-customize')));
      for (var i = 0; i < 7; i++) {
        await tapVisible(tester, find.byTooltip('نقل عدد العمليات إلى الأعلى'));
      }
      await tapVisible(tester, find.byKey(const Key('ledger-show-sale_gold')));
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-metric-operations')), findsOneWidget);
      expect(find.byKey(const Key('ledger-metric-sale_gold')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await host(tester);
      expect(find.byKey(const Key('ledger-metric-operations')), findsOneWidget);
      expect(find.byKey(const Key('ledger-metric-sale_gold')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-more-metrics')));
      expect(find.byKey(const Key('ledger-detail-sale_gold')), findsNothing);
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      await host(tester, shop: 'other-shop');
      expect(find.byKey(const Key('ledger-metric-operations')), findsNothing);
      expect(find.byKey(const Key('ledger-metric-sale_gold')), findsOneWidget);
    },
  );

  testWidgets(
    'separate home journals retain item, actor, payment and date and open their own book',
    (tester) async {
      final view = await ReviewGateway().ledger(
        callerUserId: 'synthetic-owner',
      );
      await host(tester, view: view);
      for (final type in ['sale', 'purchase', 'return']) {
        expect(find.byKey(Key('ledger-journal-$type')), findsOneWidget);
      }
      final sales = find.byKey(const Key('ledger-journal-sale'));
      expect(
        find.descendant(of: sales, matching: find.text('بيع · عميل تجريبي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sales, matching: find.text('المسجل: مالك تجريبي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sales, matching: find.text('خاتم · عدد القطع: 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sales, matching: find.textContaining('كاش')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sales, matching: find.text('شراء · تاجر تجريبي')),
        findsNothing,
      );
      await tapVisible(
        tester,
        find.byKey(const Key('ledger-journal-all-purchase')),
      );
      final history = find.byKey(const Key('ledger-history'));
      expect(
        find.descendant(of: history, matching: find.text('شراء · تاجر تجريبي')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: history, matching: find.text('بيع · عميل تجريبي')),
        findsNothing,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('ledger-filter-purchase')))
            .selected,
        isTrue,
      );
    },
  );
  testWidgets(
    'return quick action selects an original trade without posting a financial operation',
    (tester) async {
      final view = await ReviewGateway().ledger(
        callerUserId: 'synthetic-owner',
      );
      final selected = <LedgerFeedLine>[];
      await host(
        tester,
        view: view,
        canReturn: true,
        onOperation: selected.add,
      );
      await tapVisible(tester, find.byKey(const Key('ledger-quick-actions')));
      await tapVisible(tester, find.byKey(const Key('ledger-more-actions')));
      await tapVisible(tester, find.byKey(const Key('ledger-new-return')));
      final history = find.byKey(const Key('ledger-history'));
      expect(find.text('اختر العملية الأصلية للمرتجع'), findsOneWidget);
      expect(
        find.descendant(
          of: history,
          matching: find.text('مرتجع بيع · عميل تجريبي'),
        ),
        findsNothing,
      );
      expect(selected, isEmpty);
      await tapVisible(
        tester,
        find.descendant(of: history, matching: find.text('بيع · عميل تجريبي')),
      );
      expect(selected.single.kind, 'sale');
      expect(history, findsNothing);
      await host(
        tester,
        view: view,
        canReturn: false,
        onOperation: selected.add,
      );
      await tapVisible(tester, find.byKey(const Key('ledger-quick-actions')));
      expect(find.byKey(const Key('ledger-more-actions')), findsNothing);
      expect(find.byKey(const Key('ledger-new-return')), findsNothing);
    },
  );
  testWidgets(
    'standard item selection and anonymous unpaid purchase reach server confirmation',
    (tester) async {
      final gateway = FakeFinancialGateway();
      await pumpTrade(tester, gateway, FinancialKind.purchase);
      expect(find.byKey(const Key('trade-select-غويشة')), findsOneWidget);
      expect(find.byKey(const Key('trade-select-دبلة')), findsOneWidget);
      expect(find.byKey(const Key('trade-select-name')), findsNothing);
      await beginTrade(tester);
      expect(find.byKey(const Key('trade-name-0')), findsNothing);
      await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
      await nextTrade(tester);
      await tester.ensureVisible(find.byKey(const Key('trade-purchase-price')));
      await tester.enterText(
        find.byKey(const Key('trade-purchase-price')),
        '60000.25',
      );
      await tester.ensureVisible(
        find.byKey(const Key('trade-tender-amount-0')),
      );
      await tester.enterText(
        find.byKey(const Key('trade-tender-amount-0')),
        '',
      );
      await nextTrade(tester);
      await tapVisible(tester, find.byKey(const Key('trade-review')));
      expect(find.textContaining('60,000.25'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('trade-confirm')));
      expect(gateway.payloads.single['customer_name'], '');
      expect(
        gateway.payloads.single['purchase_obligation_piastres'],
        '6000025',
      );
      expect(find.byKey(const Key('trade-success')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'journal codec preserves item counts without accepting rounded or malformed counts',
    () {
      final json = pageJson(
        direction: 'desc',
        limit: 1,
        items: [line(1, kind: 'sale')],
      );
      final entry = (json['items'] as List).single as Map<String, Object?>;
      entry.addAll({'item_summary': 'خاتم، سلسلة', 'piece_count': '2'});
      final row = parseLedgerOperationPage(
        json,
        expectedShopId: shop,
      ).items.single;
      expect(row.itemSummary, 'خاتم، سلسلة');
      expect(row.pieceCount, '2');
      entry['piece_count'] = '18446744073709551614';
      entry['item_summary'] = List.filled(200, '💍').join();
      expect(
        parseLedgerOperationPage(
          json,
          expectedShopId: shop,
        ).items.single.pieceCount,
        '18446744073709551614',
      );
      entry['piece_count'] = '2.5';
      expect(
        () => parseLedgerOperationPage(json, expectedShopId: shop),
        throwsFormatException,
      );
      entry['piece_count'] = '2';
      entry['item_summary'] = 'خاتم\nسلسلة';
      expect(
        () => parseLedgerOperationPage(json, expectedShopId: shop),
        throwsFormatException,
      );
      expect(
        parseLedgerOperationPage(
          pageJson(
            direction: 'desc',
            limit: 1,
            items: [line(2, kind: 'sale')],
          ),
          expectedShopId: shop,
        ).items.single.itemSummary,
        isNull,
      );
    },
  );
}

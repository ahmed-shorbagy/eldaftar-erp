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
    show FakeFinancialGateway, pumpTrade, nextTrade;
import 'ledger_feed_merge_test.dart' show pageJson, line, shop;
import 'owner_feedback_ledger_review_test.dart' show ReviewGateway;

Future<void> host(
  WidgetTester tester, {
  String shop = 'feedback-shop',
  DailyLedgerView? view,
  VoidCallback? onSale,
  VoidCallback? onExpense,
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
            onExpense: onExpense ?? () {},
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
      await host(tester, onExpense: () => sales++);
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
      await host(tester, onExpense: () => sales++);
      expect(tester.getCenter(bubble), moved);
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('موضع زر الإجراءات'));
      await tapVisible(tester, find.text('أسفل اليسار'));
      expect(tester.getCenter(bubble), original);
      await tester.tap(bubble);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('ledger-new-expense')));
      expect(sales, 1);
      expect(find.byKey(const Key('ledger-new-expense')), findsNothing);
      await host(tester, shop: 'another-shop');
      expect(tester.getCenter(bubble), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'six selected metrics persist per shop with per-karat replacements',
    (tester) async {
      await host(tester);
      expect(find.byKey(const Key('ledger-metric-expense')), findsOneWidget);
      expect(find.byKey(const Key('ledger-total-gold')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('ledger-customize')));
      await tapVisible(
        tester,
        find.byKey(const Key('ledger-slot-0-total_cash')),
      );
      await tester.tap(find.text('مبيعات عيار 18').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-total-cash')), findsNothing);
      expect(
        find.byKey(const Key('ledger-metric-sale_karat_18')),
        findsOneWidget,
      );
      final saved = (await SharedPreferences.getInstance()).getStringList(
        'ledger_layout_feedback-shop',
      )!;
      expect(saved, contains('metric:sale_karat_18'));
      expect(saved.where((value) => value.startsWith('metric:')), hasLength(6));
      await tester.pumpWidget(const SizedBox.shrink());
      await host(tester);
      expect(find.byKey(const Key('ledger-total-cash')), findsNothing);
      await host(tester, shop: 'other-shop');
      expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
    },
  );

  testWidgets(
    'empty returns show a count row and returns can be hidden independently',
    (tester) async {
      await host(tester);
      expect(find.byKey(const Key('ledger-book-returns')), findsOneWidget);
      expect(find.text('باقي الحركات'), findsNothing);
      final view = await ReviewGateway().ledger(
        callerUserId: 'synthetic-owner',
      );
      await host(tester, view: view);
      await tapVisible(tester, find.byKey(const Key('ledger-other-movements')));
      expect(find.byKey(const Key('ledger-filter-return')), findsOneWidget);
      expect(find.textContaining('اسم البائع: مالك تجريبي'), findsWidgets);
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
    'legacy hidden operations migrate to six current figures per shop',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ledger_layout_feedback-shop': [
          'metrics',
          'activity',
          'metric:operations',
          'metric:total_cash',
          'metric:total_gold',
          'metric:sale',
          'metric:purchase',
          'metric:sale_gold',
          'metric:purchase_gold',
          'hidden:metric:expense',
        ],
      });
      await host(tester);
      expect(find.byKey(const Key('ledger-metric-operations')), findsNothing);
      expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
      expect(find.byKey(const Key('ledger-metric-sale_gold')), findsOneWidget);
      expect(find.byKey(const Key('ledger-metric-expense')), findsNothing);
      await host(tester, shop: 'other-shop');
      expect(find.byKey(const Key('ledger-metric-expense')), findsOneWidget);
      expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
    },
  );

  testWidgets('home journals show seller and time without weight or payment', (
    tester,
  ) async {
    final view = await ReviewGateway().ledger(callerUserId: 'synthetic-owner');
    await host(tester, view: view);
    for (final type in ['sale', 'purchase']) {
      expect(find.byKey(Key('ledger-journal-$type')), findsOneWidget);
    }
    final sales = find.byKey(const Key('ledger-journal-sale'));
    expect(
      find.descendant(of: sales, matching: find.text('بيع · عميل تجريبي')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: sales,
        matching: find.text('اسم البائع: مالك تجريبي'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sales, matching: find.text('خاتم · عدد القطع: 1')),
      findsNothing,
    );
    expect(
      find.descendant(of: sales, matching: find.textContaining('كاش')),
      findsNothing,
    );
    expect(find.textContaining('1.830'), findsNothing);
    await tapVisible(
      tester,
      find.byKey(const Key('ledger-journal-details-sale')),
    );
    expect(
      find.descendant(of: sales, matching: find.text('خاتم · عدد القطع: 1')),
      findsOneWidget,
    );
    await tapVisible(
      tester,
      find.byKey(const Key('ledger-journal-all-purchase')),
    );
    final history = find.byKey(const Key('ledger-history'));
    expect(
      find.descendant(
        of: history,
        matching: find.byKey(
          const Key(
            'ledger-open-purchase-bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: history,
        matching: find.byKey(
          const Key('ledger-open-sale-bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
        ),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('ledger-filter-purchase')))
          .selected,
      isTrue,
    );
  });
  testWidgets(
    'retired refund action stays absent even with a legacy return-capable gateway',
    (tester) async {
      final view = await ReviewGateway().ledger(
        callerUserId: 'synthetic-owner',
      );
      await host(tester, view: view, canReturn: true, onOperation: (_) {});
      await tapVisible(tester, find.byKey(const Key('ledger-quick-actions')));
      expect(find.byKey(const Key('ledger-new-return')), findsNothing);
    },
  );
  testWidgets(
    'standard item selection and anonymous unpaid purchase reach server confirmation',
    (tester) async {
      final gateway = FakeFinancialGateway();
      await pumpTrade(tester, gateway, FinancialKind.purchase);
      await tapVisible(tester, find.byKey(const Key('trade-select-أخرى')));
      expect(find.byKey(const Key('trade-other-grid')), findsOneWidget);
      expect(find.byKey(const Key('trade-select-غويشة')), findsOneWidget);
      expect(find.byKey(const Key('trade-select-دبلة')), findsOneWidget);
      expect(find.byKey(const Key('trade-select-name')), findsNothing);
      expect(find.byKey(const Key('trade-catalog-table')), findsNothing);
      expect(find.byKey(const Key('trade-open-inventory')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('trade-select-دبلة')));
      expect(find.byKey(const Key('trade-name-0')), findsNothing);
      await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
      await nextTrade(tester);
      await tester.dragUntilVisible(
        find.byKey(const Key('trade-purchase-price')),
        find.byType(ListView),
        const Offset(0, -200),
      );
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

// ADR 0033 staff ledger (2026-11-15): the employee read model parses, the
// shop cash never shows for an employee, and controls follow the grants.
import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_control_access.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_home_metrics.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_date_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shopId = '1c9c91c2-0e66-46f5-bdb7-eb511eed00ae';

// Captured from development for the test employee after
// 20261115100000_employee_ledger_reads (server_now kept as returned).
const _employeeSale =
    '{"kind": "sale", "karat": 18, "has_note": false, "label_ar": "بيع", "is_return": false, "party_name": null, "occurred_at": "2026-11-15T08:42:38.407178+00:00", "party_phone": null, "piece_count": "1", "item_summary": "خاتم", "operation_id": "4b47acb2-6a32-43cb-8f78-667d0a6471a2", "total_pounds": "10000.00", "weight_grams": "4.000", "is_daily_note": false, "payment_label": "كاش", "shop_sequence": "7", "occurred_at_shop": "2026-11-15T10:42:38", "occurred_at_cairo": "2026-11-15T10:42:38", "actor_display_name": "موظف تجربة"}';
const _ownSummary =
    '{"sale_count": 1, "repair_count": 0, "expense_count": 0, "sale_piastres": "1000000", "gold_by_bucket": [{"kind": "sale", "count": "1", "karat": 18, "category": "worked_jewelry", "milligrams": "4000"}], "purchase_count": 0, "repair_piastres": "0", "expense_piastres": "0", "purchase_piastres": "0"}';
const _employeeHome =
    '{"cash": [{"method": "cash", "pounds": "0.00", "archived": false, "label_ar": "نقدي", "piastres": "0"}, {"method": "instant_transfer", "pounds": "0.00", "archived": false, "label_ar": "انستا", "piastres": "0"}, {"method": "wallet", "pounds": "0.00", "archived": false, "label_ar": "محفظة", "piastres": "0"}, {"method": "card", "pounds": "0.00", "archived": false, "label_ar": "فيزا", "piastres": "0"}], "feed": [$_employeeSale], "scrap": [], "state": "confirmed", "stock": [], "day_reset": false, "feed_page": {"limit": 100, "has_more": false, "direction": "desc", "server_sequence": "8", "snapshot_sequence": "8", "next_before_sequence": null}, "can_confirm": false, "day_summary": $_ownSummary, "business_day": {"id": "29eab27b-9793-4f40-8e36-1470b69c40cc", "opened_at": "2026-11-15T08:17:32.311884+00:00", "business_date": "2026-11-15"}, "journal_context": {"day_ids": ["29eab27b-9793-4f40-8e36-1470b69c40cc"], "note_count": 0, "server_now": "2026-11-15T08:52:49.954157Z", "return_count": 0, "business_date": "2026-11-15", "next_midnight_at": "2026-11-15T22:00:00.000000Z"}, "entitlement_status": "active", "read_model_version": 3, "trade_change_sequence": "0", "last_closed_business_date": "2026-11-15"}';
const _employeeDate =
    '{"day_ids": ["8d119951-8cad-4ca3-80ab-7cfde988d1df", "29eab27b-9793-4f40-8e36-1470b69c40cc"], "shop_id": "$_shopId", "feed_page": {"items": [$_employeeSale], "limit": 100, "day_id": null, "shop_id": "$_shopId", "has_more": false, "direction": "desc", "server_sequence": "8", "snapshot_sequence": "8", "next_after_sequence": null, "next_before_sequence": null}, "day_summary": $_ownSummary, "server_date": "2026-11-15", "business_date": "2026-11-15", "read_model_version": 1}';

ShopAccount _shop(String role, Set<ShopPermission> grants) => ShopAccount(
  id: _shopId,
  name: 'محل',
  role: role,
  entitlement: ShopEntitlement.active,
  grants: grants,
);

Future<void> _pump(
  WidgetTester tester,
  DailyLedgerView view, {
  required bool employee,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 900),
  bool dayClosed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConfirmedLedgerDashboard(
                ledger: view,
                shopId: _shopId,
                dayClosed: dayClosed,
                hideShopBalances: employee,
                ownerControls: !employee,
                onDailyNotes: employee ? null : () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the employee home read model from the server parses', () {
    final view = parseDailyLedger(jsonDecode(_employeeHome));
    expect(view.state, 'confirmed');
    expect(view.feed, hasLength(1));
    expect(view.feed.single.actorDisplayName, 'موظف تجربة');
    expect(view.stock, isEmpty);
    expect(view.scrap, isEmpty);
    expect(view.cash.every((line) => line.piastres == '0'), isTrue);
    expect(view.daySummary!.salePiastres, '1000000');
    expect(view.daySummary!.saleCount, 1);
  });

  test('the employee date read from the server parses', () {
    final snapshot = parseLedgerDate(jsonDecode(_employeeDate), _shopId);
    expect(snapshot.page.items, hasLength(1));
    expect(snapshot.summary.salePiastres, '1000000');
  });

  test('ledger controls follow the member grants', () {
    final owner = LedgerControlAccess.of(_shop('owner', const {}));
    final seller = LedgerControlAccess.of(
      _shop('employee', const {ShopPermission.sale}),
    );
    final partner = LedgerControlAccess.of(
      _shop('partner', ShopPermission.values.toSet()),
    );
    final fullEmployee = LedgerControlAccess.of(
      _shop('employee', ShopPermission.values.toSet()),
    );

    for (final access in [owner]) {
      expect(access.sale && access.purchase && access.expense, isTrue);
      expect(access.openDay && access.closeDay && access.dailyNotes, isTrue);
      expect(access.cashTransfer && access.scrapToStock, isTrue);
      expect(access.hidesShopBalances, isFalse);
    }

    expect(seller.sale, isTrue);
    expect(seller.scrapSale, isTrue);
    expect(seller.customerReturn, isTrue);
    expect(seller.purchase, isFalse);
    expect(seller.expense, isFalse);
    expect(seller.sendInvoice, isFalse);
    expect(seller.pendingInvoices, isFalse);
    expect(seller.archive, isFalse);
    expect(seller.openDay || seller.closeDay || seller.dailyNotes, isFalse);
    expect(seller.hidesShopBalances, isTrue);

    expect(partner.purchase && partner.expense && partner.archive, isTrue);
    expect(partner.cashTransfer && partner.scrapToStock, isTrue);
    expect(partner.openDay || partner.closeDay || partner.dailyNotes, isFalse);
    expect(partner.hidesShopBalances, isFalse);

    // Even with every grant, an employee gets nothing that needs balances.
    expect(fullEmployee.expense, isTrue);
    expect(fullEmployee.cashTransfer, isFalse);
    expect(fullEmployee.scrapToStock, isFalse);
    expect(fullEmployee.hidesShopBalances, isTrue);
  });

  for (final brightness in Brightness.values) {
    for (final size in const [
      Size(320, 900),
      Size(390, 900),
      Size(1240, 900),
    ]) {
      testWidgets(
        'an employee never sees the shop cash tile (${brightness.name}, ${size.width.toInt()})',
        (tester) async {
          final view = parseDailyLedger(jsonDecode(_employeeHome));
          await _pump(
            tester,
            view,
            employee: true,
            brightness: brightness,
            size: size,
          );
          expect(find.byKey(const Key('ledger-total-cash')), findsNothing);
          expect(find.byKey(const Key('ledger-cash-methods')), findsNothing);
          expect(find.text('الملاحظات'), findsNothing);
          expect(find.textContaining('خاتم'), findsWidgets);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const Key('ledger-customize')));
          await tester.pumpAndSettle();
          expect(find.text(ledgerMetricLabel('total_cash')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the owner keeps the cash tile and the notes book', (
    tester,
  ) async {
    final view = parseDailyLedger(jsonDecode(_employeeHome));
    await _pump(tester, view, employee: false);
    expect(find.byKey(const Key('ledger-total-cash')), findsOneWidget);
    expect(find.text('الملاحظات'), findsOneWidget);
  });

  testWidgets('a closed day tells staff that the owner opens the next day', (
    tester,
  ) async {
    final view = parseDailyLedger(jsonDecode(_employeeHome));
    await _pump(tester, view, employee: true, dayClosed: true);
    expect(
      find.text('يفتح مالك المحل يوم العمل الجديد، ثم يمكنك التسجيل.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ledger-day-closed-open')), findsNothing);
  });
}

// Visual review captures for the staff ledger (ADR 0033, 2026-11-15):
// an employee with the sale grant, a partner, and the owner, Arabic RTL,
// light and dark, at 320, 390 and 1440 px. Writes PNGs to tmp/staff-ledger.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'owner_feedback_ledger_review_test.dart' show ReviewGateway;

// The employee read model as development returns it (see employee_ledger_test).
const _employeeHome =
    '{"cash": [{"method": "cash", "pounds": "0.00", "archived": false, "label_ar": "نقدي", "piastres": "0"}, {"method": "instant_transfer", "pounds": "0.00", "archived": false, "label_ar": "انستا", "piastres": "0"}, {"method": "wallet", "pounds": "0.00", "archived": false, "label_ar": "محفظة", "piastres": "0"}, {"method": "card", "pounds": "0.00", "archived": false, "label_ar": "فيزا", "piastres": "0"}], "feed": [{"kind": "sale", "karat": 18, "has_note": false, "label_ar": "بيع", "is_return": false, "party_name": null, "occurred_at": "2026-11-15T08:42:38.407178+00:00", "party_phone": null, "piece_count": "1", "item_summary": "خاتم", "operation_id": "4b47acb2-6a32-43cb-8f78-667d0a6471a2", "total_pounds": "10000.00", "weight_grams": "4.000", "is_daily_note": false, "payment_label": "كاش", "shop_sequence": "7", "occurred_at_shop": "2026-11-15T10:42:38", "occurred_at_cairo": "2026-11-15T10:42:38", "actor_display_name": "موظف تجربة"}], "scrap": [], "state": "confirmed", "stock": [], "day_reset": false, "feed_page": {"limit": 100, "has_more": false, "direction": "desc", "server_sequence": "8", "snapshot_sequence": "8", "next_before_sequence": null}, "can_confirm": false, "day_summary": {"sale_count": 1, "repair_count": 0, "expense_count": 0, "sale_piastres": "1000000", "gold_by_bucket": [{"kind": "sale", "count": "1", "karat": 18, "category": "worked_jewelry", "milligrams": "4000"}], "purchase_count": 0, "repair_piastres": "0", "expense_piastres": "0", "purchase_piastres": "0"}, "business_day": {"id": "29eab27b-9793-4f40-8e36-1470b69c40cc", "opened_at": "2026-11-15T08:17:32.311884+00:00", "business_date": "2026-11-15"}, "journal_context": {"day_ids": ["29eab27b-9793-4f40-8e36-1470b69c40cc"], "note_count": 0, "server_now": "2026-11-15T08:52:49.954157Z", "return_count": 0, "business_date": "2026-11-15", "next_midnight_at": "2026-11-15T22:00:00.000000Z"}, "entitlement_status": "active", "read_model_version": 3, "trade_change_sequence": "0", "last_closed_business_date": "2026-11-15"}';

class _EmployeeGateway extends ReviewGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      parseDailyLedger(jsonDecode(_employeeHome));
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('staff-ledger-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../tmp/staff-ledger/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  final members = <(String, ShopAccount, ReviewGateway Function())>[
    (
      'employee',
      const ShopAccount(
        id: 'shop-1',
        name: 'متجر تجريبي',
        role: 'employee',
        entitlement: ShopEntitlement.active,
        grants: {ShopPermission.sale},
      ),
      _EmployeeGateway.new,
    ),
    (
      'partner',
      ShopAccount(
        id: 'shop-1',
        name: 'متجر تجريبي',
        role: 'partner',
        entitlement: ShopEntitlement.active,
        grants: ShopPermission.values.toSet(),
      ),
      ReviewGateway.new,
    ),
    (
      'owner',
      const ShopAccount(
        id: 'shop-1',
        name: 'متجر تجريبي',
        role: 'owner',
        entitlement: ShopEntitlement.active,
      ),
      ReviewGateway.new,
    ),
  ];

  for (final (member, shop, gateway) in members) {
    for (final width in [320.0, 390.0, 1440.0]) {
      for (final dark in [false, true]) {
        testWidgets('staff ledger $member ${dark ? 'dark' : 'light'} $width', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('staff-ledger-capture'),
              child: MaterialApp(
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                home: ShopWorkspace(
                  shop: shop,
                  gateway: gateway(),
                  store: MemoryStore(),
                  userId: '$member-1',
                  onSignOut: () async {},
                  onToggleTheme: (_) async {},
                ),
              ),
            ),
          );
          final label = '$member-${dark ? 'dark' : 'light'}-${width.toInt()}';
          await _capture(tester, 'ledger-$label');
          final cashTile = find.byKey(const Key('ledger-total-cash'));
          if (member == 'employee') {
            expect(cashTile, findsNothing);
          } else {
            expect(cashTile, findsOneWidget);
          }
          final quick = find.byKey(const Key('ledger-quick-actions'));
          if (quick.evaluate().isNotEmpty) {
            await tester.tap(quick);
            await _capture(tester, 'actions-$label');
            final close = find.byKey(const Key('ledger-close-day'));
            if (member == 'owner') {
              expect(close, findsWidgets);
            } else {
              expect(close, findsNothing);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

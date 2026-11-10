import 'package:eldafttar/src/features/customers/domain/phone_countries.dart';
import 'package:eldafttar/src/features/customers/domain/shop_phone_country.dart';
import 'package:eldafttar/src/features/customers/presentation/customer_phone_field.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'batch2_trade_support.dart';
import 'repair_widget_test.dart'
    show FakeRepairs, MemoryLocker, pumpRepair, shopId;

/// ADR 0044 C-D10: an empty customer phone starts on the shop owner's
/// country in every form; a stored number keeps its own country.
void main() {
  tearDown(ShopPhoneCountryCache.clear);

  test('owner phone sets the shop default; no phone falls back to Egypt', () {
    ShopPhoneCountryCache.remember('shop-sa', '+966501234567');
    ShopPhoneCountryCache.remember('shop-eg', null);
    expect(ShopPhoneCountryCache.forShop('shop-sa').nameAr, 'السعودية');
    expect(ShopPhoneCountryCache.forShop('shop-eg'), egypt);
    expect(ShopPhoneCountryCache.forShop('unknown'), egypt);
  });

  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CustomerPhoneField(
              controller: controller,
              fieldKey: const Key('phone'),
              label: 'الهاتف',
              defaultCountry: ShopPhoneCountryCache.forShop('shop-sa'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an empty field starts on the owner country', (tester) async {
    ShopPhoneCountryCache.remember('shop-sa', '+966501234567');
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpField(tester, controller);
    expect(find.text('+966'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone')), '501234567');
    expect(controller.text, '+966501234567');
  });

  testWidgets('a stored Egyptian number keeps Egypt', (tester) async {
    ShopPhoneCountryCache.remember('shop-sa', '+966501234567');
    final controller = TextEditingController(text: '+201012345678');
    addTearDown(controller.dispose);
    await pumpField(tester, controller);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('+966'), findsNothing);
  });

  testWidgets('the full-page sale form uses the owner country', (tester) async {
    // pumpTradeScreen opens FinancialTradeScreen directly (shop-1), the
    // path the ledger home uses; it passes no defaultPhoneCountry.
    ShopPhoneCountryCache.remember('shop-1', '+966501234567');
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
      size: const Size(390, 900),
    );
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
    await tester.pumpAndSettle();
    final country = tester.widget<DropdownButton<PhoneCountry>>(
      find.byKey(const Key('[<\'trade-customer-phone\'>]-country')),
    );
    expect(country.value?.nameAr, 'السعودية');
  });

  testWidgets('repair intake uses the owner country and stores E.164', (
    tester,
  ) async {
    ShopPhoneCountryCache.remember(shopId, '+966501234567');
    await pumpRepair(tester, gateway: FakeRepairs(), locker: MemoryLocker());
    await tester.tap(find.byKey(const Key('repair-new')));
    await tester.pumpAndSettle();
    final country = tester.widget<DropdownButton<PhoneCountry>>(
      find.byKey(const Key('[<\'repair-phone\'>]-country')),
    );
    expect(country.value?.nameAr, 'السعودية');
  });
}

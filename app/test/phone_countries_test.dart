import 'package:eldafttar/src/features/customers/domain/phone_countries.dart';
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

  test('phone checks cover Egypt, Saudi Arabia, and international entry', () {
    expect(
      (checkCustomerPhone(egypt, '0101234567') as PhoneRejected).message,
      'الرقم ناقص 1 رقم.',
    );
    expect(
      (checkCustomerPhone(egypt, '01712345678') as PhoneRejected).message,
      'رقم الموبايل المصري يبدأ بـ 010 أو 011 أو 012 أو 015.',
    );
    expect(
      (checkCustomerPhone(egypt, '01012345678') as PhoneAccepted).e164,
      '+201012345678',
    );
    final saudi = phoneCountries[1];
    expect(
      (checkCustomerPhone(saudi, '512345678') as PhoneAccepted).e164,
      '+966512345678',
    );
    final detected = checkCustomerPhone(egypt, '+966512345678');
    expect((detected as PhoneAccepted).e164, '+966512345678');
    expect(
      (checkCustomerPhone(egypt, '٠١٠١٢٣٤٥٦٧٨') as PhoneAccepted).e164,
      '+201012345678',
    );
    expect(splitCustomerPhone('01012345678').country.dial, '20');
    expect(splitCustomerPhone('01012345678').national, '1012345678');
  });

  testWidgets('a short sale phone cannot reach review', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.00');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '100');
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
    await tester.pumpAndSettle();
    await enterTradeField(
      tester,
      const Key('trade-customer-phone'),
      '0101234567',
    );
    await reviewTrade(tester);
    expect(find.text('الرقم ناقص 1 رقم.'), findsOneWidget);
    expect(find.byKey(const Key('trade-confirm')), findsNothing);
    expect(gateway.payloads, isEmpty);
  });

  Future<void> typePhoneThenCollapse(
    WidgetTester tester,
    Batch2TradeGateway gateway,
    String phone,
  ) async {
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.00');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '100');
    final disclosure = find.byKey(const Key('trade-customer-disclosure'));
    await revealTrade(tester, disclosure);
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
    await enterTradeField(tester, const Key('trade-customer-phone'), phone);
    final header = find.text('تفاصيل العميل (اختياري)');
    await revealTrade(tester, header);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-customer-phone')), findsNothing);
  }

  testWidgets('a phone typed before collapsing the section is still saved', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await typePhoneThenCollapse(tester, gateway, '01012345678');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payloads.single['customer_phone'], '+201012345678');
  });

  testWidgets('a short phone in a collapsed section still blocks review', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await typePhoneThenCollapse(tester, gateway, '010123');
    await reviewTrade(tester);
    expect(find.text('راجع رقم الهاتف.'), findsOneWidget);
    expect(find.byKey(const Key('trade-confirm')), findsNothing);
    expect(gateway.payloads, isEmpty);
  });
}

import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';

void main() {
  test('ordered karats put 18 and 21 first and 22 and 14 last', () {
    expect(orderedKarats({14, 18, 21, 22}), [18, 21, 22, 14]);
    expect(orderedKarats(ScrapKarats.allowed), [18, 21, 24, 22, 14]);
  });

  testWidgets('a purchase scrap row lists 18 first and 14 last', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
    );
    await chooseTradeItem(tester, 'كسر');
    await tester.tap(find.byKey(const Key('trade-karat-0-scrap-18')));
    await tester.pumpAndSettle();
    final values = tester
        .widgetList<DropdownMenuItem<int>>(find.byType(DropdownMenuItem<int>))
        .map((item) => item.value)
        .toList();
    expect(values.first, 18);
    expect(values.last, 14);
    expect(values, containsAllInOrder([18, 21, 24, 22, 14]));
  });
}

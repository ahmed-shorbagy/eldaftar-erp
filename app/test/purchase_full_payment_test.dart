import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:eldafttar/src/theme/amount_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'financial_trade_screen_test.dart';

const _ring = FinancialItemInput(
  category: 'scrap',
  karat: 21,
  grams: '10.000',
  count: '',
  name: 'خاتم',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a purchase with no tenders is invalid', () {
    final draft = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: const [_ring],
      tenders: const [],
    );
    expect(draft.issue, FinancialIssue.invalidTender);
  });

  test('a purchase paid less than the total is a mismatch', () {
    final draft = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: const [_ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '20000'),
      ],
    );
    expect(draft.issue, FinancialIssue.tenderMismatch);
  });

  test('a fully paid purchase has no seller payable', () {
    final draft = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: const [_ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '40000'),
        FinancialTenderInput(
          method: CashMethod.instantTransfer,
          pounds: '20000',
        ),
      ],
    );
    expect(draft.isValid, isTrue);
    final json = draft.draft!.toJson();
    expect(json.containsKey('purchase_obligation_piastres'), isFalse);
    final tenders = json['tenders'] as List;
    var sum = BigInt.zero;
    for (final tender in tenders) {
      sum += BigInt.parse((tender as Map)['piastres'] as String);
    }
    expect(sum.toString(), json['total_piastres']);
  });

  testWidgets('purchase review shows the cash decrease and no price field', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    await pumpTrade(tester, gateway, FinancialKind.purchase);
    expect(find.byKey(const Key('trade-purchase-price')), findsNothing);
    await beginTrade(tester);
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '2.000');
    await nextTrade(tester);
    await tester.dragUntilVisible(
      find.byKey(const Key('trade-tender-amount-0')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '50000',
    );
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('تنقص النقدية: ${displayPounds('50000.00')}'),
      findsOneWidget,
    );
  });

  for (final code in ['purchase_must_be_paid', 'purchase_jewelry_is_scrap']) {
    testWidgets('server code $code is shown in Arabic', (tester) async {
      final gateway = FakeFinancialGateway()..result = FinancialRejected(code);
      await pumpTrade(tester, gateway, FinancialKind.purchase);
      await beginTrade(tester);
      await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.000');
      await nextTrade(tester);
      await tester.dragUntilVisible(
        find.byKey(const Key('trade-tender-amount-0')),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.enterText(
        find.byKey(const Key('trade-tender-amount-0')),
        '1000',
      );
      await tester.ensureVisible(find.byKey(const Key('trade-review')));
      await tester.tap(find.byKey(const Key('trade-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trade-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          code == 'purchase_must_be_paid'
              ? 'يجب دفع سعر الشراء كاملًا. تأكد أن مجموع طرق الدفع يساوي الإجمالي.'
              : 'المشغولات المشتراة تُسجَّل كسرًا. حدّث التطبيق وأعد المحاولة.',
        ),
        findsOneWidget,
      );
    });
  }
}

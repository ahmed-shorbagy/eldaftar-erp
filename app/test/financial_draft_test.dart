import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ring = FinancialItemInput(
    category: 'worked_jewelry',
    karat: 18,
    grams: '1.830',
    count: '1',
    name: 'خاتم',
  );

  test('sale keeps integer piastres and three-decimal gram precision', () {
    final result = FinancialDraft.compose(
      kind: FinancialKind.sale,
      totalPounds: '4200.25',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '200.25'),
        FinancialTenderInput(method: CashMethod.card, pounds: '4000'),
      ],
    );
    expect(result.isValid, isTrue);
    final json = result.draft!.toJson();
    expect(json['total_piastres'], '420025');
    expect((json['items'] as List).single['milligrams'], '1830');
    expect((json['tenders'] as List).last['piastres'], '400000');
  });

  test('tender mismatch and duplicate methods cannot post', () {
    final mismatch = FinancialDraft.compose(
      kind: FinancialKind.sale,
      totalPounds: '100',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '99'),
      ],
    );
    expect(mismatch.issue, FinancialIssue.tenderMismatch);
    final duplicate = FinancialDraft.compose(
      kind: FinancialKind.sale,
      totalPounds: '100',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '50'),
        FinancialTenderInput(method: CashMethod.cash, pounds: '50'),
      ],
    );
    expect(duplicate.issue, FinancialIssue.invalidTender);
  });

  test('sale rejects a fourth gram decimal and purchase permits scrap', () {
    final invalid = FinancialDraft.compose(
      kind: FinancialKind.sale,
      totalPounds: '100',
      items: [
        const FinancialItemInput(
          category: 'worked_jewelry',
          karat: 18,
          grams: '1.8301',
          count: '1',
          name: 'خاتم',
        ),
      ],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '100'),
      ],
    );
    expect(invalid.issue, FinancialIssue.invalidItem);
    final purchase = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '100',
      items: const [
        FinancialItemInput(
          category: 'scrap',
          karat: 21,
          grams: '0.500',
          count: '',
          name: 'كسر',
        ),
      ],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '100'),
      ],
    );
    expect(purchase.isValid, isTrue);
    expect((purchase.draft!.items.single)['count'], isNull);
  });

  test('expense requires a description and exact split tender', () {
    final missing = FinancialDraft.compose(
      kind: FinancialKind.expense,
      totalPounds: '10',
      items: const [],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '10'),
      ],
    );
    expect(missing.issue, FinancialIssue.missingDescription);
    final valid = FinancialDraft.compose(
      kind: FinancialKind.expense,
      totalPounds: '10',
      description: 'مصاريف شحن',
      items: const [],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '5'),
        FinancialTenderInput(method: CashMethod.wallet, pounds: '5'),
      ],
    );
    expect(valid.isValid, isTrue);
  });

  test('partially paid purchase keeps one exact cash payable and seller', () {
    final purchase = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '20000'),
      ],
      customerName: 'تاجر تجريبي',
    );
    expect(purchase.isValid, isTrue);
    expect(purchase.draft!.cashPaid.wire, '2000000');
    expect(purchase.draft!.purchasePayable?.wire, '4000000');
    expect(purchase.draft!.toJson()['purchase_obligation_piastres'], '4000000');
    final anonymous = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: [ring],
      tenders: const [],
    );
    expect(anonymous.issue, FinancialIssue.missingSeller);
    final unpaid = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: [ring],
      tenders: const [],
      customerName: 'تاجر تجريبي',
    );
    expect(unpaid.isValid, isTrue);
    expect(unpaid.draft!.cashPaid.wire, '0');
    expect(unpaid.draft!.purchasePayable?.wire, '6000000');
  });

  test('scrap quick sale accepts only scrap and exact split cash', () {
    const scrap = FinancialItemInput(
      category: 'scrap',
      karat: 21,
      grams: '0.375',
      count: '',
      name: 'كسر',
    );
    final valid = FinancialDraft.compose(
      kind: FinancialKind.scrapSale,
      totalPounds: '125.25',
      items: const [scrap],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '100'),
        FinancialTenderInput(method: CashMethod.card, pounds: '25.25'),
      ],
    );
    expect(valid.isValid, isTrue);
    expect(valid.draft!.toJson()['kind'], 'scrap_sale');
    expect(valid.draft!.items.single['milligrams'], '375');
    expect(valid.draft!.items.single['count'], isNull);
    final wrongStock = FinancialDraft.compose(
      kind: FinancialKind.scrapSale,
      totalPounds: '125.25',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '125.25'),
      ],
    );
    expect(wrongStock.issue, FinancialIssue.invalidItem);
  });
}

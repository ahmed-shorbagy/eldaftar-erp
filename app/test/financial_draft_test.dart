import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ring = FinancialItemInput(
    category: 'worked_jewelry',
    karat: 18,
    grams: '1.830',
    count: '1',
    name: 'خواتم',
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
          name: 'خواتم',
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

  test('a purchase is rejected unless tenders equal the total', () {
    final partial = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: [ring],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '20000'),
      ],
      customerName: 'تاجر تجريبي',
    );
    expect(partial.issue, FinancialIssue.tenderMismatch);
    final unpaid = FinancialDraft.compose(
      kind: FinancialKind.purchase,
      totalPounds: '60000',
      items: [ring],
      tenders: const [],
    );
    expect(unpaid.issue, FinancialIssue.invalidTender);
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

  test('a standalone return keeps the sale contract and rejects scrap', () {
    final result = FinancialDraft.compose(
      kind: FinancialKind.customerReturn,
      totalPounds: '5000',
      items: const [
        FinancialItemInput(
          category: 'worked_jewelry',
          karat: 21,
          grams: '2.000',
          count: '1',
          name: 'خواتم',
        ),
      ],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '5000'),
      ],
      customerName: 'منى',
      note: 'مرتجع',
    );
    expect(result.isValid, isTrue);
    expect(result.draft!.toJson(), {
      'version': 1,
      'kind': 'customer_return',
      'total_piastres': '500000',
      'tenders': [
        {'method': 'cash', 'piastres': '500000'},
      ],
      'items': [
        {
          'category': 'worked_jewelry',
          'karat': 21,
          'milligrams': '2000',
          'count': '1',
          'item_name': 'خواتم',
          'line_price_piastres': null,
        },
      ],
      'customer_name': 'منى',
      'customer_phone': '',
      'note': 'مرتجع',
    });
    expect(result.draft!.toJson().containsKey('description'), isFalse);
    final scrap = FinancialDraft.compose(
      kind: FinancialKind.customerReturn,
      totalPounds: '5000',
      items: const [
        FinancialItemInput(
          category: 'scrap',
          karat: 21,
          grams: '2.000',
          count: '1',
          name: 'كسر',
        ),
      ],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '5000'),
      ],
    );
    expect(scrap.issue, FinancialIssue.invalidItem);
    final mismatch = FinancialDraft.compose(
      kind: FinancialKind.customerReturn,
      totalPounds: '5000',
      items: const [
        FinancialItemInput(
          category: 'worked_jewelry',
          karat: 21,
          grams: '2.000',
          count: '1',
          name: 'خواتم',
        ),
      ],
      tenders: const [
        FinancialTenderInput(method: CashMethod.cash, pounds: '1'),
      ],
    );
    expect(mismatch.issue, FinancialIssue.tenderMismatch);
  });
}

import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/invoice_pricing.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit price components conserve every piastre', () {
    final result =
        InvoicePricing.compose(
              basePounds: '1000.01',
              workmanshipPounds: '50.02',
              otherChargesPounds: '10.03',
              otherChargesLabel: 'تغليف',
              discountPounds: '20.04',
            )
            as Accepted<InvoicePricing>;
    expect(result.value.total.wire, '104002');
    expect(result.value.toJson(), {
      'base_piastres': '100001',
      'workmanship_piastres': '5002',
      'other_charges_piastres': '1003',
      'other_charges_label': 'تغليف',
      'discount_piastres': '2004',
    });
  });
  test('invalid adjustments cannot become a sale', () {
    for (final result in [
      InvoicePricing.compose(basePounds: '1', discountPounds: '1.01'),
      InvoicePricing.compose(basePounds: '1', discountPounds: '1'),
      InvoicePricing.compose(basePounds: '1', workmanshipPounds: '-1'),
      InvoicePricing.compose(basePounds: '1', workmanshipPounds: '0.001'),
      InvoicePricing.compose(basePounds: '1', otherChargesPounds: '1'),
      InvoicePricing.compose(
        basePounds: '92233720368547758.07',
        workmanshipPounds: '.01',
      ),
    ]) {
      expect(result, isA<Rejected<InvoicePricing>>());
    }
  });
  test('exact intermediate sums apply discount before final bigint check', () {
    final result =
        InvoicePricing.compose(
              basePounds: '92233720368547758.07',
              workmanshipPounds: '0.01',
              discountPounds: '0.01',
            )
            as Accepted<InvoicePricing>;
    expect(result.value.total.wire, '9223372036854775807');
    expect(
      InvoicePricing.compose(
        basePounds: '92233720368547758.07',
        workmanshipPounds: '0.01',
      ),
      isA<Rejected<InvoicePricing>>(),
    );
  });
  test(
    'split tenders match adjusted total; item prices match explicit base',
    () {
      final price =
          (InvoicePricing.compose(
                    basePounds: '1000',
                    workmanshipPounds: '50',
                    discountPounds: '20',
                  )
                  as Accepted<InvoicePricing>)
              .value;
      FinancialDraftResult compose(String total, String paid) =>
          FinancialDraft.compose(
            kind: FinancialKind.sale,
            totalPounds: total,
            pricing: price,
            items: const [
              FinancialItemInput(
                category: 'worked_jewelry',
                karat: 18,
                grams: '1.830',
                count: '1',
                name: 'خاتم',
                linePricePounds: '1000',
              ),
            ],
            tenders: [
              const FinancialTenderInput(
                method: CashMethod.cash,
                pounds: '500',
              ),
              FinancialTenderInput(method: CashMethod.card, pounds: paid),
            ],
          );
      final accepted = compose('1030', '530');
      expect(accepted.isValid, isTrue);
      expect(accepted.draft!.toJson()['version'], 2);
      expect(accepted.draft!.toJson()['pricing'], price.toJson());
      expect(compose('1000', '500').issue, FinancialIssue.pricingMismatch);
      expect(compose('1030', '529.99').issue, FinancialIssue.tenderMismatch);
    },
  );
}

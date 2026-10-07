import 'package:eldafttar/src/features/daily_ledger/domain/ledger_compensation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const refundable = {
    'cash': '8000',
    'instant_transfer': '0',
    'wallet': '0',
    'card': '0',
  };

  Map<String, BigInt> methods(Map<String, String> values) => {
    for (final entry in values.entries) entry.key: BigInt.parse(entry.value),
  };

  ReturnLineInput line({
    BigInt? milligrams,
    BigInt? count,
    BigInt? remainderMilligrams,
    BigInt? remainderCount,
  }) => ReturnLineInput(
    itemIndex: 0,
    category: 'worked_jewelry',
    karat: 18,
    scrap: false,
    milligrams: milligrams ?? BigInt.from(2000),
    count: count ?? BigInt.one,
    remainderMilligrams: remainderMilligrams ?? BigInt.from(4000),
    remainderCount: remainderCount ?? BigInt.two,
  );

  test('accepts an explicit consideration that is not the weight ratio', () {
    final reviewed = reviewPartialReturn(
      kind: 'sale_return',
      consideration: BigInt.from(3000),
      remainderConsideration: BigInt.from(8000),
      payableRemaining: BigInt.zero,
      quantityRemains: true,
      lines: [line()],
      tenders: {'cash': BigInt.from(3000)},
      refundableByMethod: methods(refundable),
      shopBalances: {'cash': BigInt.from(508000)},
      pricingRequired: false,
    );
    expect(reviewed, isA<CompensationAccepted<PartialReturnReview>>());
    final value = (reviewed as CompensationAccepted<PartialReturnReview>).value;
    expect(value.cashRefund, BigInt.from(3000));
    expect(value.cancelledPayable, BigInt.zero);
    expect(value.consideration, isNot(BigInt.from(4000)));
  });

  test('purchase return cancels payable before cash from the seller', () {
    final reviewed = reviewPartialReturn(
      kind: 'purchase_return',
      consideration: BigInt.from(5000),
      remainderConsideration: BigInt.from(10000),
      payableRemaining: BigInt.from(4000),
      quantityRemains: true,
      lines: [
        line(
          milligrams: BigInt.from(2000),
          count: BigInt.one,
          remainderMilligrams: BigInt.from(2000),
          remainderCount: BigInt.one,
        ),
      ],
      tenders: {'cash': BigInt.from(1000)},
      refundableByMethod: methods({
        'cash': '6000',
        'instant_transfer': '0',
        'wallet': '0',
        'card': '0',
      }),
      pricingRequired: false,
    );
    final value = (reviewed as CompensationAccepted<PartialReturnReview>).value;
    expect(value.cancelledPayable, BigInt.from(4000));
    expect(value.cashRefund, BigInt.from(1000));
  });

  test('exchange nets cash and keeps karat buckets separate', () {
    final returned = reviewPartialReturn(
      kind: 'sale_return',
      consideration: BigInt.from(4000),
      remainderConsideration: BigInt.from(4000),
      payableRemaining: BigInt.zero,
      quantityRemains: true,
      lines: [
        line(
          milligrams: BigInt.from(2000),
          remainderMilligrams: BigInt.from(2000),
          remainderCount: BigInt.one,
        ),
      ],
      tenders: {'cash': BigInt.from(4000)},
      refundableByMethod: methods({
        'cash': '4000',
        'instant_transfer': '0',
        'wallet': '0',
        'card': '0',
      }),
      shopBalances: {'cash': BigInt.from(500000)},
      pricingRequired: false,
    );
    final accepted =
        reviewExchange(
              returnSide:
                  (returned as CompensationAccepted<PartialReturnReview>).value,
              replacementKind: 'sale',
              replacementTotal: BigInt.from(1500),
              replacementTenders: {'cash': BigInt.from(1500)},
              replacementLines: [
                ReplacementLine(
                  category: 'worked_jewelry',
                  karat: 18,
                  milligrams: BigInt.from(2000),
                  count: BigInt.one,
                  itemName: 'بدل',
                ),
                ReplacementLine(
                  category: 'bullion',
                  karat: 24,
                  milligrams: BigInt.from(1000),
                  count: BigInt.one,
                  itemName: 'سبيكة',
                ),
              ],
            )
            as CompensationAccepted<ExchangeReview>;
    expect(accepted.value.returnSide.signedCash, BigInt.from(-4000));
    expect(accepted.value.replacementCash, BigInt.from(1500));
    expect(accepted.value.netCash, BigInt.from(-2500));
    expect(accepted.value.netCash.toString(), '-2500');
    final jewelry = accepted.value.netLines.singleWhere(
      (line) => line.karat == 18,
    );
    final bullion = accepted.value.netLines.singleWhere(
      (line) => line.karat == 24,
    );
    expect(jewelry.milligrams, BigInt.zero);
    expect(bullion.milligrams, BigInt.from(-1000));
    expect(accepted.value.netLines, hasLength(2));
  });

  test(
    'correction uses signed bigint deltas and rejects a zero or split pair',
    () {
      final bookCash = methods({
        'cash': '500000',
        'instant_transfer': '0',
        'wallet': '0',
        'card': '1000',
      });
      final stock = [
        MetalEffect(
          category: 'worked_jewelry',
          karat: 18,
          milligrams: BigInt.from(10000),
          count: BigInt.from(4),
        ),
      ];
      final zero = reviewCountedCorrection(
        reason: 'لا فرق',
        countedCash: bookCash,
        bookCash: bookCash,
        countedStock: stock,
        bookStock: stock,
        countedScrap: const [],
        bookScrap: const [],
      );
      expect((zero as CompensationRejected).code, 'invalid_input');
      final pair = reviewCountedCorrection(
        reason: 'عدد بلا وزن',
        countedCash: bookCash,
        bookCash: bookCash,
        countedStock: [
          MetalEffect(
            category: 'worked_jewelry',
            karat: 18,
            milligrams: BigInt.from(1000),
            count: BigInt.zero,
          ),
        ],
        bookStock: stock,
        countedScrap: const [],
        bookScrap: const [],
      );
      expect((pair as CompensationRejected).code, 'stock_pair_mismatch');
      final huge = BigInt.parse('9223372036854775806');
      final corrected =
          reviewCountedCorrection(
                reason: 'نقص جرد',
                countedCash: {...bookCash, 'cash': huge},
                bookCash: {...bookCash, 'cash': huge - BigInt.one},
                countedStock: [
                  MetalEffect(
                    category: 'worked_jewelry',
                    karat: 18,
                    milligrams: BigInt.from(9000),
                    count: BigInt.from(3),
                  ),
                ],
                bookStock: stock,
                countedScrap: const [],
                bookScrap: const [],
              )
              as CompensationAccepted<CorrectionReview>;
      expect(corrected.value.cashDeltas['cash'], BigInt.one);
      expect(corrected.value.cashDeltas['cash'].toString(), '1');
      expect(corrected.value.stockDeltas.single.milligrams.toString(), '-1000');
      expect(corrected.value.stockDeltas.single.count.toString(), '-1');
    },
  );

  test(
    'over-return and price components stay inside the original remainder',
    () {
      final over = reviewPartialReturn(
        kind: 'sale_return',
        consideration: BigInt.from(3000),
        remainderConsideration: BigInt.from(8000),
        payableRemaining: BigInt.zero,
        quantityRemains: true,
        lines: [line(milligrams: BigInt.from(4001))],
        tenders: {'cash': BigInt.from(3000)},
        refundableByMethod: methods(refundable),
        pricingRequired: false,
      );
      expect((over as CompensationRejected).code, 'return_exceeds_original');
      final priced = reviewPartialReturn(
        kind: 'sale_return',
        consideration: BigInt.from(3000),
        remainderConsideration: BigInt.from(8000),
        payableRemaining: BigInt.zero,
        quantityRemains: true,
        lines: [line()],
        tenders: {'cash': BigInt.from(3000)},
        refundableByMethod: methods(refundable),
        shopBalances: {'cash': BigInt.from(8000)},
        pricingRequired: true,
        pricing: PriceComponents(
          base: BigInt.from(2500),
          workmanship: BigInt.from(500),
          otherCharges: BigInt.zero,
          discount: BigInt.zero,
          otherChargesLabel: '',
          remainderBase: BigInt.from(7000),
          remainderWorkmanship: BigInt.from(1000),
          remainderOtherCharges: BigInt.zero,
          remainderDiscount: BigInt.zero,
        ),
      );
      expect(priced, isA<CompensationAccepted<PartialReturnReview>>());
    },
  );
  test('refund method is explicit and capped by the paid total', () {
    final result = reviewPartialReturn(
      kind: 'sale_return',
      consideration: BigInt.from(1000),
      remainderConsideration: BigInt.from(1000),
      payableRemaining: BigInt.zero,
      quantityRemains: true,
      lines: [
        line(
          milligrams: BigInt.from(500),
          count: BigInt.one,
          remainderMilligrams: BigInt.from(500),
          remainderCount: BigInt.one,
        ),
      ],
      tenders: {'cash': BigInt.from(1000)},
      refundableByMethod: {'cash': BigInt.zero, 'card': BigInt.from(1000)},
      shopBalances: {'cash': BigInt.from(2000)},
      pricingRequired: false,
    );
    expect(result, isA<CompensationAccepted<PartialReturnReview>>());
    final over = reviewPartialReturn(
      kind: 'sale_return',
      consideration: BigInt.from(1001),
      remainderConsideration: BigInt.from(2000),
      payableRemaining: BigInt.zero,
      quantityRemains: true,
      lines: [line()],
      tenders: {'cash': BigInt.from(1001)},
      refundableByMethod: {'cash': BigInt.zero, 'card': BigInt.from(1000)},
      pricingRequired: false,
    );
    expect(over, isA<CompensationRejected<PartialReturnReview>>());
  });
}

import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:flutter_test/flutter_test.dart';

const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const lotId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const productId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const receiptId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const traderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const operationId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const denominationId = '12121212-1212-4121-8121-121212121212';

DayAnchor get day =>
    (DayAnchor.tryCreate(dayId, '2') as InventoryAccepted<DayAnchor>).value;

LotSnapshot lot({
  String id = lotId,
  String category = 'worked_jewelry',
  int karat = 21,
  StockClass stockClass = StockClass.ownedAvailable,
  int originalMg = 10000,
  int? remainingMg,
  int count = 1,
  int? remainingCount,
  String? originOperationId,
  int? nominalMg,
}) {
  final scrap = category == 'scrap';
  final original = BigInt.from(originalMg);
  return LotSnapshot(
    id: id,
    productId: productId,
    productName: 'خاتم',
    displayName: 'خاتم',
    category: category,
    karat: karat,
    stockClass: stockClass,
    remainingMilligrams: BigInt.from(remainingMg ?? originalMg),
    remainingCount: scrap ? null : BigInt.from(remainingCount ?? count),
    originalMilligrams: original,
    originalCount: scrap ? null : BigInt.from(count),
    legacyAggregate: false,
    nominalMilligrams: nominalMg == null ? null : BigInt.from(nominalMg),
    originOperationId: originOperationId,
  );
}

void main() {
  test('actual milligrams stay distinct from nominal identity', () {
    final reviewed = reviewAddition(
      day: day,
      reason: 'وزن فعلي',
      lines: [
        AdditionLine(
          itemName: 'سبيكة',
          category: 'bullion',
          karat: 24,
          milligrams: BigInt.from(4998),
          count: BigInt.one,
          denominationId: denominationId,
          nominalMilligrams: BigInt.from(5000),
        ),
      ],
    );
    final command = (reviewed as InventoryAccepted<ReviewedCommand>).value;
    final line = (command.payload['lines'] as List).single as Map;
    expect(line['milligrams'], '4998');
    expect(line['denomination_id'], denominationId);
    expect(command.notes, contains('nominal_not_stock'));
    expect(
      command.effects
          .where((effect) => effect.unit == EffectUnit.milligrams)
          .single
          .delta,
      BigInt.from(4998),
    );
    final measured = MeasuredIdentity(
      actualMilligrams: BigInt.from(4998),
      nominalMilligrams: BigInt.from(5000),
    );
    expect(measured.stockMilligrams, BigInt.from(4998));
    expect(measured.nominalDiffers, isTrue);
  });

  test('saleable stock excludes pending and trader custody', () {
    final triple = QuantityTriple(
      availableMilligrams: BigInt.from(10000),
      pendingMilligrams: BigInt.from(2500),
      heldMilligrams: BigInt.from(4000),
      availableCount: BigInt.one,
      pendingCount: BigInt.one,
      heldCount: null,
    );
    expect(triple.saleableMilligrams, BigInt.from(10000));
    expect(triple.saleableCount, BigInt.one);
    expect(triple.pendingMilligrams, BigInt.from(2500));
    expect(triple.heldMilligrams, BigInt.from(4000));
  });

  test('ownership transfer keeps exactly one obligation unit', () {
    final receipt = _custody();
    final cash =
        reviewOwnershipTransfer(
              day: day,
              reason: 'شراء الأمانة',
              receipt: receipt,
              milligrams: BigInt.from(10000),
              count: BigInt.one,
              obligation: EgpObligation(
                pricePiastres: BigInt.from(6000000),
                tenders: [
                  TenderDraft(method: 'cash', piastres: BigInt.from(2000000)),
                ],
              ),
            )
            as InventoryAccepted<ReviewedCommand>;
    final command = cash.value;
    expect(command.payload['price_piastres'], '6000000');
    expect(command.payload['purchase_obligation_piastres'], '4000000');
    expect(command.payload.containsKey('obligation_karat'), isFalse);
    expect(command.payload.containsKey('obligation_milligrams'), isFalse);
    expect(_delta(command, 'cash'), BigInt.from(-2000000));
    expect(_delta(command, 'egp_payable'), BigInt.from(4000000));
    expect(_delta(command, 'owned_available'), BigInt.from(10000));
    expect(_delta(command, 'trader_custody'), BigInt.from(-10000));
    expect(
      command.effects.where((effect) => effect.bucket == 'gold_payable'),
      isEmpty,
    );

    final paid =
        reviewOwnershipTransfer(
              day: day,
              reason: 'شراء الأمانة',
              receipt: receipt,
              milligrams: BigInt.from(10000),
              count: BigInt.one,
              obligation: EgpObligation(
                pricePiastres: BigInt.from(6000000),
                tenders: [
                  TenderDraft(method: 'cash', piastres: BigInt.from(6000000)),
                ],
              ),
            )
            as InventoryAccepted<ReviewedCommand>;
    expect(
      paid.value.payload.containsKey('purchase_obligation_piastres'),
      isFalse,
    );

    final gold =
        reviewOwnershipTransfer(
              day: day,
              reason: 'شراء الأمانة',
              receipt: receipt,
              milligrams: BigInt.from(10000),
              count: BigInt.one,
              obligation: GoldObligationDraft(
                karat: 21,
                milligrams: BigInt.from(6000),
              ),
            )
            as InventoryAccepted<ReviewedCommand>;
    expect(gold.value.payload['obligation_karat'], 21);
    expect(gold.value.payload['obligation_milligrams'], '6000');
    expect(gold.value.payload.containsKey('price_piastres'), isFalse);
    expect(gold.value.payload.containsKey('tenders'), isFalse);
    expect(gold.value.notes, contains('gold_obligation_only'));

    final mismatch = reviewOwnershipTransfer(
      day: day,
      reason: 'شراء الأمانة',
      receipt: receipt,
      milligrams: BigInt.from(10000),
      count: BigInt.one,
      obligation: GoldObligationDraft(karat: 18, milligrams: BigInt.from(6000)),
    );
    expect(
      (mismatch as InventoryRejected<ReviewedCommand>).code,
      InventoryIssueCode.karatMismatch,
    );
  });

  test('gold settlement is partial, full, or rejected when it exceeds', () {
    final source = lot(category: 'scrap', karat: 21);
    ReviewedCommand settle(int milligrams) =>
        (reviewGoldSettlement(
                  day: day,
                  reason: 'تسليم',
                  obligationOperationId: operationId,
                  obligationKarat: 21,
                  remainingMilligrams: BigInt.from(10000),
                  deliveries: [
                    DeliveryDraft(
                      lot: source,
                      milligrams: BigInt.from(milligrams),
                      count: null,
                    ),
                  ],
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    expect(settle(4000).partial, isTrue);
    expect(settle(4000).notes, contains('partial_settlement'));
    expect(settle(10000).partial, isFalse);
    expect(settle(10000).notes, contains('full_settlement'));
    final exceeded = reviewGoldSettlement(
      day: day,
      reason: 'تسليم',
      obligationOperationId: operationId,
      obligationKarat: 21,
      remainingMilligrams: BigInt.from(10000),
      deliveries: [
        DeliveryDraft(lot: source, milligrams: BigInt.from(10001), count: null),
      ],
    );
    expect(
      (exceeded as InventoryRejected<ReviewedCommand>).code,
      InventoryIssueCode.exceedsRemaining,
    );
  });

  test('piece quantities close together and a named lot cannot increase', () {
    final piece = lot(count: 2);
    expect(
      (reviewRemoval(
                day: day,
                reason: 'إخراج',
                lines: [
                  (
                    lot: piece,
                    milligrams: BigInt.from(10000),
                    count: BigInt.one,
                  ),
                ],
              )
              as InventoryRejected<ReviewedCommand>)
          .code,
      InventoryIssueCode.stockPairMismatch,
    );
    expect(
      (reviewCorrection(
                day: day,
                reason: 'جرد',
                cashDeltas: const [],
                metalDeltas: [
                  MetalDecrease(
                    lot: piece,
                    milligrams: BigInt.from(1000),
                    count: BigInt.one,
                  ),
                ],
              )
              as InventoryRejected<ReviewedCommand>)
          .code,
      InventoryIssueCode.invalidInput,
    );
  });

  test('overflow, empty reason, and scrap count stay canonical', () {
    expect(
      (reviewAddition(
                day: day,
                reason: 'حد',
                lines: [
                  AdditionLine(
                    itemName: 'سبيكة',
                    category: 'bullion',
                    karat: 24,
                    milligrams: BigInt.parse('9223372036854775808'),
                    count: BigInt.one,
                  ),
                ],
              )
              as InventoryRejected<ReviewedCommand>)
          .code,
      InventoryIssueCode.overflow,
    );
    expect(
      (reviewAddition(
                day: day,
                reason: '   ',
                lines: [
                  AdditionLine(
                    itemName: 'خاتم',
                    category: 'worked_jewelry',
                    karat: 21,
                    milligrams: BigInt.from(1000),
                    count: BigInt.one,
                  ),
                ],
              )
              as InventoryRejected<ReviewedCommand>)
          .code,
      InventoryIssueCode.invalidInput,
    );
    final scrap =
        reviewAddition(
              day: day,
              reason: 'كسر',
              lines: [
                AdditionLine(
                  itemName: 'كسر',
                  category: 'scrap',
                  karat: 21,
                  milligrams: BigInt.from(1500),
                  count: null,
                ),
              ],
            )
            as InventoryAccepted<ReviewedCommand>;
    final line = (scrap.value.payload['lines'] as List).single as Map;
    expect(line['count'], isNull);
    expect(line['milligrams'], '1500');
    expect(scrap.value.payload['version'], 1);
    expect(scrap.value.payload['expected_day_version'], '2');
  });

  test('receipt, recognition, and manual link do not double-count stock', () {
    ReviewedCommand receive(String recognition) =>
        (reviewReceipt(
                  day: day,
                  ownerKind: recognition == 'custody' ? 'trader' : 'shop',
                  traderId: recognition == 'custody' ? traderId : null,
                  counterpartyName: 'تاجر',
                  productName: 'خاتم',
                  category: 'worked_jewelry',
                  karat: 21,
                  milligrams: BigInt.from(10000),
                  count: BigInt.one,
                  recognition: recognition,
                  note: '',
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    String weightBucket(ReviewedCommand command) => command.effects
        .where((effect) => effect.unit == EffectUnit.milligrams)
        .single
        .bucket;
    expect(weightBucket(receive('immediate')), 'owned_available');
    expect(weightBucket(receive('deferred')), 'owned_pending');
    expect(receive('deferred').notes, contains('pending_not_saleable'));
    expect(weightBucket(receive('custody')), 'trader_custody');
    expect(
      receive('custody').effects.where((effect) => effect.bucket == 'cash'),
      isEmpty,
    );

    final recognized =
        reviewRecognition(
              day: day,
              reason: 'اعتراف',
              receipt: ReceiptSnapshot(
                id: receiptId,
                ownerKind: 'shop',
                policy: 'deferred',
                counterpartyName: 'تاجر',
                productId: productId,
                lotId: lotId,
                category: 'worked_jewelry',
                karat: 21,
                remainingMilligrams: BigInt.from(10000),
                remainingCount: BigInt.one,
              ),
              milligrams: BigInt.from(10000),
              count: BigInt.one,
            )
            as InventoryAccepted<ReviewedCommand>;
    expect(_delta(recognized.value, 'owned_pending'), BigInt.from(-10000));
    expect(_delta(recognized.value, 'owned_available'), BigInt.from(10000));

    final linked =
        reviewManualLink(
              day: day,
              reason: 'ربط',
              receipt: ReceiptSnapshot(
                id: receiptId,
                ownerKind: 'shop',
                policy: 'deferred',
                counterpartyName: 'تاجر',
                productId: productId,
                lotId: 'abababab-abab-4aba-8aba-abababababab',
                category: 'worked_jewelry',
                karat: 21,
                remainingMilligrams: BigInt.from(10000),
                remainingCount: BigInt.one,
              ),
              lot: lot(originOperationId: operationId),
              manualOperationId: operationId,
            )
            as InventoryAccepted<ReviewedCommand>;
    expect(
      linked.value.effects.map((effect) => effect.bucket),
      everyElement('owned_pending'),
    );
    expect(
      linked.value.effects.where((effect) => effect.delta.isNegative),
      isNotEmpty,
    );
    expect(linked.value.notes, contains('no_second_stock_posting'));
    expect(linked.value.payload['milligrams'], '10000');
  });

  test(
    'gold acquisition keeps an explicit trader id and never a display name',
    () {
      final unlinked =
          reviewGoldAcquisition(
                day: day,
                itemName: 'خاتم',
                category: 'worked_jewelry',
                karat: 21,
                milligrams: BigInt.from(1000),
                count: BigInt.one,
                obligationKarat: 21,
                obligationMilligrams: BigInt.from(1000),
                counterpartyName: 'تاجر الأمانة',
                note: '',
              )
              as InventoryAccepted<ReviewedCommand>;
      expect(unlinked.value.payload['trader_id'], isNull);
      expect(unlinked.value.notes, isNot(contains('linked_trader')));
      final linked =
          reviewGoldAcquisition(
                day: day,
                itemName: 'خاتم',
                category: 'worked_jewelry',
                karat: 21,
                milligrams: BigInt.from(1000),
                count: BigInt.one,
                obligationKarat: 18,
                obligationMilligrams: BigInt.from(800),
                counterpartyName: 'تاجر الأمانة',
                note: '',
                traderId: traderId,
              )
              as InventoryAccepted<ReviewedCommand>;
      expect(linked.value.payload['trader_id'], traderId);
      expect(linked.value.notes, contains('linked_trader'));
      expect(
        (reviewGoldAcquisition(
                  day: day,
                  itemName: 'خاتم',
                  category: 'worked_jewelry',
                  karat: 21,
                  milligrams: BigInt.from(1000),
                  count: BigInt.one,
                  obligationKarat: 21,
                  obligationMilligrams: BigInt.from(1000),
                  counterpartyName: 'تاجر الأمانة',
                  note: '',
                  traderId: 'تاجر الأمانة',
                )
                as InventoryRejected<ReviewedCommand>)
            .code,
        InventoryIssueCode.invalidInput,
      );
    },
  );

  test(
    'named lot sale is a version 2 envelope and pending stock cannot be sold',
    () {
      final sold =
          reviewExplicitLotSale(
                day: day,
                lot: lot(count: 2, nominalMg: 5000),
                milligrams: BigInt.from(4000),
                count: BigInt.one,
                totalPiastres: BigInt.from(100000),
                tenders: [
                  TenderDraft(method: 'cash', piastres: BigInt.from(100000)),
                ],
                description: 'بيع',
                customerName: '',
                customerPhone: '',
                note: '',
                pricing: {
                  'base_piastres': '120000',
                  'workmanship_piastres': '0',
                  'other_charges_piastres': '0',
                  'other_charges_label': '',
                  'discount_piastres': '20000',
                },
              )
              as InventoryAccepted<ReviewedCommand>;
      expect(sold.value.payload['version'], 2);
      expect(sold.value.kind, 'sale');
      expect(sold.value.payload.containsKey('lot_identities'), isFalse);
      final selection =
          (sold.value.payload['lot_selections'] as List).single as Map;
      expect(selection['lot_id'], lotId);
      expect(selection['milligrams'], '4000');
      expect(selection['count'], '1');
      expect(sold.value.notes, contains('named_lot'));
      expect(
        (reviewExplicitLotSale(
                  day: day,
                  lot: lot(stockClass: StockClass.ownedPending),
                  milligrams: BigInt.from(1000),
                  count: BigInt.one,
                  totalPiastres: BigInt.from(1000),
                  tenders: [
                    TenderDraft(method: 'cash', piastres: BigInt.from(1000)),
                  ],
                  description: '',
                  customerName: '',
                  customerPhone: '',
                  note: '',
                )
                as InventoryRejected<ReviewedCommand>)
            .code,
        InventoryIssueCode.invalidInput,
      );
      expect(
        (reviewExplicitLotSale(
                  day: day,
                  lot: lot(count: 2),
                  milligrams: BigInt.from(1000),
                  count: BigInt.one,
                  totalPiastres: BigInt.from(1000),
                  tenders: [
                    TenderDraft(method: 'cash', piastres: BigInt.from(900)),
                  ],
                  description: '',
                  customerName: '',
                  customerPhone: '',
                  note: '',
                )
                as InventoryRejected<ReviewedCommand>)
            .code,
        InventoryIssueCode.tenderMismatch,
      );
    },
  );
}

ReceiptSnapshot _custody() => ReceiptSnapshot(
  id: receiptId,
  ownerKind: 'trader',
  policy: 'custody',
  traderId: traderId,
  counterpartyName: 'تاجر الأمانة',
  productId: productId,
  lotId: lotId,
  category: 'worked_jewelry',
  karat: 21,
  remainingMilligrams: BigInt.from(10000),
  remainingCount: BigInt.one,
);

BigInt _delta(ReviewedCommand command, String bucket) => command.effects
    .where(
      (effect) => effect.bucket == bucket && effect.unit != EffectUnit.count,
    )
    .fold(BigInt.zero, (sum, effect) => sum + effect.delta);

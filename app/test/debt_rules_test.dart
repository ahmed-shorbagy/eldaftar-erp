import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const sourceId = 'd3000000-0000-4000-8000-000000000201';
const reference = 'd3000000-0000-4000-8000-000000000202';
const dayId = 'd3000000-0000-4000-8000-000000000203';

void main() {
  test('declaration keeps money and gold exact and posts nothing', () {
    final money = debtDeclaration(
      direction: DebtDirection.shopOwes,
      unit: DebtUnit.money,
      karat: null,
      amountText: '10.50',
      partyName: ' طرف ',
      contactPhone: '',
      reason: ' دين سابق ',
      externalReference: ' EXT-1 ',
    );
    expect(money, isA<DebtAccepted<DebtDeclaration>>());
    final declared = (money as DebtAccepted<DebtDeclaration>).value;
    expect(declared.amount, BigInt.from(1050));
    expect(declared.partyName, 'طرف');
    expect(declared.externalReference, 'EXT-1');
    expect(declared.effect.isZero, isTrue);
    expect(declared.effect.custodyMilligrams, BigInt.zero);
    expect(declared.toPayload()['karat'], isNull);
    expect(declared.toPayload().length, 10);

    final gold = debtDeclaration(
      direction: DebtDirection.owedToShop,
      unit: DebtUnit.gold,
      karat: 21,
      amountText: '1.255',
      partyName: 'عميل',
      contactPhone: '+201000000000',
      reason: 'ذهب',
      externalReference: '',
    );
    final received = (gold as DebtAccepted<DebtDeclaration>).value;
    expect(received.amount, BigInt.from(1255));
    expect(received.externalReference, isNull);
    expect(received.effect.goldMilligrams, BigInt.zero);
  });

  test('rejects conversion, overflow, bad karat and padded identity', () {
    expect(
      (debtDeclaration(
                direction: DebtDirection.shopOwes,
                unit: DebtUnit.gold,
                karat: 15,
                amountText: '1.000',
                partyName: 'طرف',
                contactPhone: '',
                reason: 'سبب',
                externalReference: '',
              )
              as DebtRejected)
          .issue,
      DebtIssue.unsupportedCategoryKarat,
    );
    expect(
      (debtDeclaration(
                direction: DebtDirection.shopOwes,
                unit: DebtUnit.money,
                karat: null,
                amountText: '92233720368547758.08',
                partyName: 'طرف',
                contactPhone: '',
                reason: 'سبب',
                externalReference: '',
              )
              as DebtRejected)
          .issue,
      DebtIssue.overflow,
    );
    expect(debtPhone(' 010 '), isA<DebtRejected<String>>());
  });

  test('settlement signs match the unit and direction without conversion', () {
    final sourceNone = debtSettlement(
      sourceKind: DebtSourceKind.purchaseCashPayable,
      sourceId: sourceId,
      direction: DebtDirection.shopOwes,
      unit: DebtUnit.money,
      karat: null,
      remaining: BigInt.from(8000),
      recordVersion: null,
      amountText: '10',
      ledgerEffect: DebtLedgerEffect.none,
      reason: 'بلا قيد',
      settlementReference: reference,
      dayId: null,
      dayVersion: null,
      tenders: null,
      deliveries: null,
      receipt: null,
    );
    expect((sourceNone as DebtRejected).issue, DebtIssue.ledgerEffectRequired);

    final cash = debtSettlement(
      sourceKind: DebtSourceKind.standalone,
      sourceId: sourceId,
      direction: DebtDirection.shopOwes,
      unit: DebtUnit.money,
      karat: null,
      remaining: BigInt.from(5000),
      recordVersion: BigInt.one,
      amountText: '20.00',
      ledgerEffect: DebtLedgerEffect.move,
      reason: 'سداد نقدي',
      settlementReference: reference,
      dayId: dayId,
      dayVersion: BigInt.one,
      tenders: [
        DebtTender(method: 'cash', piastres: BigInt.from(1500)),
        DebtTender(method: 'wallet', piastres: BigInt.from(500)),
      ],
      deliveries: null,
      receipt: null,
    );
    final paid = (cash as DebtAccepted<DebtSettlement>).value;
    expect(paid.amount, BigInt.from(2000));
    expect(paid.effect.cashPiastres, BigInt.from(-2000));
    expect(paid.effect.goldMilligrams, BigInt.zero);
    expect(paid.effect.saleableStockMilligrams, BigInt.zero);
    expect(paid.toPayload().length, 18);

    final tooMuch = debtSettlement(
      sourceKind: DebtSourceKind.standalone,
      sourceId: sourceId,
      direction: DebtDirection.shopOwes,
      unit: DebtUnit.money,
      karat: null,
      remaining: BigInt.from(100),
      recordVersion: BigInt.one,
      amountText: '2',
      ledgerEffect: DebtLedgerEffect.none,
      reason: 'زيادة',
      settlementReference: reference,
      dayId: null,
      dayVersion: null,
      tenders: null,
      deliveries: null,
      receipt: null,
    );
    expect((tooMuch as DebtRejected).issue, DebtIssue.exceedsRemaining);

    final scrapOut = debtSettlement(
      sourceKind: DebtSourceKind.goldObligation,
      sourceId: sourceId,
      direction: DebtDirection.shopOwes,
      unit: DebtUnit.gold,
      karat: 21,
      remaining: BigInt.from(800),
      recordVersion: null,
      amountText: '0.800',
      ledgerEffect: DebtLedgerEffect.move,
      reason: 'تسليم كسر',
      settlementReference: reference,
      dayId: dayId,
      dayVersion: BigInt.two,
      tenders: null,
      deliveries: [
        DebtDelivery(
          lotId: dayId,
          milligrams: BigInt.from(800),
          count: null,
          scrap: true,
        ),
      ],
      receipt: null,
    );
    final outgoing = (scrapOut as DebtAccepted<DebtSettlement>).value;
    expect(outgoing.effect.goldMilligrams, BigInt.from(-800));
    expect(outgoing.effect.goldCount, BigInt.zero);
    expect(outgoing.effect.saleableStockMilligrams, BigInt.zero);
    expect(outgoing.effect.cashPiastres, BigInt.zero);

    final incoming = debtSettlement(
      sourceKind: DebtSourceKind.standalone,
      sourceId: sourceId,
      direction: DebtDirection.owedToShop,
      unit: DebtUnit.gold,
      karat: 21,
      remaining: BigInt.from(1500),
      recordVersion: BigInt.one,
      amountText: '1.500',
      ledgerEffect: DebtLedgerEffect.move,
      reason: 'استلام',
      settlementReference: reference,
      dayId: dayId,
      dayVersion: BigInt.one,
      tenders: null,
      deliveries: null,
      receipt: DebtReceipt(
        category: 'worked_jewelry',
        productName: 'خاتم',
        milligrams: BigInt.from(1500),
        count: BigInt.one,
      ),
    );
    final received = (incoming as DebtAccepted<DebtSettlement>).value;
    expect(received.effect.goldMilligrams, BigInt.from(1500));
    expect(received.effect.goldCount, BigInt.one);
    expect(received.effect.saleableStockMilligrams, BigInt.from(1500));
    expect(received.effect.custodyMilligrams, BigInt.zero);
  });

  test('cancel and archive payloads stay strict', () {
    final cancel = debtCancelPayload(
      sourceId: sourceId,
      expectedRemaining: BigInt.from(4000),
      expectedVersion: BigInt.one,
      reason: 'تسجيل خاطئ',
    );
    expect(cancel['source_kind'], 'standalone');
    expect(cancel.length, 7);
    final archive = debtArchivePayload(
      sourceKind: DebtSourceKind.purchaseCashPayable,
      sourceId: sourceId,
      expectedRemaining: BigInt.from(5000),
      expectedVersion: null,
      reason: 'إخفاء',
    );
    expect(archive['expected_version'], isNull);
    expect(archive['source_kind'], 'purchase_cash_payable');
  });
}

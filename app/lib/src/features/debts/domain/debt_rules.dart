import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../../daily_ledger/domain/quantities.dart';

/// Debt validation codes. Arabic copy stays in presentation.
enum DebtIssue {
  invalidInput,
  unsupportedCategoryKarat,
  negativeAmount,
  overflow,
  exceedsRemaining,
  ledgerEffectRequired,
  tenderMismatch,
  deliveryMismatch,
}

sealed class DebtRulesResult<T> {
  const DebtRulesResult();
}

final class DebtAccepted<T> extends DebtRulesResult<T> {
  const DebtAccepted(this.value);
  final T value;
}

final class DebtRejected<T> extends DebtRulesResult<T> {
  const DebtRejected(this.issue);
  final DebtIssue issue;
}

enum DebtDirection {
  shopOwes('shop_owes'),
  owedToShop('owed_to_shop');

  const DebtDirection(this.wire);
  final String wire;

  static DebtDirection? byWire(String value) {
    for (final direction in values) {
      if (direction.wire == value) return direction;
    }
    return null;
  }
}

enum DebtUnit {
  money('money'),
  gold('gold');

  const DebtUnit(this.wire);
  final String wire;

  static DebtUnit? byWire(String value) {
    for (final unit in values) {
      if (unit.wire == value) return unit;
    }
    return null;
  }
}

enum DebtLedgerEffect {
  move('move'),
  none('none');

  const DebtLedgerEffect(this.wire);
  final String wire;
}

enum DebtSourceKind {
  standalone('standalone'),
  purchaseCashPayable('purchase_cash_payable'),
  goldObligation('gold_obligation');

  const DebtSourceKind(this.wire);
  final String wire;

  bool get isSource => this != standalone;

  static DebtSourceKind? byWire(String value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// Reviewed physical effect. Custody stays zero; there is no unit conversion.
final class DebtEffect {
  const DebtEffect({
    required this.cashPiastres,
    required this.goldMilligrams,
    required this.goldCount,
    required this.saleableStockMilligrams,
  });

  static final zero = DebtEffect(
    cashPiastres: BigInt.zero,
    goldMilligrams: BigInt.zero,
    goldCount: BigInt.zero,
    saleableStockMilligrams: BigInt.zero,
  );

  final BigInt cashPiastres;
  final BigInt goldMilligrams;
  final BigInt goldCount;
  final BigInt saleableStockMilligrams;

  BigInt get custodyMilligrams => BigInt.zero;

  bool get isZero =>
      cashPiastres == BigInt.zero &&
      goldMilligrams == BigInt.zero &&
      goldCount == BigInt.zero &&
      saleableStockMilligrams == BigInt.zero &&
      custodyMilligrams == BigInt.zero;

  Map<String, String> get wires => {
    'cash_piastres': cashPiastres.toString(),
    'gold_milligrams': goldMilligrams.toString(),
    'gold_count': goldCount.toString(),
    'custody_milligrams': '0',
    'saleable_stock_milligrams': saleableStockMilligrams.toString(),
  };
}

final _phone = RegExp(r'^\+?[0-9]{7,15}$');

bool debtCategoryAllows(String category, int karat) {
  if (category == 'scrap') return ScrapKarats.allowed.contains(karat);
  return StockCategory.byCode(category)?.allowsKarat(karat) ?? false;
}

DebtRulesResult<String> debtParty(String raw) => _text(raw, 1, 200);

DebtRulesResult<String> debtReason(String raw) => _text(raw, 1, 500);

DebtRulesResult<String> debtPhone(String raw) {
  if (raw != raw.trim() || raw.length > 20) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  if (raw.isEmpty || _phone.hasMatch(raw)) return DebtAccepted(raw);
  return const DebtRejected(DebtIssue.invalidInput);
}

DebtRulesResult<String?> debtExternalReference(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const DebtAccepted(null);
  if (text.length > 80) return const DebtRejected(DebtIssue.invalidInput);
  return DebtAccepted(text);
}

/// A declaration records a historical balance and moves nothing.
final class DebtDeclaration {
  const DebtDeclaration({
    required this.direction,
    required this.unit,
    required this.karat,
    required this.amount,
    required this.partyName,
    required this.contactPhone,
    required this.reason,
    required this.externalReference,
  });

  final DebtDirection direction;
  final DebtUnit unit;
  final int? karat;
  final BigInt amount;
  final String partyName;
  final String contactPhone;
  final String reason;
  final String? externalReference;

  DebtEffect get effect => DebtEffect.zero;

  Map<String, Object?> toPayload() => {
    'amount': amount.toString(),
    'contact_phone': contactPhone,
    'direction': direction.wire,
    'external_reference': externalReference,
    'karat': karat,
    'kind': 'debt_declare',
    'party_name': partyName,
    'reason': reason,
    'unit': unit.wire,
    'version': 1,
  };
}

DebtRulesResult<DebtDeclaration> debtDeclaration({
  required DebtDirection direction,
  required DebtUnit unit,
  required int? karat,
  required String amountText,
  required String partyName,
  required String contactPhone,
  required String reason,
  required String externalReference,
}) {
  final party = debtParty(partyName);
  if (party is DebtRejected<String>) return DebtRejected(party.issue);
  final phone = debtPhone(contactPhone);
  if (phone is DebtRejected<String>) return DebtRejected(phone.issue);
  final why = debtReason(reason);
  if (why is DebtRejected<String>) return DebtRejected(why.issue);
  final reference = debtExternalReference(externalReference);
  if (reference is DebtRejected<String?>) return DebtRejected(reference.issue);
  final karatResult = _karatFor(unit, karat);
  if (karatResult is DebtRejected<int?>) return DebtRejected(karatResult.issue);
  final amount = _amount(unit, amountText);
  if (amount is DebtRejected<BigInt>) return DebtRejected(amount.issue);
  return DebtAccepted(
    DebtDeclaration(
      direction: direction,
      unit: unit,
      karat: (karatResult as DebtAccepted<int?>).value,
      amount: (amount as DebtAccepted<BigInt>).value,
      partyName: (party as DebtAccepted<String>).value,
      contactPhone: (phone as DebtAccepted<String>).value,
      reason: (why as DebtAccepted<String>).value,
      externalReference: (reference as DebtAccepted<String?>).value,
    ),
  );
}

final class DebtTender {
  const DebtTender({required this.method, required this.piastres});
  final String method;
  final BigInt piastres;

  Map<String, Object?> toJson() => {
    'method': method,
    'piastres': piastres.toString(),
  };
}

final class DebtDelivery {
  const DebtDelivery({
    required this.lotId,
    required this.milligrams,
    required this.count,
    required this.scrap,
  });

  final String lotId;
  final BigInt milligrams;
  final BigInt? count;
  final bool scrap;

  Map<String, Object?> toJson() => {
    'lot_id': lotId,
    'milligrams': milligrams.toString(),
    'count': scrap ? null : count!.toString(),
  };
}

final class DebtReceipt {
  const DebtReceipt({
    required this.category,
    required this.productName,
    required this.milligrams,
    required this.count,
  });

  final String category;
  final String productName;
  final BigInt milligrams;
  final BigInt? count;

  Map<String, Object?> toJson() => {
    'category': category,
    'product_name': productName,
    'milligrams': milligrams.toString(),
    'count': count?.toString(),
  };
}

final class DebtSettlement {
  const DebtSettlement({
    required this.sourceKind,
    required this.sourceId,
    required this.direction,
    required this.unit,
    required this.karat,
    required this.amount,
    required this.expectedRemaining,
    required this.expectedVersion,
    required this.ledgerEffect,
    required this.reason,
    required this.settlementReference,
    required this.expectedDayId,
    required this.expectedDayVersion,
    required this.tenders,
    required this.deliveries,
    required this.receipt,
    required this.effect,
  });

  final DebtSourceKind sourceKind;
  final String sourceId;
  final DebtDirection direction;
  final DebtUnit unit;
  final int? karat;
  final BigInt amount;
  final BigInt expectedRemaining;
  final BigInt? expectedVersion;
  final DebtLedgerEffect ledgerEffect;
  final String reason;
  final String settlementReference;
  final String? expectedDayId;
  final BigInt? expectedDayVersion;
  final List<DebtTender>? tenders;
  final List<DebtDelivery>? deliveries;
  final DebtReceipt? receipt;
  final DebtEffect effect;

  Map<String, Object?> toPayload() => {
    'amount': amount.toString(),
    'deliveries': deliveries == null
        ? null
        : [for (final line in deliveries!) line.toJson()],
    'direction': direction.wire,
    'expected_day_id': expectedDayId,
    'expected_day_version': expectedDayVersion?.toString(),
    'expected_remaining': expectedRemaining.toString(),
    'expected_version': expectedVersion?.toString(),
    'karat': karat,
    'kind': 'debt_settle',
    'ledger_effect': ledgerEffect.wire,
    'reason': reason,
    'receipt': receipt?.toJson(),
    'settlement_reference': settlementReference,
    'source_id': sourceId,
    'source_kind': sourceKind.wire,
    'tenders': tenders == null
        ? null
        : [for (final tender in tenders!) tender.toJson()],
    'unit': unit.wire,
    'version': 1,
  };
}

DebtRulesResult<DebtSettlement> debtSettlement({
  required DebtSourceKind sourceKind,
  required String sourceId,
  required DebtDirection direction,
  required DebtUnit unit,
  required int? karat,
  required BigInt remaining,
  required BigInt? recordVersion,
  required String amountText,
  required DebtLedgerEffect ledgerEffect,
  required String reason,
  required String settlementReference,
  required String? dayId,
  required BigInt? dayVersion,
  required List<DebtTender>? tenders,
  required List<DebtDelivery>? deliveries,
  required DebtReceipt? receipt,
}) {
  if (sourceId.isEmpty) return const DebtRejected(DebtIssue.invalidInput);
  if (sourceKind.isSource &&
      (direction != DebtDirection.shopOwes ||
          ledgerEffect != DebtLedgerEffect.move)) {
    return const DebtRejected(DebtIssue.ledgerEffectRequired);
  }
  if (sourceKind == DebtSourceKind.standalone && recordVersion == null) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  if (sourceKind.isSource && recordVersion != null) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  final why = debtReason(reason);
  if (why is DebtRejected<String>) return DebtRejected(why.issue);
  final purity = _karatFor(unit, karat);
  if (purity is DebtRejected<int?>) return DebtRejected(purity.issue);
  final amount = _amount(unit, amountText);
  if (amount is DebtRejected<BigInt>) return DebtRejected(amount.issue);
  final parsedAmount = (amount as DebtAccepted<BigInt>).value;
  if (parsedAmount > remaining) {
    return const DebtRejected(DebtIssue.exceedsRemaining);
  }
  if (ledgerEffect == DebtLedgerEffect.none) {
    if (tenders != null ||
        deliveries != null ||
        receipt != null ||
        dayId != null ||
        dayVersion != null) {
      return const DebtRejected(DebtIssue.invalidInput);
    }
    return DebtAccepted(
      _settlement(
        sourceKind: sourceKind,
        sourceId: sourceId,
        direction: direction,
        unit: unit,
        karat: (purity as DebtAccepted<int?>).value,
        amount: parsedAmount,
        remaining: remaining,
        recordVersion: recordVersion,
        ledgerEffect: ledgerEffect,
        reason: (why as DebtAccepted<String>).value,
        settlementReference: settlementReference,
        dayId: null,
        dayVersion: null,
        tenders: null,
        deliveries: null,
        receipt: null,
        effect: DebtEffect.zero,
      ),
    );
  }
  if (dayId == null || dayId.isEmpty || dayVersion == null) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  if (unit == DebtUnit.money) {
    final paid = _tenders(tenders, parsedAmount);
    if (paid is DebtRejected<List<DebtTender>>) return DebtRejected(paid.issue);
    if (deliveries != null || receipt != null) {
      return const DebtRejected(DebtIssue.invalidInput);
    }
    final sign = direction == DebtDirection.shopOwes
        ? -parsedAmount
        : parsedAmount;
    return DebtAccepted(
      _settlement(
        sourceKind: sourceKind,
        sourceId: sourceId,
        direction: direction,
        unit: unit,
        karat: null,
        amount: parsedAmount,
        remaining: remaining,
        recordVersion: recordVersion,
        ledgerEffect: ledgerEffect,
        reason: (why as DebtAccepted<String>).value,
        settlementReference: settlementReference,
        dayId: dayId,
        dayVersion: dayVersion,
        tenders: (paid as DebtAccepted<List<DebtTender>>).value,
        deliveries: null,
        receipt: null,
        effect: DebtEffect(
          cashPiastres: sign,
          goldMilligrams: BigInt.zero,
          goldCount: BigInt.zero,
          saleableStockMilligrams: BigInt.zero,
        ),
      ),
    );
  }
  final resolvedKarat = (purity as DebtAccepted<int?>).value!;
  if (direction == DebtDirection.shopOwes) {
    final lines = _deliveries(deliveries, parsedAmount, resolvedKarat);
    if (lines is DebtRejected<List<DebtDelivery>>) {
      return DebtRejected(lines.issue);
    }
    if (tenders != null || receipt != null) {
      return const DebtRejected(DebtIssue.invalidInput);
    }
    final accepted = (lines as DebtAccepted<List<DebtDelivery>>).value;
    var pieces = BigInt.zero;
    var saleable = BigInt.zero;
    for (final line in accepted) {
      if (!line.scrap) {
        final nextPieces = PostgresInteger.checkedAdd(pieces, line.count!);
        final nextSaleable = PostgresInteger.checkedAdd(
          saleable,
          line.milligrams,
        );
        if (nextPieces == null || nextSaleable == null) {
          return const DebtRejected(DebtIssue.overflow);
        }
        pieces = nextPieces;
        saleable = nextSaleable;
      }
    }
    return DebtAccepted(
      _settlement(
        sourceKind: sourceKind,
        sourceId: sourceId,
        direction: direction,
        unit: unit,
        karat: resolvedKarat,
        amount: parsedAmount,
        remaining: remaining,
        recordVersion: recordVersion,
        ledgerEffect: ledgerEffect,
        reason: (why as DebtAccepted<String>).value,
        settlementReference: settlementReference,
        dayId: dayId,
        dayVersion: dayVersion,
        tenders: null,
        deliveries: accepted,
        receipt: null,
        effect: DebtEffect(
          cashPiastres: BigInt.zero,
          goldMilligrams: -parsedAmount,
          goldCount: -pieces,
          saleableStockMilligrams: -saleable,
        ),
      ),
    );
  }
  final incoming = _receipt(receipt, parsedAmount, resolvedKarat);
  if (incoming is DebtRejected<DebtReceipt>) {
    return DebtRejected(incoming.issue);
  }
  if (tenders != null || deliveries != null) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  final owned = (incoming as DebtAccepted<DebtReceipt>).value;
  final scrap = owned.category == 'scrap';
  return DebtAccepted(
    _settlement(
      sourceKind: sourceKind,
      sourceId: sourceId,
      direction: direction,
      unit: unit,
      karat: resolvedKarat,
      amount: parsedAmount,
      remaining: remaining,
      recordVersion: recordVersion,
      ledgerEffect: ledgerEffect,
      reason: (why as DebtAccepted<String>).value,
      settlementReference: settlementReference,
      dayId: dayId,
      dayVersion: dayVersion,
      tenders: null,
      deliveries: null,
      receipt: owned,
      effect: DebtEffect(
        cashPiastres: BigInt.zero,
        goldMilligrams: parsedAmount,
        goldCount: scrap ? BigInt.zero : owned.count!,
        saleableStockMilligrams: scrap ? BigInt.zero : parsedAmount,
      ),
    ),
  );
}

Map<String, Object?> debtCancelPayload({
  required String sourceId,
  required BigInt expectedRemaining,
  required BigInt expectedVersion,
  required String reason,
}) => {
  'expected_remaining': expectedRemaining.toString(),
  'expected_version': expectedVersion.toString(),
  'kind': 'debt_cancel',
  'reason': reason,
  'source_id': sourceId,
  'source_kind': DebtSourceKind.standalone.wire,
  'version': 1,
};

Map<String, Object?> debtArchivePayload({
  required DebtSourceKind sourceKind,
  required String sourceId,
  required BigInt expectedRemaining,
  required BigInt? expectedVersion,
  required String reason,
}) => {
  'expected_remaining': expectedRemaining.toString(),
  'expected_version': expectedVersion?.toString(),
  'kind': 'debt_archive',
  'reason': reason,
  'source_id': sourceId,
  'source_kind': sourceKind.wire,
  'version': 1,
};

DebtRulesResult<String> _text(String raw, int min, int max) {
  final text = raw.trim();
  if (text.length < min || text.length > max) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  return DebtAccepted(text);
}

DebtRulesResult<int?> _karatFor(DebtUnit unit, int? karat) {
  if (unit == DebtUnit.money) {
    return karat == null
        ? const DebtAccepted(null)
        : const DebtRejected(DebtIssue.invalidInput);
  }
  if (karat == null || !ScrapKarats.allowed.contains(karat)) {
    return const DebtRejected(DebtIssue.unsupportedCategoryKarat);
  }
  return DebtAccepted(karat);
}

DebtRulesResult<BigInt> _amount(DebtUnit unit, String text) {
  if (unit == DebtUnit.money) {
    final parsed = Piastres.parsePounds(text.trim());
    if (parsed is Rejected<Piastres>) return DebtRejected(_issue(parsed.code));
    final value = (parsed as Accepted<Piastres>).value.value;
    if (value == BigInt.zero) return const DebtRejected(DebtIssue.invalidInput);
    return DebtAccepted(value);
  }
  final parsed = Milligrams.parseGrams(text.trim());
  if (parsed is Rejected<Milligrams>) return DebtRejected(_issue(parsed.code));
  final value = (parsed as Accepted<Milligrams>).value.value;
  if (value == BigInt.zero) return const DebtRejected(DebtIssue.invalidInput);
  return DebtAccepted(value);
}

DebtIssue _issue(OpeningIssueCode code) => switch (code) {
  OpeningIssueCode.negativeAmount => DebtIssue.negativeAmount,
  OpeningIssueCode.overflow => DebtIssue.overflow,
  _ => DebtIssue.invalidInput,
};

DebtRulesResult<List<DebtTender>> _tenders(
  List<DebtTender>? tenders,
  BigInt expected,
) {
  if (tenders == null || tenders.isEmpty || tenders.length > 4) {
    return const DebtRejected(DebtIssue.tenderMismatch);
  }
  final seen = <String>{};
  var sum = BigInt.zero;
  for (final tender in tenders) {
    if (CashMethod.byCode(tender.method) == null ||
        !seen.add(tender.method) ||
        tender.piastres <= BigInt.zero ||
        !PostgresInteger.fits(tender.piastres)) {
      return const DebtRejected(DebtIssue.tenderMismatch);
    }
    final next = PostgresInteger.checkedAdd(sum, tender.piastres);
    if (next == null) return const DebtRejected(DebtIssue.overflow);
    sum = next;
  }
  if (sum != expected) return const DebtRejected(DebtIssue.tenderMismatch);
  return DebtAccepted(tenders);
}

DebtRulesResult<List<DebtDelivery>> _deliveries(
  List<DebtDelivery>? lines,
  BigInt expected,
  int karat,
) {
  if (lines == null || lines.isEmpty || lines.length > 20) {
    return const DebtRejected(DebtIssue.deliveryMismatch);
  }
  final seen = <String>{};
  var sum = BigInt.zero;
  for (final line in lines) {
    if (line.lotId.isEmpty || !seen.add(line.lotId)) {
      return const DebtRejected(DebtIssue.deliveryMismatch);
    }
    if (line.milligrams <= BigInt.zero ||
        !PostgresInteger.fits(line.milligrams)) {
      return const DebtRejected(DebtIssue.deliveryMismatch);
    }
    if (line.scrap) {
      if (line.count != null) {
        return const DebtRejected(DebtIssue.deliveryMismatch);
      }
    } else if (line.count == null ||
        line.count! <= BigInt.zero ||
        !PostgresInteger.fits(line.count!)) {
      return const DebtRejected(DebtIssue.deliveryMismatch);
    }
    final next = PostgresInteger.checkedAdd(sum, line.milligrams);
    if (next == null) return const DebtRejected(DebtIssue.overflow);
    sum = next;
  }
  if (sum != expected || !ScrapKarats.allowed.contains(karat)) {
    return const DebtRejected(DebtIssue.deliveryMismatch);
  }
  return DebtAccepted(lines);
}

DebtRulesResult<DebtReceipt> _receipt(
  DebtReceipt? receipt,
  BigInt expected,
  int karat,
) {
  if (receipt == null ||
      receipt.milligrams != expected ||
      !debtCategoryAllows(receipt.category, karat)) {
    return const DebtRejected(DebtIssue.deliveryMismatch);
  }
  final name = receipt.productName;
  if (name != name.trim() || name.isEmpty || name.length > 120) {
    return const DebtRejected(DebtIssue.invalidInput);
  }
  final scrap = receipt.category == 'scrap';
  if (scrap && receipt.count != null) {
    return const DebtRejected(DebtIssue.deliveryMismatch);
  }
  if (!scrap &&
      (receipt.count == null ||
          receipt.count! <= BigInt.zero ||
          !PostgresInteger.fits(receipt.count!))) {
    return const DebtRejected(DebtIssue.deliveryMismatch);
  }
  return DebtAccepted(receipt);
}

DebtSettlement _settlement({
  required DebtSourceKind sourceKind,
  required String sourceId,
  required DebtDirection direction,
  required DebtUnit unit,
  required int? karat,
  required BigInt amount,
  required BigInt remaining,
  required BigInt? recordVersion,
  required DebtLedgerEffect ledgerEffect,
  required String reason,
  required String settlementReference,
  required String? dayId,
  required BigInt? dayVersion,
  required List<DebtTender>? tenders,
  required List<DebtDelivery>? deliveries,
  required DebtReceipt? receipt,
  required DebtEffect effect,
}) {
  return DebtSettlement(
    sourceKind: sourceKind,
    sourceId: sourceId,
    direction: direction,
    unit: unit,
    karat: karat,
    amount: amount,
    expectedRemaining: remaining,
    expectedVersion: recordVersion,
    ledgerEffect: ledgerEffect,
    reason: reason,
    settlementReference: settlementReference,
    expectedDayId: dayId,
    expectedDayVersion: dayVersion,
    tenders: tenders,
    deliveries: deliveries,
    receipt: receipt,
    effect: effect,
  );
}

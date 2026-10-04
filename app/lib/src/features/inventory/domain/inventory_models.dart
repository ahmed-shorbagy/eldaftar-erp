import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/postgres_integer.dart';

/// Bookkeeping stock classes. Pending and trader custody are never saleable.
enum StockClass {
  ownedAvailable('owned_available'),
  ownedPending('owned_pending'),
  traderCustody('trader_custody');

  const StockClass(this.code);
  final String code;

  static StockClass? byCode(String code) {
    for (final value in StockClass.values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

enum InventoryIssueCode {
  invalidInput('invalid_input'),
  overflow('overflow'),
  unsupportedCategoryKarat('unsupported_category_karat'),
  exceedsRemaining('exceeds_remaining'),
  stockPairMismatch('stock_pair_mismatch'),
  mixedObligation('mixed_obligation'),
  karatMismatch('karat_mismatch'),
  tenderMismatch('tender_mismatch'),
  emptyCommand('empty_command'),
  duplicateLine('duplicate_line'),
  negativeBalance('negative_balance'),
  custodyRequiresTransfer('custody_requires_transfer');

  const InventoryIssueCode(this.wire);
  final String wire;
}

sealed class InventoryResult<T> {
  const InventoryResult();
}

final class InventoryAccepted<T> extends InventoryResult<T> {
  const InventoryAccepted(this.value);
  final T value;
}

final class InventoryRejected<T> extends InventoryResult<T> {
  const InventoryRejected(this.code);
  final InventoryIssueCode code;
}

/// Open-day identity copied from the server. The client does not invent it.
final class DayAnchor {
  const DayAnchor._(this.dayId, this.versionWire);

  final String dayId;
  final String versionWire;

  static InventoryResult<DayAnchor> tryCreate(
    String dayId,
    String versionWire,
  ) {
    if (!_uuid.hasMatch(dayId) || !_canonical.hasMatch(versionWire)) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (BigInt.parse(versionWire) < BigInt.one) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    return InventoryAccepted(DayAnchor._(dayId, versionWire));
  }
}

/// Confirmed milligrams split by custody. Saleable stock is the available part.
final class QuantityTriple {
  const QuantityTriple({
    required this.availableMilligrams,
    required this.pendingMilligrams,
    required this.heldMilligrams,
    required this.availableCount,
    required this.pendingCount,
    required this.heldCount,
  });

  final BigInt availableMilligrams;
  final BigInt pendingMilligrams;
  final BigInt heldMilligrams;
  final BigInt? availableCount;
  final BigInt? pendingCount;
  final BigInt? heldCount;

  /// Shop-owned stock that can be sold. Pending and custody stay outside it.
  BigInt get saleableMilligrams => availableMilligrams;

  BigInt? get saleableCount => availableCount;
}

/// Measured weight is the stock quantity. Nominal identity is a catalog label.
final class MeasuredIdentity {
  const MeasuredIdentity({
    required this.actualMilligrams,
    this.nominalMilligrams,
  });

  final BigInt actualMilligrams;
  final BigInt? nominalMilligrams;

  BigInt get stockMilligrams => actualMilligrams;

  bool get nominalDiffers =>
      nominalMilligrams != null && nominalMilligrams != actualMilligrams;
}

enum EffectUnit { milligrams, count, piastres }

final class InventoryEffect {
  const InventoryEffect({
    required this.bucket,
    required this.unit,
    required this.delta,
    this.category,
    this.karat,
    this.method,
  });

  final String bucket;
  final EffectUnit unit;
  final BigInt delta;
  final String? category;
  final int? karat;
  final String? method;

  @override
  bool operator ==(Object other) =>
      other is InventoryEffect &&
      other.bucket == bucket &&
      other.unit == unit &&
      other.delta == delta &&
      other.category == category &&
      other.karat == karat &&
      other.method == method;

  @override
  int get hashCode => Object.hash(bucket, unit, delta, category, karat, method);
}

final class ReviewedCommand {
  const ReviewedCommand({
    required this.kind,
    required this.payload,
    required this.effects,
    this.notes = const [],
    this.partial,
  });

  final String kind;
  final Map<String, Object?> payload;
  final List<InventoryEffect> effects;
  final List<String> notes;

  /// True when a receipt or obligation is only partly closed. Null when unused.
  final bool? partial;

  Map<String, Object?> envelope(String idempotencyKey) => {
    'p_idempotency_key': idempotencyKey,
    'p_payload': payload,
  };
}

final class LotSnapshot {
  const LotSnapshot({
    required this.id,
    required this.productId,
    required this.productName,
    required this.displayName,
    required this.category,
    required this.karat,
    required this.stockClass,
    required this.remainingMilligrams,
    required this.remainingCount,
    required this.originalMilligrams,
    required this.originalCount,
    required this.legacyAggregate,
    this.denominationId,
    this.nominalMilligrams,
    this.coinTypeId,
    this.coinNominalMilligrams,
    this.traderId,
    this.originOperationId,
  });

  final String id;
  final String productId;
  final String productName;
  final String displayName;
  final String category;
  final int karat;
  final StockClass stockClass;
  final BigInt remainingMilligrams;
  final BigInt? remainingCount;
  final BigInt originalMilligrams;
  final BigInt? originalCount;
  final bool legacyAggregate;
  final String? denominationId;
  final BigInt? nominalMilligrams;
  final String? coinTypeId;
  final BigInt? coinNominalMilligrams;
  final String? traderId;
  final String? originOperationId;

  bool get tracksCount => category != 'scrap';
}

final class ReceiptSnapshot {
  const ReceiptSnapshot({
    required this.id,
    required this.ownerKind,
    required this.policy,
    required this.counterpartyName,
    required this.productId,
    required this.lotId,
    required this.category,
    required this.karat,
    required this.remainingMilligrams,
    required this.remainingCount,
    this.traderId,
    this.productName = '',
  });

  final String id;
  final String ownerKind;
  final String policy;
  final String? traderId;
  final String counterpartyName;
  final String productId;
  final String lotId;
  final String category;
  final int karat;
  final BigInt remainingMilligrams;
  final BigInt? remainingCount;
  final String productName;
}

final class AdditionLine {
  const AdditionLine({
    required this.itemName,
    required this.category,
    required this.karat,
    required this.milligrams,
    required this.count,
    this.denominationId,
    this.nominalMilligrams,
    this.coinTypeId,
    this.coinNominalMilligrams,
  });

  final String itemName;
  final String category;
  final int karat;
  final BigInt milligrams;
  final BigInt? count;
  final String? denominationId;
  final BigInt? nominalMilligrams;
  final String? coinTypeId;
  final BigInt? coinNominalMilligrams;
}

final class CashDelta {
  const CashDelta({
    required this.method,
    required this.piastres,
    this.knownBalance,
  });

  final String method;
  final BigInt piastres;
  final BigInt? knownBalance;
}

sealed class MetalDelta {
  const MetalDelta();
}

final class MetalDecrease extends MetalDelta {
  const MetalDecrease({
    required this.lot,
    required this.milligrams,
    required this.count,
  });

  final LotSnapshot lot;
  final BigInt milligrams;
  final BigInt? count;
}

final class MetalIncrease extends MetalDelta {
  const MetalIncrease({
    required this.itemName,
    required this.category,
    required this.karat,
    required this.milligrams,
    required this.count,
  });

  final String itemName;
  final String category;
  final int karat;
  final BigInt milligrams;
  final BigInt? count;
}

final class TenderDraft {
  const TenderDraft({required this.method, required this.piastres});

  final String method;
  final BigInt piastres;
}

sealed class TransferObligation {
  const TransferObligation();
}

final class EgpObligation extends TransferObligation {
  const EgpObligation({required this.pricePiastres, required this.tenders});

  final BigInt pricePiastres;
  final List<TenderDraft> tenders;
}

final class GoldObligationDraft extends TransferObligation {
  const GoldObligationDraft({required this.karat, required this.milligrams});

  final int karat;
  final BigInt milligrams;
}

final class DeliveryDraft {
  const DeliveryDraft({
    required this.lot,
    required this.milligrams,
    required this.count,
  });

  final LotSnapshot lot;
  final BigInt milligrams;
  final BigInt? count;
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
final _canonical = RegExp(r'^(0|[1-9][0-9]*)$');

bool inventoryPairAllowed(String category, int karat) {
  if (category == 'scrap') return ScrapKarats.allowed.contains(karat);
  return StockCategory.byCode(category)?.allowsKarat(karat) ?? false;
}

bool inventoryUuid(String value) => _uuid.hasMatch(value);

String signedWire(BigInt value) =>
    value.isNegative ? '-${value.abs()}' : value.toString();

InventoryResult<BigInt> parseSignedWire(String input) {
  if (input.startsWith('-')) {
    final magnitude = input.substring(1);
    if (magnitude == '9223372036854775808') {
      return InventoryAccepted(PostgresInteger.min);
    }
    if (!_canonical.hasMatch(magnitude)) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    final value = -BigInt.parse(magnitude);
    if (!PostgresInteger.fits(value)) {
      return const InventoryRejected(InventoryIssueCode.overflow);
    }
    return InventoryAccepted(value);
  }
  if (!_canonical.hasMatch(input)) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final value = BigInt.parse(input);
  if (!PostgresInteger.fits(value)) {
    return const InventoryRejected(InventoryIssueCode.overflow);
  }
  return InventoryAccepted(value);
}

InventoryResult<String> _label(String raw, {required int max}) {
  final text = raw.trim();
  if (text.isEmpty || text.length > max) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  return InventoryAccepted(text);
}

InventoryResult<String> _reason(String raw) => _label(raw, max: 1000);

Map<String, Object?> _anchor(String kind, DayAnchor day) => {
  'version': 1,
  'kind': kind,
  'expected_day_id': day.dayId,
  'expected_day_version': day.versionWire,
};

InventoryEffect _mg(String bucket, BigInt delta, String category, int karat) =>
    InventoryEffect(
      bucket: bucket,
      unit: EffectUnit.milligrams,
      delta: delta,
      category: category,
      karat: karat,
    );

InventoryEffect _count(
  String bucket,
  BigInt delta,
  String category,
  int karat,
) => InventoryEffect(
  bucket: bucket,
  unit: EffectUnit.count,
  delta: delta,
  category: category,
  karat: karat,
);

InventoryIssueCode? _take({
  required bool scrap,
  required BigInt remainingMg,
  required BigInt? remainingCount,
  required BigInt milligrams,
  required BigInt? count,
}) {
  if (!PostgresInteger.fits(milligrams) ||
      (count != null && !PostgresInteger.fits(count)) ||
      !PostgresInteger.fits(remainingMg)) {
    return InventoryIssueCode.overflow;
  }
  if (milligrams <= BigInt.zero || milligrams > remainingMg) {
    return milligrams <= BigInt.zero
        ? InventoryIssueCode.invalidInput
        : InventoryIssueCode.exceedsRemaining;
  }
  if (scrap) {
    if (count != null) return InventoryIssueCode.invalidInput;
    return null;
  }
  if (count == null || remainingCount == null || count <= BigInt.zero) {
    return InventoryIssueCode.invalidInput;
  }
  if (count > remainingCount) return InventoryIssueCode.exceedsRemaining;
  final leftMg = remainingMg - milligrams;
  final leftCount = remainingCount - count;
  if ((leftMg == BigInt.zero) != (leftCount == BigInt.zero)) {
    return InventoryIssueCode.stockPairMismatch;
  }
  return null;
}

Map<String, Object?> _quantityKeys(
  String category,
  BigInt milligrams,
  BigInt? count,
) => {
  'milligrams': milligrams.toString(),
  'count': category == 'scrap' ? null : count!.toString(),
};

InventoryResult<ReviewedCommand> reviewAddition({
  required DayAnchor day,
  required String reason,
  required List<AdditionLine> lines,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (lines.isEmpty || lines.length > 50) {
    return const InventoryRejected(InventoryIssueCode.emptyCommand);
  }
  final payloadLines = <Map<String, Object?>>[];
  final effects = <InventoryEffect>[];
  final notes = <String>[];
  for (final line in lines) {
    final name = _label(line.itemName, max: 120);
    if (name is InventoryRejected<String>) return InventoryRejected(name.code);
    if (!inventoryPairAllowed(line.category, line.karat) ||
        line.milligrams <= BigInt.zero) {
      return InventoryRejected(
        inventoryPairAllowed(line.category, line.karat)
            ? InventoryIssueCode.invalidInput
            : InventoryIssueCode.unsupportedCategoryKarat,
      );
    }
    if (!PostgresInteger.fits(line.milligrams) ||
        (line.count != null && !PostgresInteger.fits(line.count!))) {
      return const InventoryRejected(InventoryIssueCode.overflow);
    }
    if (line.category == 'scrap') {
      if (line.count != null) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
    } else if (line.count == null || line.count! <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (line.denominationId != null &&
        (line.category != 'bullion' || !inventoryUuid(line.denominationId!))) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (line.coinTypeId != null &&
        (line.category != 'coin' || !inventoryUuid(line.coinTypeId!))) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (line.nominalMilligrams != null &&
        line.nominalMilligrams! <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (line.coinNominalMilligrams != null &&
        line.coinNominalMilligrams! <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    final identity = MeasuredIdentity(
      actualMilligrams: line.milligrams,
      nominalMilligrams: line.nominalMilligrams ?? line.coinNominalMilligrams,
    );
    if (identity.nominalDiffers) notes.add('nominal_not_stock');
    payloadLines.add({
      'item_name': (name as InventoryAccepted<String>).value,
      'category': line.category,
      'karat': line.karat,
      'milligrams': identity.stockMilligrams.toString(),
      'count': line.category == 'scrap' ? null : line.count!.toString(),
      'denomination_id': line.denominationId,
      'coin_type_id': line.coinTypeId,
    });
    effects.add(
      _mg('owned_available', line.milligrams, line.category, line.karat),
    );
    if (line.category != 'scrap') {
      effects.add(
        _count('owned_available', line.count!, line.category, line.karat),
      );
    }
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_addition',
      payload: {
        ..._anchor('inventory_addition', day),
        'reason': (why as InventoryAccepted<String>).value,
        'lines': payloadLines,
      },
      effects: effects,
      notes: notes,
    ),
  );
}

InventoryResult<ReviewedCommand> reviewRemoval({
  required DayAnchor day,
  required String reason,
  required List<({LotSnapshot lot, BigInt milligrams, BigInt? count})> lines,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (lines.isEmpty || lines.length > 50) {
    return const InventoryRejected(InventoryIssueCode.emptyCommand);
  }
  final seen = <String>{};
  final payloadLines = <Map<String, Object?>>[];
  final effects = <InventoryEffect>[];
  for (final line in lines) {
    if (!seen.add(line.lot.id)) {
      return const InventoryRejected(InventoryIssueCode.duplicateLine);
    }
    if (line.lot.stockClass != StockClass.ownedAvailable) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    final issue = _take(
      scrap: !line.lot.tracksCount,
      remainingMg: line.lot.remainingMilligrams,
      remainingCount: line.lot.remainingCount,
      milligrams: line.milligrams,
      count: line.count,
    );
    if (issue != null) return InventoryRejected(issue);
    payloadLines.add({
      'lot_id': line.lot.id,
      ..._quantityKeys(line.lot.category, line.milligrams, line.count),
    });
    effects.add(
      _mg(
        'owned_available',
        -line.milligrams,
        line.lot.category,
        line.lot.karat,
      ),
    );
    if (line.lot.tracksCount) {
      effects.add(
        _count(
          'owned_available',
          -line.count!,
          line.lot.category,
          line.lot.karat,
        ),
      );
    }
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_removal',
      payload: {
        ..._anchor('inventory_removal', day),
        'reason': (why as InventoryAccepted<String>).value,
        'lines': payloadLines,
      },
      effects: effects,
    ),
  );
}

InventoryResult<ReviewedCommand> reviewCorrection({
  required DayAnchor day,
  required String reason,
  required List<CashDelta> cashDeltas,
  required List<MetalDelta> metalDeltas,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (cashDeltas.length > 4 || metalDeltas.length > 50) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (cashDeltas.isEmpty && metalDeltas.isEmpty) {
    return const InventoryRejected(InventoryIssueCode.emptyCommand);
  }
  final seen = <String>{};
  final cashPayload = <Map<String, Object?>>[];
  final metalPayload = <Map<String, Object?>>[];
  final effects = <InventoryEffect>[];
  for (final delta in cashDeltas) {
    if (CashMethod.byCode(delta.method) == null || !seen.add(delta.method)) {
      return InventoryRejected(
        seen.contains(delta.method)
            ? InventoryIssueCode.duplicateLine
            : InventoryIssueCode.invalidInput,
      );
    }
    if (delta.piastres == BigInt.zero ||
        !PostgresInteger.fits(delta.piastres)) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (delta.piastres.isNegative) {
      final balance = delta.knownBalance;
      if (balance == null) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
      final next = PostgresInteger.checkedAdd(balance, delta.piastres);
      if (next == null) {
        return const InventoryRejected(InventoryIssueCode.overflow);
      }
      if (next.isNegative) {
        return const InventoryRejected(InventoryIssueCode.negativeBalance);
      }
    }
    cashPayload.add({
      'method': delta.method,
      'piastres': signedWire(delta.piastres),
    });
    effects.add(
      InventoryEffect(
        bucket: 'cash',
        unit: EffectUnit.piastres,
        delta: delta.piastres,
        method: delta.method,
      ),
    );
  }
  final lots = <String>{};
  for (final delta in metalDeltas) {
    if (delta is MetalDecrease) {
      if (delta.lot.stockClass != StockClass.ownedAvailable) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
      if (!lots.add(delta.lot.id)) {
        return const InventoryRejected(InventoryIssueCode.duplicateLine);
      }
      if (!delta.milligrams.isNegative) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
      final takeMg = delta.milligrams.abs();
      if (delta.lot.tracksCount) {
        if (delta.count == null || !delta.count!.isNegative) {
          return const InventoryRejected(InventoryIssueCode.invalidInput);
        }
      } else if (delta.count != null) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
      final issue = _take(
        scrap: !delta.lot.tracksCount,
        remainingMg: delta.lot.remainingMilligrams,
        remainingCount: delta.lot.remainingCount,
        milligrams: takeMg,
        count: delta.count?.abs(),
      );
      if (issue != null) return InventoryRejected(issue);
      metalPayload.add({
        'lot_id': delta.lot.id,
        'milligrams': signedWire(delta.milligrams),
        'count': delta.lot.tracksCount ? signedWire(delta.count!) : null,
      });
      effects.add(
        _mg(
          'owned_available',
          delta.milligrams,
          delta.lot.category,
          delta.lot.karat,
        ),
      );
      if (delta.lot.tracksCount) {
        effects.add(
          _count(
            'owned_available',
            delta.count!,
            delta.lot.category,
            delta.lot.karat,
          ),
        );
      }
    } else if (delta is MetalIncrease) {
      final name = _label(delta.itemName, max: 120);
      if (name is InventoryRejected<String>) {
        return InventoryRejected(name.code);
      }
      if (!inventoryPairAllowed(delta.category, delta.karat) ||
          delta.milligrams <= BigInt.zero) {
        return const InventoryRejected(
          InventoryIssueCode.unsupportedCategoryKarat,
        );
      }
      if (delta.category == 'scrap') {
        if (delta.count != null) {
          return const InventoryRejected(InventoryIssueCode.invalidInput);
        }
      } else if (delta.count == null || delta.count! <= BigInt.zero) {
        return const InventoryRejected(InventoryIssueCode.invalidInput);
      }
      metalPayload.add({
        'item_name': (name as InventoryAccepted<String>).value,
        'category': delta.category,
        'karat': delta.karat,
        'milligrams': delta.milligrams.toString(),
        'count': delta.category == 'scrap' ? null : delta.count!.toString(),
      });
      effects.add(
        _mg('owned_available', delta.milligrams, delta.category, delta.karat),
      );
      if (delta.category != 'scrap') {
        effects.add(
          _count('owned_available', delta.count!, delta.category, delta.karat),
        );
      }
    }
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_correction',
      payload: {
        ..._anchor('inventory_correction', day),
        'reason': (why as InventoryAccepted<String>).value,
        'cash_deltas': cashPayload,
        'metal_deltas': metalPayload,
      },
      effects: effects,
      notes: const ['adjustment_clearing'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewConversion({
  required DayAnchor day,
  required String reason,
  required LotSnapshot source,
  required String destinationCategory,
  required String itemName,
  required BigInt milligrams,
  required BigInt? sourceCount,
  required BigInt? destinationCount,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  final name = _label(itemName, max: 120);
  if (name is InventoryRejected<String>) return InventoryRejected(name.code);
  if (source.stockClass != StockClass.ownedAvailable ||
      source.category == destinationCategory ||
      !inventoryPairAllowed(source.category, source.karat) ||
      !inventoryPairAllowed(destinationCategory, source.karat)) {
    return const InventoryRejected(InventoryIssueCode.unsupportedCategoryKarat);
  }
  final issue = _take(
    scrap: !source.tracksCount,
    remainingMg: source.remainingMilligrams,
    remainingCount: source.remainingCount,
    milligrams: milligrams,
    count: sourceCount,
  );
  if (issue != null) return InventoryRejected(issue);
  if (destinationCategory == 'scrap') {
    if (destinationCount != null) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
  } else if (destinationCount == null || destinationCount <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final effects = <InventoryEffect>[
    _mg('owned_available', -milligrams, source.category, source.karat),
    _mg('owned_available', milligrams, destinationCategory, source.karat),
  ];
  if (source.tracksCount) {
    effects.add(
      _count('owned_available', -sourceCount!, source.category, source.karat),
    );
  }
  if (destinationCategory != 'scrap') {
    effects.add(
      _count(
        'owned_available',
        destinationCount!,
        destinationCategory,
        source.karat,
      ),
    );
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_conversion',
      payload: {
        ..._anchor('inventory_conversion', day),
        'reason': (why as InventoryAccepted<String>).value,
        'karat': source.karat,
        'milligrams': milligrams.toString(),
        'source_category': source.category,
        'source_lot_id': source.id,
        'source_count': source.tracksCount ? sourceCount!.toString() : null,
        'destination_category': destinationCategory,
        'destination_count': destinationCategory == 'scrap'
            ? null
            : destinationCount!.toString(),
        'item_name': (name as InventoryAccepted<String>).value,
      },
      effects: effects,
      notes: const ['same_karat'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewReceipt({
  required DayAnchor day,
  required String ownerKind,
  required String? traderId,
  required String counterpartyName,
  required String productName,
  required String category,
  required int karat,
  required BigInt milligrams,
  required BigInt? count,
  required String recognition,
  required String note,
  String? denominationId,
  BigInt? nominalMilligrams,
  String? coinTypeId,
}) {
  final party = _label(counterpartyName, max: 200);
  if (party is InventoryRejected<String>) return InventoryRejected(party.code);
  final product = _label(productName, max: 120);
  if (product is InventoryRejected<String>) {
    return InventoryRejected(product.code);
  }
  final remark = note.trim();
  if (remark.length > 1000) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (!inventoryPairAllowed(category, karat) || milligrams <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.unsupportedCategoryKarat);
  }
  if (category == 'scrap') {
    if (count != null) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
  } else if (count == null || count <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final shopOwned = ownerKind == 'shop';
  final traderOwned = ownerKind == 'trader';
  if (!shopOwned && !traderOwned) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (traderOwned) {
    if (recognition != 'custody' ||
        traderId == null ||
        !inventoryUuid(traderId)) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
  } else if (traderId != null ||
      (recognition != 'immediate' && recognition != 'deferred')) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (denominationId != null &&
      (category != 'bullion' || !inventoryUuid(denominationId))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (coinTypeId != null &&
      (category != 'coin' || !inventoryUuid(coinTypeId))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (nominalMilligrams != null && nominalMilligrams <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final bucket = switch (recognition) {
    'immediate' => 'owned_available',
    'deferred' => 'owned_pending',
    _ => 'trader_custody',
  };
  final effects = <InventoryEffect>[_mg(bucket, milligrams, category, karat)];
  if (category != 'scrap') effects.add(_count(bucket, count!, category, karat));
  final notes = <String>[
    if (recognition == 'deferred') 'pending_not_saleable',
    if (recognition == 'custody') 'custody_not_owned',
    if (recognition == 'immediate') 'owned_now',
    if (nominalMilligrams != null && nominalMilligrams != milligrams)
      'nominal_not_stock',
  ];
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_receipt',
      payload: {
        ..._anchor('inventory_receipt', day),
        'owner_kind': ownerKind,
        'trader_id': traderId,
        'counterparty_name': (party as InventoryAccepted<String>).value,
        'product_name': (product as InventoryAccepted<String>).value,
        'category': category,
        'karat': karat,
        ..._quantityKeys(category, milligrams, count),
        'recognition': recognition,
        'denomination_id': denominationId,
        'coin_type_id': coinTypeId,
        'note': remark,
      },
      effects: effects,
      notes: notes,
    ),
  );
}

InventoryResult<ReviewedCommand> reviewRecognition({
  required DayAnchor day,
  required String reason,
  required ReceiptSnapshot receipt,
  required BigInt milligrams,
  required BigInt? count,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (receipt.policy == 'custody') {
    return const InventoryRejected(InventoryIssueCode.custodyRequiresTransfer);
  }
  if (receipt.policy != 'deferred' || receipt.ownerKind != 'shop') {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final issue = _take(
    scrap: receipt.category == 'scrap',
    remainingMg: receipt.remainingMilligrams,
    remainingCount: receipt.remainingCount,
    milligrams: milligrams,
    count: count,
  );
  if (issue != null) return InventoryRejected(issue);
  final effects = <InventoryEffect>[
    _mg('owned_pending', -milligrams, receipt.category, receipt.karat),
    _mg('owned_available', milligrams, receipt.category, receipt.karat),
  ];
  if (receipt.category != 'scrap') {
    effects
      ..add(_count('owned_pending', -count!, receipt.category, receipt.karat))
      ..add(_count('owned_available', count, receipt.category, receipt.karat));
  }
  final full = milligrams == receipt.remainingMilligrams;
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'inventory_recognition',
      payload: {
        ..._anchor('inventory_recognition', day),
        'receipt_id': receipt.id,
        ..._quantityKeys(receipt.category, milligrams, count),
        'reason': (why as InventoryAccepted<String>).value,
      },
      effects: effects,
      notes: [full ? 'full_quantity' : 'partial_quantity'],
      partial: !full,
    ),
  );
}

InventoryResult<ReviewedCommand> reviewManualLink({
  required DayAnchor day,
  required String reason,
  required ReceiptSnapshot receipt,
  required LotSnapshot lot,
  required String manualOperationId,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (receipt.policy == 'custody') {
    return const InventoryRejected(InventoryIssueCode.custodyRequiresTransfer);
  }
  if (receipt.policy != 'deferred' ||
      receipt.ownerKind != 'shop' ||
      !inventoryUuid(manualOperationId) ||
      lot.originOperationId != manualOperationId ||
      lot.stockClass != StockClass.ownedAvailable ||
      lot.productId != receipt.productId ||
      lot.category != receipt.category ||
      lot.karat != receipt.karat ||
      lot.remainingMilligrams != lot.originalMilligrams ||
      lot.remainingCount != lot.originalCount) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final issue = _take(
    scrap: receipt.category == 'scrap',
    remainingMg: receipt.remainingMilligrams,
    remainingCount: receipt.remainingCount,
    milligrams: lot.originalMilligrams,
    count: lot.originalCount,
  );
  if (issue != null) return InventoryRejected(issue);
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'receipt_manual_allocation',
      payload: {
        ..._anchor('receipt_manual_allocation', day),
        'receipt_id': receipt.id,
        'manual_operation_id': manualOperationId,
        'lot_id': lot.id,
        ..._quantityKeys(
          lot.category,
          lot.originalMilligrams,
          lot.originalCount,
        ),
        'reason': (why as InventoryAccepted<String>).value,
      },
      effects: [
        _mg('owned_pending', -lot.originalMilligrams, lot.category, lot.karat),
        if (lot.tracksCount)
          _count('owned_pending', -lot.originalCount!, lot.category, lot.karat),
      ],
      notes: const ['no_second_stock_posting'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewOwnershipTransfer({
  required DayAnchor day,
  required String reason,
  required ReceiptSnapshot receipt,
  required BigInt milligrams,
  required BigInt? count,
  required TransferObligation obligation,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (receipt.policy != 'custody' || receipt.ownerKind != 'trader') {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final issue = _take(
    scrap: receipt.category == 'scrap',
    remainingMg: receipt.remainingMilligrams,
    remainingCount: receipt.remainingCount,
    milligrams: milligrams,
    count: count,
  );
  if (issue != null) return InventoryRejected(issue);
  final effects = <InventoryEffect>[
    _mg('trader_custody', -milligrams, receipt.category, receipt.karat),
    _mg('owned_available', milligrams, receipt.category, receipt.karat),
  ];
  if (receipt.category != 'scrap') {
    effects
      ..add(_count('trader_custody', -count!, receipt.category, receipt.karat))
      ..add(_count('owned_available', count, receipt.category, receipt.karat));
  }
  final payload = <String, Object?>{
    ..._anchor('ownership_transfer', day),
    'receipt_id': receipt.id,
    ..._quantityKeys(receipt.category, milligrams, count),
    'reason': (why as InventoryAccepted<String>).value,
  };
  if (obligation is EgpObligation) {
    if (obligation.pricePiastres <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    final tenders = _tenders(obligation.tenders);
    if (tenders is InventoryRejected<List<Map<String, Object?>>>) {
      return InventoryRejected(tenders.code);
    }
    final rows =
        (tenders as InventoryAccepted<List<Map<String, Object?>>>).value;
    final sum = PostgresInteger.checkedSum([
      for (final row in obligation.tenders) row.piastres,
    ]);
    if (sum == null) {
      return const InventoryRejected(InventoryIssueCode.overflow);
    }
    if (sum > obligation.pricePiastres) {
      return const InventoryRejected(InventoryIssueCode.tenderMismatch);
    }
    final payable = obligation.pricePiastres - sum;
    payload['price_piastres'] = obligation.pricePiastres.toString();
    payload['tenders'] = rows;
    if (payable > BigInt.zero) {
      payload['purchase_obligation_piastres'] = payable.toString();
      effects.add(
        InventoryEffect(
          bucket: 'egp_payable',
          unit: EffectUnit.piastres,
          delta: payable,
        ),
      );
    }
    for (final tender in obligation.tenders) {
      effects.add(
        InventoryEffect(
          bucket: 'cash',
          unit: EffectUnit.piastres,
          delta: -tender.piastres,
          method: tender.method,
        ),
      );
    }
  } else if (obligation is GoldObligationDraft) {
    if (obligation.karat != receipt.karat ||
        !ScrapKarats.allowed.contains(obligation.karat) ||
        obligation.milligrams <= BigInt.zero) {
      return InventoryRejected(
        obligation.karat == receipt.karat
            ? InventoryIssueCode.invalidInput
            : InventoryIssueCode.karatMismatch,
      );
    }
    payload['obligation_karat'] = obligation.karat;
    payload['obligation_milligrams'] = obligation.milligrams.toString();
    effects.add(
      InventoryEffect(
        bucket: 'gold_payable',
        unit: EffectUnit.milligrams,
        delta: obligation.milligrams,
        karat: obligation.karat,
      ),
    );
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'ownership_transfer',
      payload: payload,
      effects: effects,
      notes: [
        obligation is EgpObligation
            ? 'egp_obligation_only'
            : 'gold_obligation_only',
        milligrams == receipt.remainingMilligrams
            ? 'full_quantity'
            : 'partial_quantity',
      ],
      partial: milligrams != receipt.remainingMilligrams,
    ),
  );
}

InventoryResult<List<Map<String, Object?>>> _tenders(
  List<TenderDraft> tenders,
) {
  if (tenders.length > 4) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final seen = <String>{};
  final rows = <Map<String, Object?>>[];
  for (final tender in tenders) {
    if (CashMethod.byCode(tender.method) == null ||
        !seen.add(tender.method) ||
        tender.piastres <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    rows.add({'method': tender.method, 'piastres': tender.piastres.toString()});
  }
  return InventoryAccepted(rows);
}

InventoryResult<ReviewedCommand> reviewGoldAcquisition({
  required DayAnchor day,
  required String itemName,
  required String category,
  required int karat,
  required BigInt milligrams,
  required BigInt? count,
  required int obligationKarat,
  required BigInt obligationMilligrams,
  required String counterpartyName,
  required String note,
  String? denominationId,
  String? coinTypeId,
  BigInt? nominalMilligrams,
  String? traderId,
}) {
  if (traderId != null && !inventoryUuid(traderId)) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final name = _label(itemName, max: 120);
  if (name is InventoryRejected<String>) return InventoryRejected(name.code);
  final party = _label(counterpartyName, max: 200);
  if (party is InventoryRejected<String>) return InventoryRejected(party.code);
  final remark = note.trim();
  if (remark.length > 1000 ||
      !inventoryPairAllowed(category, karat) ||
      milligrams <= BigInt.zero ||
      !ScrapKarats.allowed.contains(obligationKarat) ||
      obligationMilligrams <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (category == 'scrap') {
    if (count != null) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
  } else if (count == null || count <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (denominationId != null &&
      (category != 'bullion' || !inventoryUuid(denominationId))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  if (coinTypeId != null &&
      (category != 'coin' || !inventoryUuid(coinTypeId))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final effects = <InventoryEffect>[
    _mg('owned_available', milligrams, category, karat),
    if (category != 'scrap') _count('owned_available', count!, category, karat),
    InventoryEffect(
      bucket: 'gold_payable',
      unit: EffectUnit.milligrams,
      delta: obligationMilligrams,
      karat: obligationKarat,
    ),
  ];
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'gold_obligation_acquisition',
      payload: {
        ..._anchor('gold_obligation_acquisition', day),
        'category': category,
        'karat': karat,
        ..._quantityKeys(category, milligrams, count),
        'item_name': (name as InventoryAccepted<String>).value,
        'obligation_karat': obligationKarat,
        'obligation_milligrams': obligationMilligrams.toString(),
        'counterparty_name': (party as InventoryAccepted<String>).value,
        'note': remark,
        'denomination_id': denominationId,
        'coin_type_id': coinTypeId,
        'trader_id': traderId,
      },
      effects: effects,
      notes: [
        'gold_obligation_only',
        if (nominalMilligrams != null && nominalMilligrams != milligrams)
          'nominal_not_stock',
        if (obligationKarat != karat) 'explicit_obligation_karat',
        if (traderId != null) 'linked_trader',
      ],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewGoldSettlement({
  required DayAnchor day,
  required String reason,
  required String obligationOperationId,
  required int obligationKarat,
  required BigInt remainingMilligrams,
  required List<DeliveryDraft> deliveries,
}) {
  final why = _reason(reason);
  if (why is InventoryRejected<String>) return InventoryRejected(why.code);
  if (!inventoryUuid(obligationOperationId) ||
      deliveries.isEmpty ||
      deliveries.length > 20 ||
      remainingMilligrams <= BigInt.zero) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final seen = <String>{};
  final rows = <Map<String, Object?>>[];
  final effects = <InventoryEffect>[];
  var sum = BigInt.zero;
  for (final delivery in deliveries) {
    if (delivery.lot.karat != obligationKarat) {
      return const InventoryRejected(InventoryIssueCode.karatMismatch);
    }
    if (delivery.lot.stockClass != StockClass.ownedAvailable) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    if (!seen.add(delivery.lot.id)) {
      return const InventoryRejected(InventoryIssueCode.duplicateLine);
    }
    final issue = _take(
      scrap: !delivery.lot.tracksCount,
      remainingMg: delivery.lot.remainingMilligrams,
      remainingCount: delivery.lot.remainingCount,
      milligrams: delivery.milligrams,
      count: delivery.count,
    );
    if (issue != null) return InventoryRejected(issue);
    final next = PostgresInteger.checkedAdd(sum, delivery.milligrams);
    if (next == null) {
      return const InventoryRejected(InventoryIssueCode.overflow);
    }
    sum = next;
    rows.add({
      'lot_id': delivery.lot.id,
      ..._quantityKeys(
        delivery.lot.category,
        delivery.milligrams,
        delivery.count,
      ),
    });
    effects.add(
      _mg(
        'owned_available',
        -delivery.milligrams,
        delivery.lot.category,
        delivery.lot.karat,
      ),
    );
    if (delivery.lot.tracksCount) {
      effects.add(
        _count(
          'owned_available',
          -delivery.count!,
          delivery.lot.category,
          delivery.lot.karat,
        ),
      );
    }
  }
  if (sum > remainingMilligrams) {
    return const InventoryRejected(InventoryIssueCode.exceedsRemaining);
  }
  effects.add(
    InventoryEffect(
      bucket: 'gold_payable',
      unit: EffectUnit.milligrams,
      delta: -sum,
      karat: obligationKarat,
    ),
  );
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'gold_obligation_settlement',
      payload: {
        ..._anchor('gold_obligation_settlement', day),
        'obligation_operation_id': obligationOperationId,
        'deliveries': rows,
        'reason': (why as InventoryAccepted<String>).value,
      },
      effects: effects,
      notes: [
        sum == remainingMilligrams ? 'full_settlement' : 'partial_settlement',
      ],
      partial: sum != remainingMilligrams,
    ),
  );
}

InventoryResult<ReviewedCommand> reviewProduct({
  required DayAnchor day,
  required String name,
  required String category,
  required int karat,
}) {
  final label = _label(name, max: 120);
  if (label is InventoryRejected<String>) return InventoryRejected(label.code);
  if (!inventoryPairAllowed(category, karat)) {
    return const InventoryRejected(InventoryIssueCode.unsupportedCategoryKarat);
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'product',
      payload: {
        ..._anchor('product', day),
        'name': (label as InventoryAccepted<String>).value,
        'category': category,
        'karat': karat,
      },
      effects: const [],
      notes: const ['catalog_only'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewBullionDenomination({
  required DayAnchor day,
  required String label,
  required BigInt nominalMilligrams,
  required bool active,
}) {
  final name = _label(label, max: 120);
  if (name is InventoryRejected<String>) return InventoryRejected(name.code);
  if (nominalMilligrams <= BigInt.zero ||
      !PostgresInteger.fits(nominalMilligrams)) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'bullion_denomination',
      payload: {
        ..._anchor('bullion_denomination', day),
        'label': (name as InventoryAccepted<String>).value,
        'nominal_milligrams': nominalMilligrams.toString(),
        'active': active,
      },
      effects: const [],
      notes: const ['nominal_not_stock', 'catalog_only'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewCoinType({
  required DayAnchor day,
  required String label,
  required BigInt? nominalMilligrams,
  required bool active,
}) {
  final name = _label(label, max: 120);
  if (name is InventoryRejected<String>) return InventoryRejected(name.code);
  if (nominalMilligrams != null &&
      (nominalMilligrams <= BigInt.zero ||
          !PostgresInteger.fits(nominalMilligrams))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'coin_type',
      payload: {
        ..._anchor('coin_type', day),
        'label': (name as InventoryAccepted<String>).value,
        'nominal_milligrams': nominalMilligrams?.toString(),
        'active': active,
      },
      effects: const [],
      notes: const ['nominal_not_stock', 'catalog_only'],
    ),
  );
}

InventoryResult<ReviewedCommand> reviewTraderSave({
  required DayAnchor day,
  required String displayName,
  required String phone,
  required String note,
  required bool active,
}) {
  final name = _label(displayName, max: 200);
  if (name is InventoryRejected<String>) return InventoryRejected(name.code);
  final trimmedPhone = phone.trim();
  final trimmedNote = note.trim();
  if (trimmedPhone.length > 20 ||
      trimmedNote.length > 1000 ||
      (trimmedPhone.isNotEmpty &&
          !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(trimmedPhone))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  return InventoryAccepted(
    ReviewedCommand(
      kind: 'trader',
      payload: {
        ..._anchor('trader', day),
        'display_name': (name as InventoryAccepted<String>).value,
        'phone': trimmedPhone,
        'note': trimmedNote,
        'active': active,
      },
      effects: const [],
      notes: const ['catalog_only'],
    ),
  );
}

final _phoneWire = RegExp(r'^\+?[0-9]{7,15}$');

/// Named owned-available lot. The wrapper version is 2; FIFO v1 is untouched.
InventoryResult<ReviewedCommand> reviewExplicitLotSale({
  required DayAnchor day,
  required LotSnapshot lot,
  required BigInt milligrams,
  required BigInt? count,
  required BigInt totalPiastres,
  required List<TenderDraft> tenders,
  required String description,
  required String customerName,
  required String customerPhone,
  required String note,
  Map<String, Object?>? pricing,
}) {
  if (lot.stockClass != StockClass.ownedAvailable) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final scrap = lot.category == 'scrap';
  if (!scrap &&
      lot.category != 'worked_jewelry' &&
      lot.category != 'bullion' &&
      lot.category != 'coin') {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final kind = scrap ? 'scrap_sale' : 'sale';
  final issue = _take(
    scrap: scrap,
    remainingMg: lot.remainingMilligrams,
    remainingCount: lot.remainingCount,
    milligrams: milligrams,
    count: count,
  );
  if (issue != null) return InventoryRejected(issue);
  if (totalPiastres <= BigInt.zero || !PostgresInteger.fits(totalPiastres)) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final tenderRows = _tenders(tenders);
  if (tenderRows is InventoryRejected<List<Map<String, Object?>>>) {
    return InventoryRejected(tenderRows.code);
  }
  final rows =
      (tenderRows as InventoryAccepted<List<Map<String, Object?>>>).value;
  if (rows.isEmpty) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  final paid = PostgresInteger.checkedSum([
    for (final tender in tenders) tender.piastres,
  ]);
  if (paid == null) {
    return const InventoryRejected(InventoryIssueCode.overflow);
  }
  if (paid != totalPiastres) {
    return const InventoryRejected(InventoryIssueCode.tenderMismatch);
  }
  final itemName = lot.displayName.trim();
  final party = customerName.trim();
  final phone = customerPhone.trim();
  final remark = note.trim();
  final text = description.trim();
  if (itemName.isEmpty ||
      itemName.length > 120 ||
      text.length > 300 ||
      party.length > 200 ||
      remark.length > 1000 ||
      phone.length > 20 ||
      (phone.isNotEmpty && !_phoneWire.hasMatch(phone))) {
    return const InventoryRejected(InventoryIssueCode.invalidInput);
  }
  Map<String, Object?>? priceRow;
  if (pricing != null) {
    final base = _nonNegative(pricing['base_piastres']);
    final work = _nonNegative(pricing['workmanship_piastres']);
    final other = _nonNegative(pricing['other_charges_piastres']);
    final discount = _nonNegative(pricing['discount_piastres']);
    final label = pricing['other_charges_label'];
    if (base == null ||
        work == null ||
        other == null ||
        discount == null ||
        label is! String ||
        label.trim().length > 120 ||
        (other > BigInt.zero && label.trim().isEmpty) ||
        pricing.length != 5) {
      return const InventoryRejected(InventoryIssueCode.invalidInput);
    }
    final agreed = base + work + other - discount;
    if (agreed != totalPiastres || agreed <= BigInt.zero) {
      return const InventoryRejected(InventoryIssueCode.tenderMismatch);
    }
    priceRow = {
      'base_piastres': base.toString(),
      'workmanship_piastres': work.toString(),
      'other_charges_piastres': other.toString(),
      'other_charges_label': label.trim(),
      'discount_piastres': discount.toString(),
    };
  }
  final effects = <InventoryEffect>[
    _mg('owned_available', -milligrams, lot.category, lot.karat),
    if (!scrap) _count('owned_available', -count!, lot.category, lot.karat),
    for (final tender in tenders)
      InventoryEffect(
        bucket: 'cash',
        unit: EffectUnit.piastres,
        delta: tender.piastres,
        method: tender.method,
      ),
  ];
  return InventoryAccepted(
    ReviewedCommand(
      kind: kind,
      payload: {
        'version': 2,
        'kind': kind,
        'total_piastres': totalPiastres.toString(),
        'tenders': rows,
        'items': [
          {
            'category': lot.category,
            'karat': lot.karat,
            'milligrams': milligrams.toString(),
            'count': scrap ? null : count!.toString(),
            'item_name': itemName,
            'line_price_piastres': null,
          },
        ],
        'description': text,
        'customer_name': party,
        'customer_phone': phone,
        'note': remark,
        'expected_day_id': day.dayId,
        'expected_day_version': day.versionWire,
        'lot_selections': [
          {
            'lot_id': lot.id,
            'milligrams': milligrams.toString(),
            'count': scrap ? null : count!.toString(),
          },
        ],
        'pricing': ?priceRow,
      },
      effects: effects,
      notes: [
        'named_lot',
        if (lot.nominalMilligrams != null &&
            lot.nominalMilligrams != milligrams)
          'nominal_not_stock',
      ],
    ),
  );
}

BigInt? _nonNegative(Object? raw) {
  if (raw is! String) return null;
  final parsed = parseSignedWire(raw);
  if (parsed is! InventoryAccepted<BigInt> || parsed.value.isNegative) {
    return null;
  }
  if (!PostgresInteger.fits(parsed.value)) return null;
  return parsed.value;
}

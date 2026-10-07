import 'opening_catalog.dart';
import 'postgres_integer.dart';

/// Pure review math for audited corrections, partial returns, and exchanges.
/// Amounts stay integer piastres, milligrams, and piece counts.
sealed class CompensationResult<T> {
  const CompensationResult();
}

final class CompensationAccepted<T> extends CompensationResult<T> {
  const CompensationAccepted(this.value);
  final T value;
}

final class CompensationRejected<T> extends CompensationResult<T> {
  const CompensationRejected(this.code);
  final String code;
}

const cashMethodCodes = <String>['cash', 'instant_transfer', 'wallet', 'card'];

final class MetalEffect {
  const MetalEffect({
    required this.category,
    required this.karat,
    required this.milligrams,
    this.count,
  });

  final String category;
  final int karat;
  final BigInt milligrams;
  final BigInt? count;

  String get milligramsWire => milligrams.toString();
  String? get countWire => count?.toString();
}

final class CorrectionReview {
  const CorrectionReview({
    required this.reason,
    required this.cashDeltas,
    required this.stockDeltas,
    required this.scrapDeltas,
  });

  final String reason;
  final Map<String, BigInt> cashDeltas;
  final List<MetalEffect> stockDeltas;
  final List<MetalEffect> scrapDeltas;
}

final class ReturnLineInput {
  const ReturnLineInput({
    required this.itemIndex,
    required this.category,
    required this.karat,
    required this.scrap,
    required this.milligrams,
    required this.count,
    required this.remainderMilligrams,
    required this.remainderCount,
  });

  final int itemIndex;
  final String category;
  final int karat;
  final bool scrap;
  final BigInt milligrams;
  final BigInt count;
  final BigInt remainderMilligrams;
  final BigInt remainderCount;
}

final class PriceComponents {
  const PriceComponents({
    required this.base,
    required this.workmanship,
    required this.otherCharges,
    required this.discount,
    required this.otherChargesLabel,
    required this.remainderBase,
    required this.remainderWorkmanship,
    required this.remainderOtherCharges,
    required this.remainderDiscount,
  });

  final BigInt base;
  final BigInt workmanship;
  final BigInt otherCharges;
  final BigInt discount;
  final String otherChargesLabel;
  final BigInt remainderBase;
  final BigInt remainderWorkmanship;
  final BigInt remainderOtherCharges;
  final BigInt remainderDiscount;
}

final class PartialReturnReview {
  const PartialReturnReview({
    required this.kind,
    required this.consideration,
    required this.cancelledPayable,
    required this.cashRefund,
    required this.lines,
    required this.tenders,
    this.pricing,
  });

  final String kind;
  final BigInt consideration;
  final BigInt cancelledPayable;
  final BigInt cashRefund;
  final List<ReturnLineInput> lines;
  final Map<String, BigInt> tenders;
  final PriceComponents? pricing;

  BigInt get signedCash => kind == 'sale_return' ? -cashRefund : cashRefund;
}

final class ReplacementLine {
  const ReplacementLine({
    required this.category,
    required this.karat,
    required this.milligrams,
    required this.count,
    required this.itemName,
  });

  final String category;
  final int karat;
  final BigInt milligrams;
  final BigInt count;
  final String itemName;
}

final class ExchangeReview {
  const ExchangeReview({
    required this.returnSide,
    required this.replacementKind,
    required this.replacementCash,
    required this.replacementLines,
    required this.netCash,
    required this.netLines,
  });

  final PartialReturnReview returnSide;
  final String replacementKind;
  final BigInt replacementCash;
  final List<MetalEffect> replacementLines;
  final BigInt netCash;
  final List<MetalEffect> netLines;
}

final class ReturnRemainderItem {
  const ReturnRemainderItem({
    required this.itemIndex,
    required this.category,
    required this.karat,
    required this.itemName,
    required this.scrap,
    required this.originalMilligrams,
    required this.returnedMilligrams,
    required this.remainderMilligrams,
    this.originalCount,
    this.returnedCount,
    this.remainderCount,
  });

  final int itemIndex;
  final String category;
  final int karat;
  final String itemName;
  final bool scrap;
  final BigInt originalMilligrams;
  final BigInt returnedMilligrams;
  final BigInt remainderMilligrams;
  final BigInt? originalCount;
  final BigInt? returnedCount;
  final BigInt? remainderCount;
}

final class ReturnRemainder {
  const ReturnRemainder({
    required this.operationId,
    required this.kind,
    required this.fullyReturned,
    required this.originalImmutable,
    required this.items,
    required this.originalTotal,
    required this.returnedConsideration,
    required this.remainderConsideration,
    required this.payableRemaining,
    required this.refundableByMethod,
    required this.hasPricing,
    this.pricingRemainder,
    this.otherChargesLabel = '',
  });

  final String operationId;
  final String kind;
  final bool fullyReturned;
  final bool originalImmutable;
  final List<ReturnRemainderItem> items;
  final BigInt originalTotal;
  final BigInt returnedConsideration;
  final BigInt remainderConsideration;
  final BigInt payableRemaining;
  final Map<String, BigInt> refundableByMethod;
  final bool hasPricing;
  final Map<String, BigInt>? pricingRemainder;
  final String otherChargesLabel;

  bool get quantityRemains => items.any(
    (item) =>
        item.remainderMilligrams != BigInt.zero ||
        (item.remainderCount ?? BigInt.zero) != BigInt.zero,
  );
}

CompensationResult<CorrectionReview> reviewCountedCorrection({
  required String reason,
  required Map<String, BigInt> countedCash,
  required Map<String, BigInt> bookCash,
  required List<MetalEffect> countedStock,
  required List<MetalEffect> bookStock,
  required List<MetalEffect> countedScrap,
  required List<MetalEffect> bookScrap,
}) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty ||
      reason.length > 1000 ||
      !RegExp(r'[ء-ي]').hasMatch(trimmed)) {
    return const CompensationRejected('invalid_input');
  }
  if (countedCash.length != cashMethodCodes.length ||
      cashMethodCodes.any((method) => !countedCash.containsKey(method))) {
    return const CompensationRejected('invalid_input');
  }
  for (final method in bookCash.keys) {
    if (!cashMethodCodes.contains(method)) {
      return const CompensationRejected('invalid_input');
    }
  }
  final cashDeltas = <String, BigInt>{};
  var any = false;
  for (final method in cashMethodCodes) {
    final counted = countedCash[method]!;
    final book = bookCash[method] ?? BigInt.zero;
    if (counted.isNegative ||
        book.isNegative ||
        !PostgresInteger.fits(counted) ||
        !PostgresInteger.fits(book)) {
      return const CompensationRejected('invalid_input');
    }
    final delta = PostgresInteger.checkedAdd(counted, -book);
    if (delta == null) return const CompensationRejected('overflow');
    cashDeltas[method] = delta;
    if (delta != BigInt.zero) any = true;
  }
  final stock = _pairedDeltas(countedStock, bookStock, scrap: false);
  if (stock is CompensationRejected<List<MetalEffect>>) {
    return CompensationRejected(stock.code);
  }
  final scrap = _pairedDeltas(countedScrap, bookScrap, scrap: true);
  if (scrap is CompensationRejected<List<MetalEffect>>) {
    return CompensationRejected(scrap.code);
  }
  final stockDeltas = (stock as CompensationAccepted<List<MetalEffect>>).value;
  final scrapDeltas = (scrap as CompensationAccepted<List<MetalEffect>>).value;
  if (stockDeltas.any(
        (line) => line.milligrams != BigInt.zero || line.count != BigInt.zero,
      ) ||
      scrapDeltas.any((line) => line.milligrams != BigInt.zero)) {
    any = true;
  }
  if (!any) return const CompensationRejected('invalid_input');
  return CompensationAccepted(
    CorrectionReview(
      reason: trimmed,
      cashDeltas: cashDeltas,
      stockDeltas: stockDeltas,
      scrapDeltas: scrapDeltas,
    ),
  );
}

CompensationResult<PartialReturnReview> reviewPartialReturn({
  required String kind,
  required BigInt consideration,
  required BigInt remainderConsideration,
  required BigInt payableRemaining,
  required bool quantityRemains,
  required List<ReturnLineInput> lines,
  required Map<String, BigInt> tenders,
  required Map<String, BigInt> refundableByMethod,
  Map<String, BigInt>? shopBalances,
  required bool pricingRequired,
  PriceComponents? pricing,
}) {
  if (kind != 'sale_return' && kind != 'purchase_return') {
    return const CompensationRejected('invalid_input');
  }
  if (consideration < BigInt.zero || consideration > remainderConsideration) {
    return CompensationRejected(
      consideration < BigInt.zero ? 'invalid_input' : 'return_exceeds_original',
    );
  }
  if (lines.isEmpty && (quantityRemains || consideration == BigInt.zero)) {
    return const CompensationRejected('invalid_input');
  }
  if (lines.length > 50) return const CompensationRejected('invalid_input');
  final seen = <int>{};
  for (final line in lines) {
    if (!seen.add(line.itemIndex)) {
      return const CompensationRejected('invalid_input');
    }
    if (line.milligrams <= BigInt.zero ||
        line.milligrams > line.remainderMilligrams ||
        line.count.isNegative ||
        line.count > line.remainderCount) {
      return const CompensationRejected('return_exceeds_original');
    }
    if (!line.scrap &&
        ((line.remainderMilligrams - line.milligrams == BigInt.zero) !=
            (line.remainderCount - line.count == BigInt.zero))) {
      return const CompensationRejected('stock_pair_mismatch');
    }
    if (line.scrap) {
      if (line.count != BigInt.zero) {
        return const CompensationRejected('invalid_input');
      }
    } else if (line.count <= BigInt.zero ||
        (line.milligrams == BigInt.zero) != (line.count == BigInt.zero)) {
      return const CompensationRejected('stock_pair_mismatch');
    }
  }
  if (pricingRequired) {
    if (pricing == null) return const CompensationRejected('invalid_input');
    final priced = _pricingSums(pricing, consideration);
    if (priced is CompensationRejected<PriceComponents>) {
      return CompensationRejected(priced.code);
    }
  } else if (pricing != null) {
    return const CompensationRejected('invalid_input');
  }
  final cancel = kind == 'purchase_return'
      ? (consideration < payableRemaining ? consideration : payableRemaining)
      : BigInt.zero;
  if (cancel.isNegative) return const CompensationRejected('invalid_input');
  final cash = consideration - cancel;
  final tenderSum = PostgresInteger.checkedSum(tenders.values);
  if (tenderSum == null || tenderSum != cash) {
    return const CompensationRejected('tender_mismatch');
  }
  var refundableTotal = BigInt.zero;
  for (final entry in tenders.entries) {
    if (!cashMethodCodes.contains(entry.key) || entry.value.isNegative) {
      return const CompensationRejected('invalid_input');
    }
    if (kind == 'sale_return' &&
        shopBalances != null &&
        entry.value > (shopBalances[entry.key] ?? BigInt.zero)) {
      return const CompensationRejected('negative_owned_balance');
    }
  }
  for (final method in cashMethodCodes) {
    final part = refundableByMethod[method] ?? BigInt.zero;
    final next = PostgresInteger.checkedAdd(refundableTotal, part);
    if (next == null) return const CompensationRejected('overflow');
    refundableTotal = next;
  }
  if (cash > refundableTotal) {
    return const CompensationRejected('return_exceeds_original');
  }
  return CompensationAccepted(
    PartialReturnReview(
      kind: kind,
      consideration: consideration,
      cancelledPayable: cancel,
      cashRefund: cash,
      lines: lines,
      tenders: tenders,
      pricing: pricing,
    ),
  );
}

CompensationResult<ExchangeReview> reviewExchange({
  required PartialReturnReview returnSide,
  required String replacementKind,
  required BigInt replacementTotal,
  required Map<String, BigInt> replacementTenders,
  required List<ReplacementLine> replacementLines,
}) {
  if (returnSide.kind == 'sale_return' && replacementKind != 'sale') {
    return const CompensationRejected('invalid_input');
  }
  if (returnSide.kind == 'purchase_return' && replacementKind != 'purchase') {
    return const CompensationRejected('invalid_input');
  }
  if (replacementKind != 'sale' && replacementKind != 'purchase') {
    return const CompensationRejected('invalid_input');
  }
  if (replacementTotal <= BigInt.zero || replacementLines.isEmpty) {
    return const CompensationRejected('invalid_input');
  }
  final tenderSum = PostgresInteger.checkedSum(replacementTenders.values);
  if (tenderSum == null ||
      tenderSum.isNegative ||
      tenderSum > replacementTotal ||
      (replacementKind == 'sale' && tenderSum != replacementTotal)) {
    return const CompensationRejected('tender_mismatch');
  }
  final replacementEffects = <MetalEffect>[];
  final sign = replacementKind == 'sale' ? -BigInt.one : BigInt.one;
  for (final line in replacementLines) {
    final category = StockCategory.byCode(line.category);
    if (line.category == 'scrap'
        ? replacementKind != 'purchase' ||
              !ScrapKarats.allowed.contains(line.karat)
        : category == null || !category.allowsKarat(line.karat)) {
      return const CompensationRejected('invalid_input');
    }
    if (line.itemName.trim().isEmpty) {
      return const CompensationRejected('invalid_input');
    }
    if (line.milligrams <= BigInt.zero ||
        (line.category != 'scrap' && line.count <= BigInt.zero) ||
        (line.category == 'scrap' && line.count != BigInt.zero)) {
      return const CompensationRejected('stock_pair_mismatch');
    }
    final milligrams = PostgresInteger.checkedMultiply(line.milligrams, sign);
    final count = PostgresInteger.checkedMultiply(line.count, sign);
    if (milligrams == null || count == null) {
      return const CompensationRejected('overflow');
    }
    replacementEffects.add(
      MetalEffect(
        category: line.category,
        karat: line.karat,
        milligrams: milligrams,
        count: line.category == 'scrap' ? null : count,
      ),
    );
  }
  final replacementCash = replacementKind == 'sale' ? tenderSum : -tenderSum;
  final netCash = PostgresInteger.checkedAdd(
    returnSide.signedCash,
    replacementCash,
  );
  if (netCash == null) return const CompensationRejected('overflow');
  final nets = <String, MetalEffect>{};
  void add(MetalEffect effect) {
    final key = '${effect.category}:${effect.karat}';
    final current = nets[key];
    if (current == null) {
      nets[key] = effect;
      return;
    }
    final milligrams = PostgresInteger.checkedAdd(
      current.milligrams,
      effect.milligrams,
    );
    final count = PostgresInteger.checkedAdd(
      current.count ?? BigInt.zero,
      effect.count ?? BigInt.zero,
    );
    if (milligrams == null || count == null) {
      throw const _Overflow();
    }
    nets[key] = MetalEffect(
      category: effect.category,
      karat: effect.karat,
      milligrams: milligrams,
      count: effect.count == null && current.count == null ? null : count,
    );
  }

  try {
    for (final line in returnSide.lines) {
      final metalSign = returnSide.kind == 'sale_return'
          ? BigInt.one
          : -BigInt.one;
      final milligrams = PostgresInteger.checkedMultiply(
        line.milligrams,
        metalSign,
      );
      final count = line.scrap
          ? null
          : PostgresInteger.checkedMultiply(line.count, metalSign);
      if (milligrams == null || (!line.scrap && count == null)) {
        return const CompensationRejected('overflow');
      }
      add(
        MetalEffect(
          category: line.category,
          karat: line.karat,
          milligrams: milligrams,
          count: count,
        ),
      );
    }
    for (final effect in replacementEffects) {
      add(effect);
    }
  } on _Overflow {
    return const CompensationRejected('overflow');
  }
  return CompensationAccepted(
    ExchangeReview(
      returnSide: returnSide,
      replacementKind: replacementKind,
      replacementCash: replacementCash,
      replacementLines: replacementEffects,
      netCash: netCash,
      netLines: nets.values.toList(),
    ),
  );
}

CompensationResult<ReturnRemainder> parseReturnRemainder(
  Map<String, Object?> json,
) {
  final operationId = json['operation_id'];
  final kind = json['kind'];
  if (operationId is! String ||
      kind is! String ||
      (kind != 'sale' && kind != 'purchase')) {
    return const CompensationRejected('invalid_input');
  }
  final itemsRaw = json['items'];
  if (itemsRaw is! List) return const CompensationRejected('invalid_input');
  final items = <ReturnRemainderItem>[];
  for (final raw in itemsRaw) {
    if (raw is! Map) return const CompensationRejected('invalid_input');
    final item = Map<String, Object?>.from(raw);
    final index = _canonical(item['item_index']);
    final milligrams = _canonical(item['remainder_milligrams']);
    final original = _canonical(item['original_milligrams']);
    final returned = _canonical(item['returned_milligrams']);
    final karat = item['karat'];
    final category = item['category'];
    if (index is! BigInt ||
        milligrams is! BigInt ||
        original is! BigInt ||
        returned is! BigInt ||
        karat is! int ||
        category is! String) {
      return const CompensationRejected('invalid_input');
    }
    final scrap = category == 'scrap' || item['remainder_count'] == null;
    BigInt? remainderCount;
    BigInt? originalCount;
    BigInt? returnedCount;
    if (!scrap) {
      final parsedCount = _canonical(item['remainder_count']);
      final parsedOriginal = _canonical(item['original_count']);
      final parsedReturned = _canonical(item['returned_count']);
      if (parsedCount is! BigInt ||
          parsedOriginal is! BigInt ||
          parsedReturned is! BigInt) {
        return const CompensationRejected('invalid_input');
      }
      remainderCount = parsedCount;
      originalCount = parsedOriginal;
      returnedCount = parsedReturned;
    }
    items.add(
      ReturnRemainderItem(
        itemIndex: index.toInt(),
        category: category,
        karat: karat,
        itemName: item['item_name'] is String
            ? item['item_name'] as String
            : '',
        scrap: scrap,
        originalMilligrams: original,
        returnedMilligrams: returned,
        remainderMilligrams: milligrams,
        originalCount: originalCount,
        returnedCount: returnedCount,
        remainderCount: remainderCount,
      ),
    );
  }
  final originalTotal = _canonical(json['original_total_piastres']);
  final returnedConsideration = _canonical(
    json['returned_consideration_piastres'],
  );
  final remainderConsideration = _canonical(
    json['remainder_consideration_piastres'],
  );
  final payable = _canonical(json['payable_remaining_piastres']);
  final refundableRaw = json['refundable_by_method'];
  if (originalTotal is! BigInt ||
      returnedConsideration is! BigInt ||
      remainderConsideration is! BigInt ||
      payable is! BigInt ||
      refundableRaw is! Map) {
    return const CompensationRejected('invalid_input');
  }
  final refundable = <String, BigInt>{};
  for (final method in cashMethodCodes) {
    final amount = _canonical(refundableRaw[method]);
    if (amount is! BigInt) return const CompensationRejected('invalid_input');
    refundable[method] = amount;
  }
  Map<String, BigInt>? pricingRemainder;
  var label = '';
  final hasPricing = json['has_pricing'] == true;
  if (hasPricing) {
    final pricing = json['pricing'];
    if (pricing is! Map) return const CompensationRejected('invalid_input');
    pricingRemainder = {};
    for (final component in const [
      'base_piastres',
      'workmanship_piastres',
      'other_charges_piastres',
      'discount_piastres',
    ]) {
      final row = pricing[component];
      if (row is! Map) return const CompensationRejected('invalid_input');
      final remainder = _canonical(row['remainder']);
      if (remainder is! BigInt) {
        return const CompensationRejected('invalid_input');
      }
      pricingRemainder[component] = remainder;
    }
    label = pricing['other_charges_label'] is String
        ? pricing['other_charges_label'] as String
        : '';
  }
  return CompensationAccepted(
    ReturnRemainder(
      operationId: operationId,
      kind: kind,
      fullyReturned: json['fully_returned'] == true,
      originalImmutable: json['original_immutable'] == true,
      items: items,
      originalTotal: originalTotal,
      returnedConsideration: returnedConsideration,
      remainderConsideration: remainderConsideration,
      payableRemaining: payable,
      refundableByMethod: refundable,
      hasPricing: hasPricing,
      pricingRemainder: pricingRemainder,
      otherChargesLabel: label,
    ),
  );
}

String signedPoundsText(BigInt piastres) {
  final negative = piastres.isNegative;
  final whole = piastres.abs() ~/ BigInt.from(100);
  final fraction = (piastres.abs() % BigInt.from(100)).toInt();
  final text = '$whole.${fraction.toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

String signedGramsText(BigInt milligrams) {
  final negative = milligrams.isNegative;
  final whole = milligrams.abs() ~/ BigInt.from(1000);
  final fraction = (milligrams.abs() % BigInt.from(1000)).toInt();
  final text = '$whole.${fraction.toString().padLeft(3, '0')}';
  return negative ? '-$text' : text;
}

CompensationResult<List<MetalEffect>> _pairedDeltas(
  List<MetalEffect> counted,
  List<MetalEffect> book, {
  required bool scrap,
}) {
  String key(MetalEffect line) => '${line.category}:${line.karat}';
  if (counted.map(key).toSet().length != counted.length ||
      book.map(key).toSet().length != book.length) {
    return const CompensationRejected('invalid_input');
  }
  final bookByKey = {for (final line in book) key(line): line};
  if (bookByKey.length != counted.length ||
      counted.any((line) => !bookByKey.containsKey(key(line)))) {
    return const CompensationRejected('invalid_input');
  }
  final deltas = <MetalEffect>[];
  for (final line in counted) {
    final current = bookByKey[key(line)]!;
    if (line.milligrams.isNegative ||
        current.milligrams.isNegative ||
        !PostgresInteger.fits(line.milligrams) ||
        !PostgresInteger.fits(current.milligrams)) {
      return const CompensationRejected('invalid_input');
    }
    final milligrams = PostgresInteger.checkedAdd(
      line.milligrams,
      -current.milligrams,
    );
    if (milligrams == null) return const CompensationRejected('overflow');
    BigInt? count;
    if (!scrap) {
      final countedCount = line.count;
      final bookCount = current.count;
      if (countedCount == null ||
          bookCount == null ||
          countedCount.isNegative ||
          bookCount.isNegative ||
          !PostgresInteger.fits(countedCount) ||
          !PostgresInteger.fits(bookCount)) {
        return const CompensationRejected('invalid_input');
      }
      if ((countedCount == BigInt.zero) != (line.milligrams == BigInt.zero)) {
        return const CompensationRejected('stock_pair_mismatch');
      }
      count = PostgresInteger.checkedAdd(countedCount, -bookCount);
      if (count == null) return const CompensationRejected('overflow');
    }
    deltas.add(
      MetalEffect(
        category: line.category,
        karat: line.karat,
        milligrams: milligrams,
        count: count,
      ),
    );
  }
  return CompensationAccepted(deltas);
}

CompensationResult<PriceComponents> _pricingSums(
  PriceComponents pricing,
  BigInt consideration,
) {
  final parts = <(BigInt, BigInt)>[
    (pricing.base, pricing.remainderBase),
    (pricing.workmanship, pricing.remainderWorkmanship),
    (pricing.otherCharges, pricing.remainderOtherCharges),
    (pricing.discount, pricing.remainderDiscount),
  ];
  for (final (amount, remainder) in parts) {
    if (amount.isNegative || amount > remainder) {
      return const CompensationRejected('return_exceeds_original');
    }
  }
  if (pricing.otherCharges > BigInt.zero &&
      pricing.otherChargesLabel.trim().isEmpty) {
    return const CompensationRejected('invalid_input');
  }
  final added = PostgresInteger.checkedSum([
    pricing.base,
    pricing.workmanship,
    pricing.otherCharges,
    -pricing.discount,
  ]);
  if (added == null) return const CompensationRejected('overflow');
  if (added != consideration) {
    return const CompensationRejected('pricing_mismatch');
  }
  return CompensationAccepted(pricing);
}

Object? _canonical(Object? value) {
  if (value is int) return BigInt.from(value);
  if (value is! String) return null;
  if (!RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) return null;
  final parsed = BigInt.parse(value);
  if (!PostgresInteger.fits(parsed)) return null;
  return parsed;
}

final class _Overflow implements Exception {
  const _Overflow();
}

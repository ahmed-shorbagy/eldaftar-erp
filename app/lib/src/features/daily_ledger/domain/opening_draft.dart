import 'opening_catalog.dart';
import 'opening_issue.dart';
import 'postgres_integer.dart';
import 'quantities.dart';

/// One piece-tracked opening bucket. Milligrams and count are both positive.
final class OpeningStockBucket {
  const OpeningStockBucket._({
    required this.category,
    required this.purity,
    required this.milligrams,
    required this.count,
  });

  final StockCategory category;
  final Karat purity;
  int get karat => purity.value;
  final Milligrams milligrams;
  final PieceCount count;

  static DomainResult<OpeningStockBucket> tryCreate({
    required StockCategory category,
    required int karat,
    required Milligrams milligrams,
    required PieceCount count,
  }) {
    if (!category.allowsKarat(karat)) {
      return const Rejected(OpeningIssueCode.unsupportedCategoryKarat);
    }
    if (milligrams.value == BigInt.zero || count.value == BigInt.zero) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    return Accepted(
      OpeningStockBucket._(
        category: category,
        purity: (Karat.tryCreate(karat) as Accepted<Karat>).value,
        milligrams: milligrams,
        count: count,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'category': category.code,
    'karat': karat,
    'milligrams': milligrams.wire,
    'count': count.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is OpeningStockBucket &&
      other.category == category &&
      other.karat == karat &&
      other.milligrams == milligrams &&
      other.count == count;

  @override
  int get hashCode => Object.hash(category, karat, milligrams, count);
}

/// One scrap bucket. Weight only; a count is not representable here.
final class OpeningScrapBucket {
  const OpeningScrapBucket._({required this.purity, required this.milligrams});

  final Karat purity;
  int get karat => purity.value;
  final Milligrams milligrams;

  static DomainResult<OpeningScrapBucket> tryCreate({
    required int karat,
    required Milligrams milligrams,
  }) {
    if (!ScrapKarats.allowed.contains(karat)) {
      return const Rejected(OpeningIssueCode.unsupportedCategoryKarat);
    }
    if (milligrams.value == BigInt.zero) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    return Accepted(
      OpeningScrapBucket._(
        purity: (Karat.tryCreate(karat) as Accepted<Karat>).value,
        milligrams: milligrams,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'karat': karat,
    'milligrams': milligrams.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is OpeningScrapBucket &&
      other.karat == karat &&
      other.milligrams == milligrams;

  @override
  int get hashCode => Object.hash(karat, milligrams);
}

final class OpeningCash {
  const OpeningCash._(this._amounts);

  final Map<CashMethod, Piastres> _amounts;

  Piastres operator [](CashMethod method) => _amounts[method]!;

  Map<String, Object?> toJson() => {
    for (final method in CashMethod.canonicalOrder)
      method.code: this[method].wire,
  };
}

/// Canonical opening payload version 1. Immutable after validation.
final class OpeningDraft {
  const OpeningDraft._({
    required this.cash,
    required this.stock,
    required this.scrap,
  });

  final OpeningCash cash;
  final List<OpeningStockBucket> stock;
  final List<OpeningScrapBucket> scrap;

  int get version => OpeningPayload.version;

  /// Builds the reviewed canonical object. Quantities stay decimal strings.
  Map<String, Object?> toCanonicalJson() => {
    'version': version,
    'cash': cash.toJson(),
    'stock': [for (final row in stock) row.toJson()],
    'scrap': [for (final row in scrap) row.toJson()],
  };

  /// Fills omitted cash methods with zero and sorts buckets.
  static DomainResult<OpeningDraft> compose({
    Map<CashMethod, Piastres> cash = const {},
    List<OpeningStockBucket> stock = const [],
    List<OpeningScrapBucket> scrap = const [],
  }) {
    final amounts = <CashMethod, Piastres>{
      for (final method in CashMethod.canonicalOrder)
        method: cash[method] ?? Piastres.zero,
    };
    final sortedStock = [...stock]
      ..sort((a, b) {
        final byCategory = a.category.code.compareTo(b.category.code);
        if (byCategory != 0) return byCategory;
        return a.karat.compareTo(b.karat);
      });
    final sortedScrap = [...scrap]..sort((a, b) => a.karat.compareTo(b.karat));
    final summed = _checkedTotals(
      cash: amounts.values.map((amount) => amount.value),
      stock: sortedStock,
      scrap: sortedScrap,
    );
    if (summed != null) return Rejected(summed);
    return Accepted(
      OpeningDraft._(
        cash: OpeningCash._(Map.unmodifiable(amounts)),
        stock: List.unmodifiable(sortedStock),
        scrap: List.unmodifiable(sortedScrap),
      ),
    );
  }

  /// Parses a JSON object. Unknown fields, JSON numbers for quantities, and
  /// non-canonical amount strings are rejected. Omitted cash keys become `0`.
  static DomainResult<OpeningDraft> parseJson(Map<String, Object?> json) {
    const topLevel = {'version', 'cash', 'stock', 'scrap'};
    if (json.keys.any((key) => !topLevel.contains(key))) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    if (json['version'] is! int || json['version'] != OpeningPayload.version) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    final cashValue = json['cash'];
    final stockValue = json['stock'];
    final scrapValue = json['scrap'];
    if (cashValue is! Map || stockValue is! List || scrapValue is! List) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }

    final cash = <CashMethod, Piastres>{};
    for (final entry in cashValue.entries) {
      final key = entry.key;
      if (key is! String) return const Rejected(OpeningIssueCode.invalidInput);
      final method = CashMethod.byCode(key);
      if (method == null || cash.containsKey(method)) {
        return const Rejected(OpeningIssueCode.invalidInput);
      }
      if (entry.value is! String) {
        return const Rejected(OpeningIssueCode.invalidInput);
      }
      final parsed = Piastres.parseWire(entry.value as String);
      if (parsed is Rejected<Piastres>) return Rejected(parsed.code);
      cash[method] = (parsed as Accepted<Piastres>).value;
    }

    final stock = <OpeningStockBucket>[];
    for (final row in stockValue) {
      final parsed = _parseStockRow(row);
      if (parsed is Rejected<OpeningStockBucket>) return Rejected(parsed.code);
      stock.add((parsed as Accepted<OpeningStockBucket>).value);
    }

    final scrap = <OpeningScrapBucket>[];
    for (final row in scrapValue) {
      final parsed = _parseScrapRow(row);
      if (parsed is Rejected<OpeningScrapBucket>) return Rejected(parsed.code);
      scrap.add((parsed as Accepted<OpeningScrapBucket>).value);
    }

    return compose(cash: cash, stock: stock, scrap: scrap);
  }

  @override
  bool operator ==(Object other) =>
      other is OpeningDraft &&
      _cashEquals(other.cash) &&
      _listEquals(stock, other.stock) &&
      _listEquals(scrap, other.scrap);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(CashMethod.canonicalOrder.map((method) => cash[method])),
    Object.hashAll(stock),
    Object.hashAll(scrap),
  );

  bool _cashEquals(OpeningCash other) {
    for (final method in CashMethod.canonicalOrder) {
      if (cash[method] != other[method]) return false;
    }
    return true;
  }
}

DomainResult<OpeningStockBucket> _parseStockRow(Object? row) {
  if (row is! Map) return const Rejected(OpeningIssueCode.invalidInput);
  const fields = {'category', 'karat', 'milligrams', 'count'};
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final categoryCode = row['category'];
  final karat = row['karat'];
  final milligramsText = row['milligrams'];
  final countText = row['count'];
  if (categoryCode is! String ||
      karat is! int ||
      milligramsText is! String ||
      countText is! String) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final category = StockCategory.byCode(categoryCode);
  if (category == null) {
    return const Rejected(OpeningIssueCode.unsupportedCategoryKarat);
  }
  final milligrams = Milligrams.parseWire(milligramsText);
  if (milligrams is Rejected<Milligrams>) return Rejected(milligrams.code);
  final count = PieceCount.parseWire(countText);
  if (count is Rejected<PieceCount>) return Rejected(count.code);
  return OpeningStockBucket.tryCreate(
    category: category,
    karat: karat,
    milligrams: (milligrams as Accepted<Milligrams>).value,
    count: (count as Accepted<PieceCount>).value,
  );
}

DomainResult<OpeningScrapBucket> _parseScrapRow(Object? row) {
  if (row is! Map) return const Rejected(OpeningIssueCode.invalidInput);
  if (row.containsKey('count')) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  const fields = {'karat', 'milligrams'};
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final karat = row['karat'];
  final milligramsText = row['milligrams'];
  if (karat is! int || milligramsText is! String) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final milligrams = Milligrams.parseWire(milligramsText);
  if (milligrams is Rejected<Milligrams>) return Rejected(milligrams.code);
  return OpeningScrapBucket.tryCreate(
    karat: karat,
    milligrams: (milligrams as Accepted<Milligrams>).value,
  );
}

OpeningIssueCode? _checkedTotals({
  required Iterable<BigInt> cash,
  required List<OpeningStockBucket> stock,
  required List<OpeningScrapBucket> scrap,
}) {
  if (PostgresInteger.checkedSum(cash) == null) {
    return OpeningIssueCode.overflow;
  }
  if (_duplicateStock(stock) || _duplicateScrap(scrap)) {
    return OpeningIssueCode.duplicateBucket;
  }
  final byKarat = <int, List<BigInt>>{};
  for (final row in stock) {
    byKarat.putIfAbsent(row.karat, () => []).add(row.milligrams.value);
  }
  for (final row in scrap) {
    byKarat.putIfAbsent(row.karat, () => []).add(row.milligrams.value);
  }
  for (final weights in byKarat.values) {
    if (PostgresInteger.checkedSum(weights) == null) {
      return OpeningIssueCode.overflow;
    }
  }
  if (PostgresInteger.checkedSum(stock.map((row) => row.count.value)) == null) {
    return OpeningIssueCode.overflow;
  }
  return null;
}

bool _duplicateStock(List<OpeningStockBucket> stock) {
  final seen = <String>{};
  for (final row in stock) {
    final key = '${row.category.code}:${row.karat}';
    if (!seen.add(key)) return true;
  }
  return false;
}

bool _duplicateScrap(List<OpeningScrapBucket> scrap) {
  final seen = <int>{};
  for (final row in scrap) {
    if (!seen.add(row.karat)) return true;
  }
  return false;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

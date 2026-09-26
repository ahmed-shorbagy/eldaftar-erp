import 'opening_issue.dart';

/// Validated gold purity; category restrictions are applied by opening buckets.
final class Karat {
  const Karat._(this.value);

  final int value;

  static DomainResult<Karat> tryCreate(int value) =>
      ScrapKarats.allowed.contains(value)
      ? Accepted(Karat._(value))
      : const Rejected(OpeningIssueCode.unsupportedCategoryKarat);

  @override
  bool operator ==(Object other) => other is Karat && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Opening-only catalog. Recommended working default, not a shop-domain signature.
enum CashMethod {
  cash('cash'),
  instantTransfer('instant_transfer'),
  wallet('wallet'),
  card('card');

  const CashMethod(this.code);

  final String code;

  static const canonicalOrder = <CashMethod>[
    cash,
    instantTransfer,
    wallet,
    card,
  ];

  static CashMethod? byCode(String code) {
    for (final method in canonicalOrder) {
      if (method.code == code) return method;
    }
    return null;
  }
}

enum StockCategory {
  bullion('bullion', <int>{24}),
  coin('coin', <int>{21}),
  workedJewelry('worked_jewelry', <int>{14, 18, 21, 22});

  const StockCategory(this.code, this.karats);

  final String code;
  final Set<int> karats;

  static const canonicalOrder = <StockCategory>[bullion, coin, workedJewelry];

  bool allowsKarat(int karat) => karats.contains(karat);

  static StockCategory? byCode(String code) {
    for (final category in canonicalOrder) {
      if (category.code == code) return category;
    }
    return null;
  }
}

abstract final class ScrapKarats {
  static const allowed = <int>{14, 18, 21, 22, 24};
}

abstract final class OpeningPayload {
  static const version = 1;
}

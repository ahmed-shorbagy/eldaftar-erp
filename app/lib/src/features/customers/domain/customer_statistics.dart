const customerKarats = [14, 18, 21, 22, 24];

/// Exact server-derived customer quantities. No client financial aggregation.
class CustomerKaratWeight {
  const CustomerKaratWeight(
    this.karat,
    this.boughtMilligrams,
    this.soldMilligrams,
  );
  final int karat;
  final BigInt boughtMilligrams, soldMilligrams;
}

class CustomerLastOperation {
  const CustomerLastOperation({
    required this.id,
    required this.kind,
    required this.sequence,
    required this.createdAt,
    required this.createdAtShop,
  });
  final String id, kind, createdAt, createdAtShop;
  final BigInt sequence;
}

class CustomerStatistics {
  const CustomerStatistics({
    required this.weights,
    required this.boughtCount,
    required this.soldCount,
    required this.lastOperation,
  });
  final List<CustomerKaratWeight> weights;
  final BigInt boughtCount, soldCount;
  final CustomerLastOperation? lastOperation;
  bool get hasActivity => boughtCount + soldCount > BigInt.zero;
  CustomerKaratWeight at(int karat) =>
      weights.singleWhere((w) => w.karat == karat);
}

String customerGrams(BigInt milligrams) {
  if (milligrams < BigInt.zero) throw ArgumentError.value(milligrams);
  final whole = (milligrams ~/ BigInt.from(1000)).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$whole.${(milligrams % BigInt.from(1000)).toString().padLeft(3, '0')}';
}

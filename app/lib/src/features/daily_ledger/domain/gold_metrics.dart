/// Rational gold equivalence; round once, at the displayed centigram boundary.
const normalizationKarats = <int>[14, 18, 21, 22, 24];

BigInt normalizedGoldCentigrams(
  Iterable<({int karat, BigInt milligrams})> weights,
  int targetKarat,
) {
  if (!normalizationKarats.contains(targetKarat)) {
    throw ArgumentError.value(targetKarat, 'targetKarat');
  }
  var weighted = BigInt.zero;
  for (final weight in weights) {
    if (!normalizationKarats.contains(weight.karat) ||
        weight.milligrams.isNegative) {
      throw ArgumentError('Invalid gold weight');
    }
    weighted += weight.milligrams * BigInt.from(weight.karat);
  }
  final divisor = BigInt.from(targetKarat * 10);
  final whole = weighted ~/ divisor;
  return whole +
      ((weighted % divisor) * BigInt.two >= divisor ? BigInt.one : BigInt.zero);
}

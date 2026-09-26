/// Signed PostgreSQL `bigint` bounds. Opening arithmetic uses these limits
/// before a value is treated as safe to send or to add.
abstract final class PostgresInteger {
  static final BigInt min = BigInt.parse('-9223372036854775808');
  static final BigInt max = BigInt.parse('9223372036854775807');

  static bool fits(BigInt value) => value >= min && value <= max;

  /// Adds [left] and [right] only when both already fit and the sum fits.
  static BigInt? checkedAdd(BigInt left, BigInt right) {
    if (!fits(left) || !fits(right)) return null;
    final sum = left + right;
    if (!fits(sum)) return null;
    return sum;
  }

  /// Multiplies [left] and [right] only when both already fit and the product fits.
  static BigInt? checkedMultiply(BigInt left, BigInt right) {
    if (!fits(left) || !fits(right)) return null;
    final product = left * right;
    if (!fits(product)) return null;
    return product;
  }

  static BigInt? checkedSum(Iterable<BigInt> values) {
    var total = BigInt.zero;
    for (final value in values) {
      final next = checkedAdd(total, value);
      if (next == null) return null;
      total = next;
    }
    return total;
  }
}

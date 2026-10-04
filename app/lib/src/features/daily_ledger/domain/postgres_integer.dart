/// Signed PostgreSQL `bigint` bounds. Opening arithmetic uses these limits
/// before a value is treated as safe to send or to add.
abstract final class PostgresInteger {
  static final BigInt min = BigInt.parse('-9223372036854775808');
  static final BigInt max = BigInt.parse('9223372036854775807');

  static bool fits(BigInt value) => value >= min && value <= max;

  /// Canonical nonnegative wire value within PostgreSQL bigint bounds.
  static BigInt? parseCanonical(String value, {bool allowZero = false}) {
    final pattern = allowZero
        ? RegExp(r'^(0|[1-9][0-9]{0,18})$')
        : RegExp(r'^[1-9][0-9]{0,18}$');
    if (!pattern.hasMatch(value)) return null;
    final parsed = BigInt.parse(value);
    return fits(parsed) ? parsed : null;
  }

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

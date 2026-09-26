import 'opening_issue.dart';
import 'postgres_integer.dart';

final _wire = RegExp(r'^(0|[1-9][0-9]*)$');
final _pounds = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$');
final _grams = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,3})?$');

OpeningIssueCode? _signOrEmpty(String text) {
  if (text.isEmpty) return OpeningIssueCode.invalidInput;
  if (text.startsWith('-')) return OpeningIssueCode.negativeAmount;
  return null;
}

/// Non-negative EGP stored as integer piastres. 100 piastres = 1 pound.
final class Piastres {
  const Piastres._(this.value);

  static final zero = Piastres._(BigInt.zero);

  final BigInt value;

  String get wire => value.toString();

  /// Two decimal places, no thousands separator (`10000.00`).
  String get poundsText {
    final whole = value ~/ BigInt.from(100);
    final fraction = (value % BigInt.from(100)).toInt();
    return '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  static DomainResult<Piastres> parseWire(String input) {
    final parsed = _parseWire(input);
    if (parsed is Rejected<BigInt>) return Rejected(parsed.code);
    return Accepted(Piastres._((parsed as Accepted<BigInt>).value));
  }

  /// Pounds with at most two fractional digits. `1.25` is 125 piastres.
  static DomainResult<Piastres> parsePounds(String input) {
    final text = input.trim();
    final sign = _signOrEmpty(text);
    if (sign != null) return Rejected(sign);
    if (!_pounds.hasMatch(text)) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    final parts = text.split('.');
    final whole = BigInt.parse(parts[0]);
    final scaled = PostgresInteger.checkedMultiply(whole, BigInt.from(100));
    if (scaled == null) {
      return const Rejected(OpeningIssueCode.overflow);
    }
    final fraction = parts.length == 2
        ? BigInt.parse(parts[1].padRight(2, '0'))
        : BigInt.zero;
    final sum = PostgresInteger.checkedAdd(scaled, fraction);
    if (sum == null) return const Rejected(OpeningIssueCode.overflow);
    return Accepted(Piastres._(sum));
  }

  @override
  bool operator ==(Object other) => other is Piastres && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Piastres($wire)';
}

/// Non-negative gold weight stored as integer milligrams. 1000 mg = 1.000 g.
final class Milligrams {
  const Milligrams._(this.value);

  static final zero = Milligrams._(BigInt.zero);

  final BigInt value;

  String get wire => value.toString();

  /// Three decimal places (`1.830`).
  String get gramsText {
    final whole = value ~/ BigInt.from(1000);
    final fraction = (value % BigInt.from(1000)).toInt();
    return '$whole.${fraction.toString().padLeft(3, '0')}';
  }

  static DomainResult<Milligrams> parseWire(String input) {
    final parsed = _parseWire(input);
    if (parsed is Rejected<BigInt>) return Rejected(parsed.code);
    return Accepted(Milligrams._((parsed as Accepted<BigInt>).value));
  }

  /// Grams with at most three fractional digits. `1.830` is 1830 mg.
  static DomainResult<Milligrams> parseGrams(String input) {
    final text = input.trim();
    final sign = _signOrEmpty(text);
    if (sign != null) return Rejected(sign);
    if (!_grams.hasMatch(text)) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    final parts = text.split('.');
    final whole = BigInt.parse(parts[0]);
    final scaled = PostgresInteger.checkedMultiply(whole, BigInt.from(1000));
    if (scaled == null) {
      return const Rejected(OpeningIssueCode.overflow);
    }
    final fraction = parts.length == 2
        ? BigInt.parse(parts[1].padRight(3, '0'))
        : BigInt.zero;
    final sum = PostgresInteger.checkedAdd(scaled, fraction);
    if (sum == null) return const Rejected(OpeningIssueCode.overflow);
    return Accepted(Milligrams._(sum));
  }

  @override
  bool operator ==(Object other) => other is Milligrams && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Milligrams($wire)';
}

/// Non-negative integer piece count. Scrap buckets do not use this type.
final class PieceCount {
  const PieceCount._(this.value);

  static final zero = PieceCount._(BigInt.zero);

  final BigInt value;

  String get wire => value.toString();

  static DomainResult<PieceCount> parseWire(String input) {
    final parsed = _parseWire(input);
    if (parsed is Rejected<BigInt>) return Rejected(parsed.code);
    return Accepted(PieceCount._((parsed as Accepted<BigInt>).value));
  }

  @override
  bool operator ==(Object other) => other is PieceCount && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PieceCount($wire)';
}

DomainResult<BigInt> _parseWire(String input) {
  final sign = _signOrEmpty(input);
  if (sign != null) return Rejected(sign);
  if (!_wire.hasMatch(input)) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final value = BigInt.parse(input);
  if (!PostgresInteger.fits(value)) {
    return const Rejected(OpeningIssueCode.overflow);
  }
  return Accepted(value);
}

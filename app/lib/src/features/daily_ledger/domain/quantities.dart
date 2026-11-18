import 'opening_issue.dart';
import 'postgres_integer.dart';

final _wire = RegExp(r'^(0|[1-9][0-9]*)$');
final _pounds = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$');
// Two decimals. A written third digit must be zero (`1.830` is `1.83`).
final _entryGrams = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,2}0?)?$');
final _exactGrams = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,3})?$');

/// Grams with two decimals from integer milligrams: the one way a weight is
/// written for the owner. A stored third decimal rounds half away from zero.
/// Integer arithmetic only. ASCII minus. [grouped] adds thousands commas for
/// display; field text and wire text stay ungrouped.
String twoDecimalGrams(BigInt milligrams, {bool grouped = false}) {
  final magnitude = milligrams.abs();
  var centigrams = magnitude ~/ BigInt.from(10);
  if (magnitude % BigInt.from(10) >= BigInt.from(5)) centigrams += BigInt.one;
  var whole = (centigrams ~/ BigInt.from(100)).toString();
  if (grouped) {
    whole = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
  final fraction = (centigrams % BigInt.from(100)).toInt();
  final sign = milligrams.isNegative && centigrams != BigInt.zero ? '-' : '';
  return '$sign$whole.${fraction.toString().padLeft(2, '0')}';
}

/// An entered weight measured against a recorded one. The owner reads the
/// recorded weight with two decimals, so typing what he reads means that
/// weight itself. An older weight stored with a third decimal is then returned,
/// settled or kept in full, never left with a remainder he cannot see.
BigInt matchRecordedWeight(BigInt entered, BigInt recorded) =>
    twoDecimalGrams(entered) == twoDecimalGrams(recorded) ? recorded : entered;

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

/// Non-negative gold weight stored as integer milligrams. 1000 mg = 1 g.
/// Weights are entered and shown with two decimals; storage stays exact.
final class Milligrams {
  const Milligrams._(this.value);

  static final zero = Milligrams._(BigInt.zero);

  final BigInt value;

  String get wire => value.toString();

  /// Two decimal places (`1.83`), for display and for filling a weight field.
  String get gramsText => twoDecimalGrams(value);

  /// Every stored digit (`1.830`). Only for matching server text that carries
  /// three decimals; never shown.
  String get exactGramsText {
    final whole = value ~/ BigInt.from(1000);
    final fraction = (value % BigInt.from(1000)).toInt();
    return '$whole.${fraction.toString().padLeft(3, '0')}';
  }

  static DomainResult<Milligrams> parseWire(String input) {
    final parsed = _parseWire(input);
    if (parsed is Rejected<BigInt>) return Rejected(parsed.code);
    return Accepted(Milligrams._((parsed as Accepted<BigInt>).value));
  }

  /// An entered weight: grams with at most two fractional digits. `1.83` is
  /// 1830 mg. A third decimal is rejected.
  static DomainResult<Milligrams> parseGrams(String input) =>
      _parseGrams(input, _entryGrams);

  /// Catalog and server text, which may carry three decimals (`0.125`).
  /// Not for entry.
  static DomainResult<Milligrams> parseExactGrams(String input) =>
      _parseGrams(input, _exactGrams);

  static DomainResult<Milligrams> _parseGrams(String input, RegExp shape) {
    final text = input.trim();
    final sign = _signOrEmpty(text);
    if (sign != null) return Rejected(sign);
    if (!shape.hasMatch(text)) {
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

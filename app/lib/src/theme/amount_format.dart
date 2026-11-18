import '../features/daily_ledger/domain/quantities.dart' show twoDecimalGrams;

/// Display formatting only. Values remain exact decimal strings/integers.
///
/// Money is never abbreviated. Whole thousands are comma-grouped and a
/// non-zero cent fraction is kept. `70,000` and `1,200,000` stay complete.
String displayPounds(String exact) {
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(exact)) return exact;
  final negative = exact.startsWith('-');
  final parts = (negative ? exact.substring(1) : exact).split('.');
  final grouped = _groupThousands(parts[0]);
  final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  return '${negative ? '−' : ''}$grouped${fraction == '00' ? '' : '.$fraction'}';
}

/// The one display rule for gold weight: grams with two decimals, grouped.
///
/// A dotted value is grams (`1.25`). An integer is milligrams (`1250`).
/// Storage stays integer milligrams; a stored third decimal rounds half away
/// from zero through [twoDecimalGrams].
String displayGrams(String exact) {
  final negative = exact.startsWith('-');
  final body = negative ? exact.substring(1) : exact;
  final BigInt milligrams;
  if (RegExp(r'^[0-9]+$').hasMatch(body)) {
    milligrams = BigInt.parse(body);
  } else if (RegExp(r'^[0-9]+\.[0-9]{1,3}$').hasMatch(body)) {
    final parts = body.split('.');
    final fraction = parts[1].padRight(3, '0');
    milligrams =
        BigInt.parse(parts[0]) * BigInt.from(1000) + BigInt.parse(fraction);
  } else {
    return exact;
  }
  return displayMilligrams(negative ? -milligrams : milligrams);
}

/// [displayGrams] for a signed milligram amount. PDFs and messages pass an
/// ASCII [minus]; screens keep the typographic one.
String displayMilligrams(BigInt milligrams, {String minus = '−'}) {
  final text = twoDecimalGrams(milligrams, grouped: true);
  return text.startsWith('-') ? '$minus${text.substring(1)}' : text;
}

/// A weight with its unit, as shown on reviews and confirmations.
String displayGoldEffect(BigInt milligrams) =>
    '${displayMilligrams(milligrams)} جرام';

String _groupThousands(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Keeps phone-like runs («+201001234567») left to right inside Arabic text.
/// In an RTL line a leading «+» otherwise lands after the digits, for example
/// in the automatic customer name «عميل +201001234567».
String isolatePhoneRuns(String text) => text.replaceAllMapped(
  RegExp(
    '\\+?[0-9\u0660-\u0669][0-9\u0660-\u0669 \\-]*[0-9\u0660-\u0669]|\\+?[0-9\u0660-\u0669]',
  ),
  (match) => '\u2066${match[0]}\u2069',
);

/// Wraps a value of unknown direction (a person's name, a formatted date) so
/// it does not reorder its neighbours in a «·»-separated Arabic line. A Latin
/// actor name otherwise pulled the day of an Arabic date beside it.
String isolateText(String text) => '\u2068$text\u2069';

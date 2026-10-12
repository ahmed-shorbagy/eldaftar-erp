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

/// Two-decimal gold display. Stored and entered grams stay at three decimals.
///
/// A dotted value is grams (`1.255`). An integer is milligrams (`1255`).
/// The third decimal rounds half away from zero using integer division only.
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
  final rounded = _roundMilligramsToCentigrams(milligrams);
  final whole = rounded ~/ BigInt.from(100);
  final fraction = (rounded % BigInt.from(100)).toInt();
  return '${negative && rounded != BigInt.zero ? '−' : ''}${_groupThousands(whole.toString())}.${fraction.toString().padLeft(2, '0')}';
}

BigInt _roundMilligramsToCentigrams(BigInt milligrams) {
  final quotient = milligrams ~/ BigInt.from(10);
  final remainder = milligrams % BigInt.from(10);
  if (remainder >= BigInt.from(5)) return quotient + BigInt.one;
  return quotient;
}

/// Keeps two-decimal grams while revealing a rounding difference at confirmation.
String displayGoldEffect(BigInt milligrams) {
  final grams = '${displayGrams(milligrams.toString())} جرام';
  if (milligrams.abs() % BigInt.from(10) == BigInt.zero) return grams;
  return '$grams (${_groupThousands(milligrams.toString())} ملليجرام)';
}

String _groupThousands(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

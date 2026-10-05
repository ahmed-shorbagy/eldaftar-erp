/// Display formatting only. Values remain exact decimal strings/integers.
String displayPounds(String exact, {bool compact = false}) {
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]{1,2})?$').hasMatch(exact)) return exact;
  final negative = exact.startsWith('-');
  final parts = (negative ? exact.substring(1) : exact).split('.');
  final whole = BigInt.parse(parts[0]);
  if (compact && whole >= BigInt.from(1000000)) {
    final millions = whole ~/ BigInt.from(1000000);
    final tenth = (whole % BigInt.from(1000000)) ~/ BigInt.from(100000);
    return '${negative ? '−' : ''}$millions${tenth == BigInt.zero ? '' : '.$tenth'} مليون';
  }
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  return '${negative ? '−' : ''}$grouped${fraction == '00' ? '' : '.$fraction'}';
}

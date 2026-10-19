/// Only UI-owned isolates. The stored template and external body remain plain
/// validated text; input can never supply these control characters.
String messageDisplay(String text) => text.replaceAllMapped(
  RegExp(r'[0-9]+(?:[.,:/-][0-9]+)*'),
  (m) => '\u2066${m[0]}\u2069',
);

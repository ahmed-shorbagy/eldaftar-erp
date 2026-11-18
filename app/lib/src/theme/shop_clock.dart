/// The one clock format shown to shop users.
///
/// Owner rule (2026-11-17): the ordinary clock. «الساعة ٢ تبقى الساعة ٢»:
/// twelve hours with ص/م, no seconds, and never a time-zone name or «UTC».
/// Stored instants stay server-generated UTC; only the display changes.
library;

const _arabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

final _wallTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?)?',
);

/// «2:05 م» for 14:05. Digits stay left to right inside Arabic text.
///
/// Pass [isolate] false for PDFs and outgoing message text, where the
/// direction marks would print as boxes or travel into another app.
String shopClock(int hour24, int minute, {bool isolate = true}) {
  final period = hour24 < 12 ? 'ص' : 'م';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final clock = '$hour12:${minute.toString().padLeft(2, '0')}';
  return isolate ? '\u2066$clock\u2069 $period' : '$clock $period';
}

/// «17 نوفمبر 2026» for `2026-11-17`. Returns the input when it is not a date.
String shopDate(String isoDate) {
  final match = _wallTime.firstMatch(isoDate);
  if (match == null) return isoDate;
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return isoDate;
  return '${int.parse(match.group(3)!)} ${_arabicMonths[month - 1]} '
      '${match.group(1)}';
}

/// The clock part of a shop wall time (`YYYY-MM-DDTHH:MM:SS`, or with a
/// space). Null when the text carries no valid time.
String? shopClockOf(String wallTime, {bool isolate = true}) {
  final match = _wallTime.firstMatch(wallTime);
  final hourText = match?.group(4);
  if (match == null || hourText == null) return null;
  final hour = int.parse(hourText);
  final minute = int.parse(match.group(5)!);
  if (hour > 23 || minute > 59) return null;
  return shopClock(hour, minute, isolate: isolate);
}

/// «17 نوفمبر 2026، 5:49 م» for a shop wall time. The value is already in
/// the shop's zone; this function never shifts it. Text that is not a wall
/// time is returned as it came, with the `T` separator hidden.
String shopDateTime(String wallTime) {
  final clock = shopClockOf(wallTime);
  if (clock == null) {
    final match = _wallTime.firstMatch(wallTime);
    return match == null ? wallTime.replaceAll('T', ' ') : shopDate(wallTime);
  }
  return '${shopDate(wallTime)}، $clock';
}

/// Numeric date with the clock for PDF text drawn right to left, in reading
/// order: «2026/11/17 5:49 م». No direction marks.
String shopNumericDateTime(String wallTime) {
  final match = _wallTime.firstMatch(wallTime);
  if (match == null) return wallTime.replaceAll('T', ' ');
  final date = '${match.group(1)}/${match.group(2)}/${match.group(3)}';
  final clock = shopClockOf(wallTime, isolate: false);
  return clock == null ? date : '$date $clock';
}

/// The same value for a PDF cell that is forced left to right. Such a cell
/// draws characters in the order given, so the parts are written in the order
/// an Arabic reader sees them from the left: «م 5:49 2026/11/17». Read right
/// to left that is the date, the time, then ص/م, as on screen.
String shopNumericDateTimeLtr(String wallTime) {
  final match = _wallTime.firstMatch(wallTime);
  if (match == null) return wallTime.replaceAll('T', ' ');
  final date = '${match.group(1)}/${match.group(2)}/${match.group(3)}';
  final hourText = match.group(4);
  if (hourText == null) return date;
  final hour = int.parse(hourText);
  final minute = int.parse(match.group(5)!);
  if (hour > 23 || minute > 59) return date;
  final period = hour < 12 ? 'ص' : 'م';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $hour12:${minute.toString().padLeft(2, '0')} $date';
}

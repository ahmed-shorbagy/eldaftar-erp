/// Gregorian calendar value, independent of device time and time zones.
final class DebtCalendarDate implements Comparable<DebtCalendarDate> {
  const DebtCalendarDate._(this.wire);
  final String wire;
  static DebtCalendarDate? parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8));
    if (year < 1 || month < 1 || month > 12 || day < 1) return null;
    final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return day <= days[month - 1] ? DebtCalendarDate._(value) : null;
  }

  DateTime get calendar => DateTime.utc(
    int.parse(wire.substring(0, 4)),
    int.parse(wire.substring(5, 7)),
    int.parse(wire.substring(8)),
  );
  @override
  int compareTo(DebtCalendarDate other) => wire.compareTo(other.wire);
  @override
  String toString() => wire;
}

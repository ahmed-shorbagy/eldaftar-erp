// Owner rule of 2026-11-17: the ordinary clock everywhere. «الساعة ٢ تبقى
// الساعة ٢»: twelve hours with ص/م, no seconds, no time-zone name, no «UTC».
import 'package:eldafttar/src/theme/shop_clock.dart';
import 'package:eldafttar/src/theme/shop_instant.dart';
import 'package:flutter_test/flutter_test.dart';

String plain(String text) => text.replaceAll(RegExp('[\u2066\u2069]'), '');

void main() {
  test('afternoon hours are not shown on a 24-hour clock', () {
    expect(plain(shopClock(14, 5)), '2:05 م');
    expect(plain(shopClock(16, 0)), '4:00 م');
    expect(plain(shopClock(23, 59)), '11:59 م');
    expect(plain(shopClock(9, 30)), '9:30 ص');
  });

  test('midnight and noon read 12', () {
    expect(plain(shopClock(0, 0)), '12:00 ص');
    expect(plain(shopClock(0, 15)), '12:15 ص');
    expect(plain(shopClock(12, 0)), '12:00 م');
    expect(plain(shopClock(12, 45)), '12:45 م');
  });

  test('a wall time keeps its day and drops the seconds', () {
    expect(
      plain(shopDateTime('2026-11-17T17:49:58')),
      '17 نوفمبر 2026، 5:49 م',
    );
    expect(
      plain(shopDateTime('2026-11-17 00:05:00')),
      '17 نوفمبر 2026، 12:05 ص',
    );
    expect(shopDateTime('2026-11-17'), '17 نوفمبر 2026');
    expect(shopDateTime('—'), '—');
    expect(shopNumericDateTime('2026-11-17T17:49:58'), '2026/11/17 5:49 م');
    expect(shopClockOf('2026-11-17T25:00:00'), isNull);
  });

  test('PDF and message text carry no direction marks', () {
    expect(shopClock(14, 5, isolate: false), '2:05 م');
    expect(
      shopNumericDateTime('2026-11-17T14:05:00'),
      isNot(contains('\u2066')),
    );
    expect(shopClock(14, 5), contains('\u2066'));
  });

  test('an instant is shown in the shop zone and never names the zone', () {
    final instant = DateTime.utc(2026, 11, 17, 15, 49, 58);
    final cairo = plain(shopInstantText(instant, 'Africa/Cairo'));
    expect(cairo, '17 نوفمبر 2026، 5:49 م');
    // The shop's day, not the UTC day.
    final late = plain(
      shopInstantText(DateTime.utc(2026, 11, 17, 22, 30), 'Africa/Cairo'),
    );
    expect(late, '18 نوفمبر 2026، 12:30 ص');
    for (final text in [
      cairo,
      late,
      plain(shopInstantText(instant, 'Not/AZone')),
      plain(shopInstantText(instant)),
    ]) {
      expect(text, isNot(contains('UTC')));
      expect(text, isNot(contains('توقيت')));
      expect(text, isNot(contains('Cairo')));
      expect(text, matches(RegExp(r'\d{1,2}:\d{2} [صم]$')));
    }
  });
}

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'shop_clock.dart';

bool _zonesReady = false;

/// A server instant as the shop reads it: «17 نوفمبر 2026، 5:49 م».
///
/// Converted to [timeZone] (the shop's zone from the server). When the zone
/// is missing or unknown the device's own zone is used. The text never names
/// a zone and never says «UTC» (owner rule, 2026-11-17).
String shopInstantText(DateTime instant, [String? timeZone]) {
  var local = instant.toLocal();
  if (timeZone != null && timeZone.isNotEmpty) {
    try {
      if (!_zonesReady) {
        tzdata.initializeTimeZones();
        _zonesReady = true;
      }
      local = tz.TZDateTime.from(instant.toUtc(), tz.getLocation(timeZone));
    } catch (_) {
      local = instant.toLocal();
    }
  }
  final date =
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  return '${shopDate(date)}، ${shopClock(local.hour, local.minute)}';
}

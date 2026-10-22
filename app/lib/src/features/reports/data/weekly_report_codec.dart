import '../domain/financial_day_report.dart';
import '../domain/financial_week_report.dart';
import 'report_codec.dart';

FinancialWeekReport parseFinancialWeekReport(Object? raw) {
  final m = Map<String, dynamic>.from(raw as Map);
  String string(Object? v) => v as String;
  Map<String, dynamic> map(Object? v) => Map<String, dynamic>.from(v as Map);
  BigInt integer(Object? value) {
    if (value is! String || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const FormatException('weekly_integer');
    }
    return BigInt.parse(value);
  }

  DateTime date(Object? value) {
    final s = string(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      throw const FormatException('weekly_date');
    }
    final parsed = DateTime.parse('${s}T00:00:00Z');
    if (parsed.toIso8601String().substring(0, 10) != s) {
      throw const FormatException('weekly_date');
    }
    return parsed;
  }

  final start = date(m['start_date']),
      end = date(m['end_date']),
      server = date(m['server_date']),
      lastSelectable = date(m['last_selectable_date']);
  if (m['version'] != 1 ||
      end.difference(start).inDays != 6 ||
      lastSelectable.isBefore(server) ||
      end.isAfter(lastSelectable) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(string(m['fingerprint']))) {
    throw const FormatException('weekly_scope');
  }
  final summary = map(m['summary']).map((k, v) => MapEntry(k, integer(v)));
  if (!reportSummaryLabels.keys.every(summary.containsKey)) {
    throw const FormatException('weekly_summary');
  }
  final days = (m['days'] as List)
      .map(
        (d) => parseFinancialDayReport({
          ...map(d),
          'generated_at_shop': m['generated_at_shop'],
          'generated_at_utc': m['generated_at_utc'],
        }),
      )
      .toList();
  if (days.map((d) => d.day.id).toSet().length != days.length) {
    throw const FormatException('weekly_duplicate_day');
  }
  final operations = <String>{};
  for (final day in days) {
    final dayDate = date(day.day.date);
    if (day.shopId != m['shop_id'] ||
        day.shopName != m['shop_name'] ||
        day.timeZone != m['time_zone'] ||
        dayDate.isBefore(start) ||
        dayDate.isAfter(end)) {
      throw const FormatException('weekly_day_scope');
    }
    for (final t in day.transactions) {
      if (!operations.add(t.id)) {
        throw const FormatException('weekly_duplicate_operation');
      }
    }
  }
  for (final key in reportSummaryLabels.keys) {
    if (days.fold(BigInt.zero, (n, d) => n + d.value(key)) != summary[key]) {
      throw const FormatException('weekly_incomplete');
    }
  }
  final gold = (m['gold'] as List).map((v) {
    final g = map(v);
    return ReportGold(
      g['karat'] as int,
      integer(g['sold']),
      integer(g['bought']),
    );
  }).toList();
  if (gold.map((g) => g.karat).join(',') != '14,18,21,22,24') {
    throw const FormatException('weekly_karats');
  }
  final groups = (m['groups'] as List).map((v) {
    final g = map(v);
    return WeeklyReportGroup(
      category: string(g['category']),
      karat: g['karat'] as int,
      sold: integer(g['sold']),
      bought: integer(g['bought']),
      saleMovements: integer(g['sale_movements']),
      purchaseMovements: integer(g['purchase_movements']),
    );
  }).toList();
  final expected =
      <
        String,
        ({BigInt sold, BigInt bought, Set<String> sales, Set<String> purchases})
      >{};
  for (final day in days) {
    for (final t in day.transactions) {
      for (final i in t.items) {
        if (i.sold == BigInt.zero && i.bought == BigInt.zero) continue;
        final key = '${i.category}:${i.karat}';
        final previous =
            expected[key] ??
            (
              sold: BigInt.zero,
              bought: BigInt.zero,
              sales: <String>{},
              purchases: <String>{},
            );
        if (i.sold != BigInt.zero) previous.sales.add(t.id);
        if (i.bought != BigInt.zero) previous.purchases.add(t.id);
        expected[key] = (
          sold: previous.sold + i.sold,
          bought: previous.bought + i.bought,
          sales: previous.sales,
          purchases: previous.purchases,
        );
      }
    }
  }
  final seen = <String>{};
  for (final group in groups) {
    final key = '${group.category}:${group.karat}';
    final e = expected[key];
    if (!seen.add(key) ||
        e == null ||
        group.sold != e.sold ||
        group.bought != e.bought ||
        group.saleMovements != BigInt.from(e.sales.length) ||
        group.purchaseMovements != BigInt.from(e.purchases.length)) {
      throw const FormatException('weekly_groups');
    }
  }
  if (seen.length != expected.length) {
    throw const FormatException('weekly_missing_group');
  }
  for (final g in gold) {
    final byDay = days.expand((d) => d.gold).where((v) => v.karat == g.karat);
    final byGroup = groups.where((v) => v.karat == g.karat);
    if (byDay.fold(BigInt.zero, (n, v) => n + v.sold) != g.sold ||
        byDay.fold(BigInt.zero, (n, v) => n + v.bought) != g.bought ||
        byGroup.fold(BigInt.zero, (n, v) => n + v.sold) != g.sold ||
        byGroup.fold(BigInt.zero, (n, v) => n + v.bought) != g.bought) {
      throw const FormatException('weekly_gold');
    }
  }
  final containsOpen = m['contains_open_day'] as bool;
  if (containsOpen != days.any((d) => d.day.status == 'open')) {
    throw const FormatException('weekly_day_state');
  }
  if (m['first_business_date'] != null) date(m['first_business_date']);
  return FinancialWeekReport(
    shopId: string(m['shop_id']),
    shopName: string(m['shop_name']),
    timeZone: string(m['time_zone']),
    startDate: string(m['start_date']),
    endDate: string(m['end_date']),
    serverDate: string(m['server_date']),
    lastSelectableDate: string(m['last_selectable_date']),
    firstBusinessDate: m['first_business_date'] as String?,
    generatedAtShop: string(m['generated_at_shop']),
    fingerprint: string(m['fingerprint']),
    containsOpenDay: containsOpen,
    summary: Map.unmodifiable(summary),
    gold: List.unmodifiable(gold),
    groups: List.unmodifiable(groups),
    days: List.unmodifiable(days),
  );
}

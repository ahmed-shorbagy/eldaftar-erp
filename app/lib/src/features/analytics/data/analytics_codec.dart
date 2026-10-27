import '../../reports/domain/financial_day_report.dart';
import '../domain/period_analytics.dart';

PeriodAnalytics parsePeriodAnalytics(Object? raw) {
  final m = Map<String, dynamic>.from(raw as Map);
  String string(Object? v) => v as String;
  Map<String, dynamic> map(Object? v) => Map<String, dynamic>.from(v as Map);
  BigInt integer(Object? value) {
    if (value is! String || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const FormatException('analytics_integer');
    }
    return BigInt.parse(value);
  }

  DateTime date(Object? value) {
    final s = string(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      throw const FormatException('analytics_date');
    }
    final parsed = DateTime.parse('${s}T00:00:00Z');
    if (parsed.toIso8601String().substring(0, 10) != s) {
      throw const FormatException('analytics_date');
    }
    return parsed;
  }

  final period = string(m['period']);
  if (m['version'] != 1 ||
      !const {'week', 'month', 'year'}.contains(period) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(string(m['fingerprint']))) {
    throw const FormatException('analytics_scope');
  }
  final start = date(m['start_date']);
  final end = date(m['end_date']);
  final anchor = date(m['anchor_date']);
  final lastSelectable = date(m['last_selectable_date']);
  final server = date(m['server_date']);
  if (end.isBefore(start) ||
      lastSelectable.isBefore(server) ||
      anchor.isAfter(lastSelectable)) {
    throw const FormatException('analytics_bounds');
  }
  if (period == 'week' && end.difference(start).inDays != 6) {
    throw const FormatException('analytics_week');
  }
  final summary = map(m['summary']).map((k, v) => MapEntry(k, integer(v)));
  if (!reportSummaryLabels.keys.every(summary.containsKey)) {
    throw const FormatException('analytics_summary');
  }
  final gold = (m['gold'] as List).map((v) {
    final g = map(v);
    return ReportGold(g['karat'] as int, integer(g['sold']), integer(g['bought']));
  }).toList();
  if (gold.map((g) => g.karat).toSet().length != gold.length) {
    throw const FormatException('analytics_gold');
  }
  final isOwner = m['is_owner'] == true;
  final actorsRaw = m['actors'];
  final actors = <AnalyticsActor>[];
  if (actorsRaw is List) {
    for (final row in actorsRaw) {
      final a = map(row);
      final actorGold = (a['gold'] as List).map((g) {
        final item = map(g);
        return AnalyticsActorGold(
          item['karat'] as int,
          integer(item['sold']),
          integer(item['bought']),
        );
      }).toList();
      actors.add(
        AnalyticsActor(
          actorUserId: string(a['actor_user_id']),
          displayName: string(a['display_name']),
          role: string(a['role']),
          gold: actorGold,
          soldTotal: integer(a['sold_total']),
          boughtTotal: integer(a['bought_total']),
        ),
      );
    }
  }
  if (!isOwner && actors.isNotEmpty) {
    throw const FormatException('analytics_actors');
  }
  final dayCount = m['day_count'];
  return PeriodAnalytics(
    shopId: string(m['shop_id']),
    shopName: string(m['shop_name']),
    timeZone: string(m['time_zone']),
    period: period,
    anchorDate: string(m['anchor_date']),
    startDate: string(m['start_date']),
    endDate: string(m['end_date']),
    serverDate: string(m['server_date']),
    lastSelectableDate: string(m['last_selectable_date']),
    firstBusinessDate: m['first_business_date'] is String
        ? m['first_business_date'] as String
        : null,
    generatedAtShop: string(m['generated_at_shop']),
    fingerprint: string(m['fingerprint']),
    containsOpenDay: m['contains_open_day'] == true,
    isOwner: isOwner,
    dayCount: dayCount is int ? dayCount : int.parse('$dayCount'),
    summary: summary,
    gold: gold,
    actors: actors,
  );
}

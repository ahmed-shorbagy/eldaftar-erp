import '../../reports/domain/financial_day_report.dart';

enum AnalyticsPeriod { week, month, year }

String analyticsPeriodApi(AnalyticsPeriod period) => switch (period) {
  AnalyticsPeriod.week => 'week',
  AnalyticsPeriod.month => 'month',
  AnalyticsPeriod.year => 'year',
};

String analyticsPeriodLabel(AnalyticsPeriod period) => switch (period) {
  AnalyticsPeriod.week => 'أسبوع',
  AnalyticsPeriod.month => 'شهر',
  AnalyticsPeriod.year => 'سنة',
};

class AnalyticsActorGold {
  const AnalyticsActorGold(this.karat, this.sold, this.bought);
  final int karat;
  final BigInt sold, bought;
}

class AnalyticsActor {
  const AnalyticsActor({
    required this.actorUserId,
    required this.displayName,
    required this.role,
    required this.gold,
    required this.soldTotal,
    required this.boughtTotal,
  });
  final String actorUserId, displayName, role;
  final List<AnalyticsActorGold> gold;
  final BigInt soldTotal, boughtTotal;
}

class PeriodAnalytics {
  const PeriodAnalytics({
    required this.shopId,
    required this.shopName,
    required this.timeZone,
    required this.period,
    required this.anchorDate,
    required this.startDate,
    required this.endDate,
    required this.serverDate,
    required this.lastSelectableDate,
    required this.firstBusinessDate,
    required this.generatedAtShop,
    required this.fingerprint,
    required this.containsOpenDay,
    required this.isOwner,
    required this.dayCount,
    required this.summary,
    required this.gold,
    required this.actors,
  });

  final String shopId,
      shopName,
      timeZone,
      period,
      anchorDate,
      startDate,
      endDate,
      serverDate,
      lastSelectableDate,
      generatedAtShop,
      fingerprint;
  final String? firstBusinessDate;
  final bool containsOpenDay, isOwner;
  final int dayCount;
  final Map<String, BigInt> summary;
  final List<ReportGold> gold;
  final List<AnalyticsActor> actors;

  BigInt value(String key) => summary[key]!;

  AnalyticsPeriod get periodKind => switch (period) {
    'week' => AnalyticsPeriod.week,
    'month' => AnalyticsPeriod.month,
    'year' => AnalyticsPeriod.year,
    _ => AnalyticsPeriod.week,
  };
}

const analyticsScope =
    'أوزان البيع والشراء حسب الفترة المالية للمتجر. صافي حركة النقد ليس ربحًا. أوزان الموظفين لصاحب المتجر فقط.';

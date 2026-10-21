import 'financial_day_report.dart';

class WeeklyReportGroup {
  const WeeklyReportGroup({
    required this.category,
    required this.karat,
    required this.sold,
    required this.bought,
    required this.saleMovements,
    required this.purchaseMovements,
  });
  final String category;
  final int karat;
  final BigInt sold, bought, saleMovements, purchaseMovements;
}

class FinancialWeekReport {
  const FinancialWeekReport({
    required this.shopId,
    required this.shopName,
    required this.timeZone,
    required this.startDate,
    required this.endDate,
    required this.serverDate,
    required this.lastSelectableDate,
    required this.firstBusinessDate,
    required this.generatedAtShop,
    required this.fingerprint,
    required this.containsOpenDay,
    required this.summary,
    required this.gold,
    required this.groups,
    required this.days,
  });
  final String shopId,
      shopName,
      timeZone,
      startDate,
      endDate,
      serverDate,
      lastSelectableDate,
      generatedAtShop,
      fingerprint;
  final String? firstBusinessDate;
  final bool containsOpenDay;
  final Map<String, BigInt> summary;
  final List<ReportGold> gold;
  final List<WeeklyReportGroup> groups;
  final List<FinancialDayReport> days;
  BigInt value(String key) => summary[key]!;
}

String reportCategory(String category) => switch (category) {
  'worked_jewelry' => 'مشغولات ذهبية',
  'bullion' => 'سبائك',
  'coin' => 'عملات ذهبية',
  'scrap' => 'كسر ذهب',
  'other' => 'أصناف أخرى',
  _ => 'صنف مسجّل',
};
const weeklyReportScope =
    'سبعة تواريخ مالية شاملة تاريخ النهاية؛ تشمل كل الأيام المالية المسجّلة في الفترة. المرتجعات في يوم ترحيلها، وصافي حركة النقد ليس ربحًا.';
const weeklyCategoryScope =
    'أوزان صافية بعد المرتجعات؛ كل صنف وعيار مستقل. قد تظهر العملية في أكثر من مجموعة. لا تُوزّع قيمة العملية الإجمالية على الأصناف.';

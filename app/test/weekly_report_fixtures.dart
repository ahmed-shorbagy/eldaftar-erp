import 'dart:convert';
import 'dart:typed_data';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/application/weekly_report_gateway.dart';
import 'package:eldafttar/src/features/reports/data/weekly_report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/features/reports/domain/financial_week_report.dart';
import 'report_fixtures.dart';

String shiftReportDate(String day, int days) {
  final shifted = DateTime.parse('${day}T00:00:00Z').add(Duration(days: days));
  return shifted.toIso8601String().substring(0, 10);
}

Map<String, dynamic> weekItem(
  String category,
  int karat,
  String milligrams, {
  String sold = '0',
  String bought = '0',
  String name = 'صنف تجريبي',
}) => {
  'name': name,
  'category': category,
  'karat': karat,
  'milligrams': milligrams,
  'sold': sold,
  'bought': bought,
};

Map<String, dynamic> weekTransaction({
  required String id,
  required String sequence,
  required String kind,
  required String label,
  String sale = '0',
  String purchase = '0',
  String expense = '0',
  String cash = '0',
  String openingCash = '0',
  String total = '0',
  String state = 'confirmed',
  String? sourceId,
  String description = 'عملية تجريبية',
  String at = '2026-10-21 01:20:30',
  List<Map<String, dynamic>> items = const [],
  List<Map<String, dynamic>> methods = const [],
  List<Map<String, dynamic>> inventory = const [],
}) => {
  'id': id,
  'sequence': sequence,
  'kind': kind,
  'label': label,
  'state': state,
  'at_shop': at,
  'source_id': sourceId,
  'description': description,
  'original_total': total,
  'sale': sale,
  'purchase': purchase,
  'expense': expense,
  'cash': cash,
  'opening_cash': openingCash,
  'methods': methods,
  'inventory': inventory,
  'items': items,
};

/// A day whose daily codec checks pass. Gross fields follow the server split
/// of positive and negative contributions; counts stay explicit so one
/// multi-category operation is not rewritten as several operations.
Map<String, dynamic> consistentDay({
  required String id,
  required String date,
  required String status,
  required List<Map<String, dynamic>> transactions,
  String saleCount = '0',
  String purchaseCount = '0',
  String expenseCount = '0',
  String returnCount = '0',
  String operationCount = '0',
}) {
  BigInt field(String key) => transactions.fold(
    BigInt.zero,
    (sum, row) => sum + BigInt.parse(row[key] as String),
  );
  BigInt positive(String key) => transactions.fold(BigInt.zero, (sum, row) {
    final value = BigInt.parse(row[key] as String);
    return value > BigInt.zero ? sum + value : sum;
  });
  BigInt negative(String key) => transactions.fold(BigInt.zero, (sum, row) {
    final value = BigInt.parse(row[key] as String);
    return value < BigInt.zero ? sum + value : sum;
  });
  final gold = <int, ({BigInt sold, BigInt bought})>{
    for (final karat in [14, 18, 21, 22, 24])
      karat: (sold: BigInt.zero, bought: BigInt.zero),
  };
  for (final row in transactions) {
    for (final item in row['items'] as List) {
      final mapped = Map<String, dynamic>.from(item as Map);
      final karat = mapped['karat'] as int;
      final current = gold[karat]!;
      gold[karat] = (
        sold: current.sold + BigInt.parse(mapped['sold'] as String),
        bought: current.bought + BigInt.parse(mapped['bought'] as String),
      );
    }
  }
  return {
    'version': 1,
    'shop_id': reportShop,
    'shop_name': 'متجر الذهب التجريبي',
    'day_id': id,
    'date': date,
    'status': status,
    'opened_at_shop': '$date 00:10:00',
    'time_zone': 'Africa/Cairo',
    'fingerprint': 'a' * 64,
    'summary': <String, dynamic>{
      'sales': positive('sale').toString(),
      'sale_returns': (-negative('sale')).toString(),
      'net_sales': field('sale').toString(),
      'purchases': positive('purchase').toString(),
      'purchase_returns': (-negative('purchase')).toString(),
      'net_purchases': field('purchase').toString(),
      'expenses': field('expense').toString(),
      'net_cash': field('cash').toString(),
      'opening_cash': field('opening_cash').toString(),
      'sale_count': saleCount,
      'purchase_count': purchaseCount,
      'expense_count': expenseCount,
      'return_count': returnCount,
      'operation_count': operationCount,
      'audit_row_count': '${transactions.length}',
    },
    'gold': [
      for (final karat in [14, 18, 21, 22, 24])
        {
          'karat': karat,
          'sold': gold[karat]!.sold.toString(),
          'bought': gold[karat]!.bought.toString(),
        },
    ],
    'transactions': transactions,
  };
}

Map<String, dynamic> consistentWeek(
  List<Map<String, dynamic>> days, {
  String? endDate,
  String? serverDate,
  String? lastSelectableDate,
  String? firstBusinessDate,
  bool? containsOpenDay,
  String? fingerprint,
}) {
  final copied = days
      .map(
        (day) => Map<String, dynamic>.from(jsonDecode(jsonEncode(day)) as Map),
      )
      .toList();
  final end = endDate ?? copied.last['date'] as String;
  final start = shiftReportDate(end, -6);
  BigInt summary(String key) => copied.fold(
    BigInt.zero,
    (sum, day) => sum + BigInt.parse(day['summary'][key] as String),
  );
  final gold = <int, ({BigInt sold, BigInt bought})>{
    for (final karat in [14, 18, 21, 22, 24])
      karat: (sold: BigInt.zero, bought: BigInt.zero),
  };
  final groups =
      <
        String,
        ({BigInt sold, BigInt bought, Set<String> sales, Set<String> purchases})
      >{};
  for (final day in copied) {
    for (final raw in day['transactions'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      for (final rawItem in row['items'] as List) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final sold = BigInt.parse(item['sold'] as String);
        final bought = BigInt.parse(item['bought'] as String);
        final karat = item['karat'] as int;
        final current = gold[karat]!;
        gold[karat] = (
          sold: current.sold + sold,
          bought: current.bought + bought,
        );
        if (sold == BigInt.zero && bought == BigInt.zero) continue;
        final key = '${item['category']}:$karat';
        final previous =
            groups[key] ??
            (
              sold: BigInt.zero,
              bought: BigInt.zero,
              sales: <String>{},
              purchases: <String>{},
            );
        if (sold != BigInt.zero) previous.sales.add(row['id'] as String);
        if (bought != BigInt.zero) previous.purchases.add(row['id'] as String);
        groups[key] = (
          sold: previous.sold + sold,
          bought: previous.bought + bought,
          sales: previous.sales,
          purchases: previous.purchases,
        );
      }
    }
  }
  final dates = copied.map((day) => day['date'] as String).toList()..sort();
  return {
    'version': 1,
    'shop_id': reportShop,
    'shop_name': 'متجر الذهب التجريبي',
    'time_zone': 'Africa/Cairo',
    'start_date': start,
    'end_date': end,
    'server_date': serverDate ?? end,
    'last_selectable_date': lastSelectableDate ?? serverDate ?? end,
    'first_business_date':
        firstBusinessDate ?? (dates.isEmpty ? null : dates.first),
    'contains_open_day':
        containsOpenDay ?? copied.any((day) => day['status'] == 'open'),
    'fingerprint': fingerprint ?? 'b' * 64,
    'generated_at_utc': '2026-10-22T10:00:00Z',
    'generated_at_shop': '2026-10-22 12:00:00',
    'summary': {
      for (final key in reportSummaryLabels.keys) key: summary(key).toString(),
    },
    'gold': [
      for (final karat in [14, 18, 21, 22, 24])
        {
          'karat': karat,
          'sold': gold[karat]!.sold.toString(),
          'bought': gold[karat]!.bought.toString(),
        },
    ],
    'groups': [
      for (final entry in groups.entries)
        {
          'category': entry.key.split(':').first,
          'karat': int.parse(entry.key.split(':').last),
          'sold': entry.value.sold.toString(),
          'bought': entry.value.bought.toString(),
          'sale_movements': '${entry.value.sales.length}',
          'purchase_movements': '${entry.value.purchases.length}',
        },
    ],
    'days': copied,
  };
}

Map<String, dynamic> deepReport(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

/// One operation contributes to several category groups and one fully offset
/// 18k group keeps a zero net with two movements.
Map<String, dynamic> richWeek({
  int extraExpenses = 0,
  bool duplicateDate = false,
}) {
  const opening = '9007199254740993';
  final first = consistentDay(
    id: reportDayId,
    date: '2026-10-16',
    status: 'closed',
    saleCount: '1',
    purchaseCount: '1',
    operationCount: '2',
    transactions: [
      weekTransaction(
        id: 'b4444444-4444-4444-8444-000000000001',
        sequence: '1',
        kind: 'opening_balances',
        label: 'أرصدة افتتاحية',
        openingCash: opening,
        at: '2026-10-16 00:10:00',
      ),
      weekTransaction(
        id: 'b4444444-4444-4444-8444-000000000002',
        sequence: '2',
        kind: 'sale',
        label: 'بيع',
        sale: '100001',
        cash: '100001',
        total: '100001',
        description:
            'بيع متعدد الأصناف والعيارات بوصف عربي طويل لاختبار التفاف السطر '
            'واستمرار العنوان عبر صفحات التقرير الأسبوعي دون تقسيم رقم أو حرف.',
        at: '2026-10-16 11:00:00',
        items: [
          weekItem(
            'worked_jewelry',
            14,
            '1000',
            sold: '1000',
            name: 'مشغول ١٤',
          ),
          weekItem(
            'worked_jewelry',
            21,
            '2001',
            sold: '2001',
            name: 'مشغول ٢١',
          ),
          weekItem(
            'worked_jewelry',
            22,
            '1000',
            sold: '1000',
            name: 'مشغول ٢٢',
          ),
          weekItem('coin', 21, '8000', sold: '8000', name: 'جنيه ذهب'),
          weekItem('bullion', 24, '1000', sold: '1000', name: 'سبيكة'),
        ],
      ),
      weekTransaction(
        id: 'b4444444-4444-4444-8444-000000000003',
        sequence: '3',
        kind: 'purchase',
        label: 'شراء',
        purchase: '50001',
        cash: '-20001',
        total: '50001',
        at: '2026-10-16 12:00:00',
        items: [
          weekItem('scrap', 14, '1000', bought: '1000', name: 'كسر'),
          weekItem('scrap', 14, '230', bought: '230', name: 'كسر إضافي'),
        ],
      ),
    ],
  );
  final secondDate = duplicateDate ? '2026-10-16' : '2026-10-22';
  final expenses = [
    for (var index = 0; index < extraExpenses; index++)
      weekTransaction(
        id: 'b4444444-4444-4444-8444-${(100 + index).toString().padLeft(12, '0')}',
        sequence: '${10 + index}',
        kind: 'expense',
        label: 'مصروف',
        expense: '1',
        cash: '-1',
        total: '1',
        description: 'مصروف تجريبي ${index + 1}',
        at: '$secondDate 15:${(index % 60).toString().padLeft(2, '0')}:00',
      ),
  ];
  final second = consistentDay(
    id: oldReportDayId,
    date: secondDate,
    status: 'open',
    saleCount: '1',
    returnCount: '1',
    expenseCount: '${1 + extraExpenses}',
    operationCount: '${3 + extraExpenses}',
    transactions: [
      weekTransaction(
        id: 'b5555555-5555-4555-8555-000000000001',
        sequence: '8',
        kind: 'sale',
        label: 'بيع',
        sale: '15001',
        cash: '15001',
        total: '15001',
        at: '$secondDate 09:00:00',
        items: [weekItem('worked_jewelry', 18, '1500', sold: '1500')],
      ),
      weekTransaction(
        id: 'b5555555-5555-4555-8555-000000000002',
        sequence: '9',
        kind: 'sale_return',
        label: 'مرتجع بيع',
        sale: '-15001',
        cash: '-15001',
        total: '15001',
        sourceId: 'b5555555-5555-4555-8555-000000000001',
        at: '$secondDate 09:30:00',
        items: [weekItem('worked_jewelry', 18, '1500', sold: '-1500')],
      ),
      weekTransaction(
        id: 'b5555555-5555-4555-8555-000000000003',
        sequence: '10',
        kind: 'expense',
        label: 'مصروف',
        expense: '123',
        cash: '-123',
        total: '123',
        at: '$secondDate 10:00:00',
      ),
      ...expenses,
    ],
  );
  return consistentWeek(
    [first, second],
    serverDate: '2026-10-22',
    lastSelectableDate: '2026-10-22',
  );
}

class FakeShopReports implements ReportGateway, WeeklyReportGateway {
  FakeShopReports() {
    week = richWeek();
  }
  final FakeReports days = FakeReports();
  Object? session = 'session';
  bool failDays = false;
  bool failWeek = false;
  Map<String, dynamic> week = {};
  final List<String?> weekEnds = [];
  int weekReads = 0, weekStores = 0;
  Future<void> Function()? onWeekStore;
  @override
  Object? reportSession(String userId) => session;
  @override
  Future<List<ReportDay>> reportDays(String userId, String shopId) async {
    if (failDays) throw StateError('unavailable');
    return days.days;
  }

  @override
  Future<FinancialDayReport> financialDayReport(
    String userId,
    String shopId,
    String dayId,
  ) {
    days.fail = failDays;
    return days.financialDayReport(userId, shopId, dayId);
  }

  @override
  Future<Uint8List> storeReportPdf(
    String userId,
    FinancialDayReport report,
    Uint8List bytes,
  ) => days.storeReportPdf(userId, report, bytes);
  @override
  Future<FinancialWeekReport> financialWeekReport(
    String userId,
    String shopId, {
    String? endDate,
  }) async {
    weekReads++;
    weekEnds.add(endDate);
    if (failWeek) throw StateError('unavailable');
    final report = parseFinancialWeekReport(week);
    if (endDate != null && report.endDate != endDate) {
      throw const FormatException('weekly_report_scope');
    }
    return report;
  }

  @override
  Future<Uint8List> storeWeeklyReportPdf(
    String userId,
    FinancialWeekReport report,
    Uint8List bytes,
  ) async {
    weekStores++;
    await onWeekStore?.call();
    return Uint8List.fromList(bytes);
  }
}

import 'dart:typed_data';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';

const reportShop = 'b2222222-2222-4222-8222-222222222222';
const reportUser = 'b1111111-1111-4111-8111-111111111111';
const reportDayId = 'b3333333-3333-4333-8333-333333333333';
const oldReportDayId = 'b3333333-3333-4333-8333-333333333334';
Map<String, dynamic> reportFixture({
  String day = reportDayId,
  bool empty = false,
  int sales = 1,
  String? date,
  String? status,
  int idOffset = 0,
}) {
  Map<String, dynamic> row(
    int n,
    String kind,
    String label,
    String total,
    String cash,
  ) => {
    'id':
        'b4444444-4444-4444-8444-${(n + idOffset).toString().padLeft(12, '0')}',
    'sequence': '$n',
    'kind': kind,
    'label': label,
    'state': 'confirmed',
    'at_shop': '2026-10-21 01:20:30',
    'source_id': null,
    'description': 'عملية تجريبية',
    'original_total': total,
    'sale': kind == 'sale' ? total : '0',
    'purchase': kind == 'purchase' ? total : '0',
    'expense': kind == 'expense' ? total : '0',
    'cash': cash,
    'opening_cash': '0',
    'methods': [
      {'method': 'cash', 'amount': cash},
    ],
    'inventory': [],
    'items': [],
  };
  final rows = <Map<String, dynamic>>[];
  if (!empty) {
    rows.add(
      row(1, 'opening_balances', 'أرصدة افتتاحية', '0', '0')
        ..['opening_cash'] = '9007199254740993',
    );
    for (var i = 0; i < sales; i++) {
      rows.add(
        row(i + 2, 'sale', 'بيع', '10001', '10001')
          ..['items'] = [
            {
              'name': 'خاتم تجريبي باسم طويل لاختبار قراءة الوصف العربي',
              'category': 'worked_jewelry',
              'karat': 21,
              'milligrams': '2001',
              'sold': '2001',
              'bought': '0',
            },
          ],
      );
    }
    rows.add(
      row(sales + 2, 'purchase', 'شراء', '50001', '-20001')
        ..['items'] = [
          {
            'name': 'كسر ذهب',
            'category': 'scrap',
            'karat': 14,
            'milligrams': '1234',
            'sold': '0',
            'bought': '1234',
          },
        ],
    );
    rows.add(row(sales + 3, 'expense', 'مصروف', '123', '-123'));
  }
  return {
    'version': 1,
    'shop_id': reportShop,
    'shop_name': 'متجر الذهب التجريبي',
    'day_id': day,
    'date': date ?? (day == reportDayId ? '2026-10-21' : '2026-10-19'),
    'status': status ?? (day == reportDayId ? 'open' : 'closed'),
    'opened_at_shop': date == null ? '2026-10-21 00:10:00' : '$date 00:10:00',
    'time_zone': 'Africa/Cairo',
    'fingerprint': 'a' * 64,
    'generated_at_utc': '2026-10-21T10:00:00Z',
    'generated_at_shop': '2026-10-21 13:00:00',
    'summary': <String, dynamic>{
      'sales': empty ? '0' : '${10001 * sales}',
      'sale_returns': '0',
      'net_sales': empty ? '0' : '${10001 * sales}',
      'purchases': empty ? '0' : '50001',
      'purchase_returns': '0',
      'net_purchases': empty ? '0' : '50001',
      'expenses': empty ? '0' : '123',
      'net_cash': empty ? '0' : '${10001 * sales - 20124}',
      'opening_cash': empty ? '0' : '9007199254740993',
      'sale_count': empty ? '0' : '$sales',
      'purchase_count': empty ? '0' : '1',
      'expense_count': empty ? '0' : '1',
      'return_count': '0',
      'operation_count': empty ? '0' : '${sales + 2}',
      'audit_row_count': '${rows.length}',
    },
    'gold': [
      for (final k in [14, 18, 21, 22, 24])
        {
          'karat': k,
          'sold': !empty && k == 21 ? '${2001 * sales}' : '0',
          'bought': !empty && k == 14 ? '1234' : '0',
        },
    ],
    'transactions': rows,
  };
}

class FakeReports implements ReportGateway {
  Object? session = 'session';
  List<ReportDay> days = const [
    ReportDay(reportDayId, '2026-10-21', 'open', '2026-10-21 00:10:00'),
    ReportDay(oldReportDayId, '2026-10-19', 'closed', '2026-10-19 09:00:00'),
  ];
  Map<String, dynamic> data = reportFixture();
  bool fail = false;
  int reads = 0, stores = 0;
  Future<FinancialDayReport> Function(String)? read;
  Future<void> Function()? store;
  @override
  Object? reportSession(String userId) => session;
  @override
  Future<List<ReportDay>> reportDays(String userId, String shopId) async {
    if (fail) throw StateError('unavailable');
    return days;
  }

  @override
  Future<FinancialDayReport> financialDayReport(
    String userId,
    String shopId,
    String dayId,
  ) async {
    reads++;
    if (fail) throw StateError('unavailable');
    return read != null
        ? await read!(dayId)
        : parseFinancialDayReport(
            dayId == reportDayId
                ? data
                : reportFixture(day: dayId, empty: true),
          );
  }

  @override
  Future<Uint8List> storeReportPdf(
    String userId,
    FinancialDayReport report,
    Uint8List bytes,
  ) async {
    stores++;
    await store?.call();
    return Uint8List.fromList(bytes);
  }
}

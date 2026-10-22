import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/media/data/r2_media_client.dart';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/application/weekly_report_export.dart';
import 'package:eldafttar/src/features/reports/data/weekly_report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'report_fixtures.dart';
import 'weekly_report_fixtures.dart';

void main() {
  test('weekly values stay exact past binary integer precision', () {
    final report = parseFinancialWeekReport(richWeek());
    expect(reportMoney(report.value('opening_cash')), '90,071,992,547,409.93');
    expect(reportMoney(report.value('net_sales')), '1,000.01');
    expect(reportMoney(report.value('net_purchases')), '500.01');
    expect(reportMoney(report.value('net_cash')), '798.77');
    expect(reportGrams(report.gold[2].sold), '10.001');
    expect(reportGrams(report.gold[0].bought), '1.230');
    final offset = report.groups.singleWhere(
      (group) => group.category == 'worked_jewelry' && group.karat == 18,
    );
    expect(offset.sold, BigInt.zero);
    expect(offset.saleMovements, BigInt.two);
    final scrap = report.groups.singleWhere(
      (group) => group.category == 'scrap' && group.karat == 14,
    );
    expect(scrap.purchaseMovements, BigInt.one);
    final movementSum = report.groups.fold<BigInt>(
      BigInt.zero,
      (sum, group) => sum + group.saleMovements,
    );
    expect(movementSum, isNot(report.value('sale_count')));
    expect(movementSum > report.value('sale_count'), isTrue);
  });

  test('same financial date can contain two distinct days', () {
    final report = parseFinancialWeekReport(richWeek(duplicateDate: true));
    expect(report.days.map((day) => day.day.date).toSet(), {'2026-10-16'});
    expect(report.days.map((day) => day.day.id).toSet(), hasLength(2));
    expect(report.startDate, '2026-10-10');
    expect(report.endDate, '2026-10-16');
  });

  test('empty and large historical weeks reconcile complete details', () {
    final empty = parseFinancialWeekReport(
      consistentWeek(const [], endDate: '2026-10-22'),
    );
    expect(empty.days, isEmpty);
    expect(empty.groups, isEmpty);
    expect(empty.value('net_sales'), BigInt.zero);
    expect(empty.gold.map((gold) => gold.karat), [14, 18, 21, 22, 24]);
    final large = parseFinancialWeekReport(richWeek(extraExpenses: 100));
    final rows = large.days.fold<int>(
      0,
      (sum, day) => sum + day.transactions.length,
    );
    expect(rows, greaterThan(100));
    expect(large.value('audit_row_count'), BigInt.from(rows));
    expect(large.value('expenses'), BigInt.from(223));
  });

  test('rejects malformed, duplicate and inconsistent weekly payloads', () {
    final base = richWeek();
    final mutations = <void Function(Map<String, dynamic>)>[
      (raw) => raw['version'] = 2,
      (raw) =>
          raw['end_date'] = shiftReportDate(raw['start_date'] as String, 5),
      (raw) => raw['end_date'] = '2026-02-31',
      (raw) => raw['last_selectable_date'] = '2026-10-21',
      (raw) => raw['fingerprint'] = 'xyz',
      (raw) => raw['summary']['sales'] = 100001,
      (raw) => (raw['summary'] as Map).remove('net_cash'),
      (raw) => raw['summary']['net_sales'] = '1',
      (raw) => raw['days'][1]['day_id'] = raw['days'][0]['day_id'],
      (raw) => raw['days'][1]['shop_id'] = 'other-shop',
      (raw) => raw['days'][0]['date'] = '2026-10-01',
      (raw) => raw['days'][1]['transactions'][0]['id'] =
          raw['days'][0]['transactions'][1]['id'],
      (raw) => raw['gold'][2]['sold'] = '1',
      (raw) => raw['gold'].removeAt(0),
      (raw) => (raw['groups'] as List).removeAt(0),
      (raw) => raw['groups'][0]['sale_movements'] = '9',
      (raw) => raw['contains_open_day'] = false,
      (raw) => raw['groups'].add({
        'category': 'other',
        'karat': 14,
        'sold': '1',
        'bought': '0',
        'sale_movements': '1',
        'purchase_movements': '0',
      }),
    ];
    for (final change in mutations) {
      final raw = deepReport(base);
      change(raw);
      expect(() => parseFinancialWeekReport(raw), throwsFormatException);
    }
  });

  test(
    'readback precedes output and temporary weekly bytes are wiped',
    () async {
      final gateway = FakeShopReports();
      Uint8List? received;
      final report = parseFinancialWeekReport(gateway.week);
      final result =
          await WeeklyReportExport(
            gateway,
            gateway,
            reportUser,
            reportShop,
            () => true,
          ).run(report, (_) async => Uint8List.fromList([9, 8, 7]), (
            bytes,
            name,
            allowed,
          ) async {
            received = bytes;
            expect(gateway.weekStores, 1);
            expect(gateway.weekReads, 3);
            expect(allowed(), isTrue);
            expect(
              name,
              'تقرير-أسبوعي-${report.startDate}-${report.endDate}.pdf',
            );
            return 'saved';
          });
      expect(result, 'saved');
      expect(received, [0, 0, 0]);
    },
  );

  test('in-range fingerprint change blocks upload and output', () async {
    final gateway = FakeShopReports();
    var output = 0;
    final result =
        await WeeklyReportExport(
          gateway,
          gateway,
          reportUser,
          reportShop,
          () => true,
        ).run(
          parseFinancialWeekReport(gateway.week),
          (_) async {
            gateway.week['fingerprint'] = 'c' * 64;
            return Uint8List(1);
          },
          (bytes, name, allowed) async {
            output++;
            return 'saved';
          },
        );
    expect(result, 'stale');
    expect(gateway.weekStores, 0);
    expect(output, 0);
  });

  test(
    'session loss and upload interruption stay retryable without output',
    () async {
      final denied = FakeShopReports();
      denied.onWeekStore = () async {
        denied.session = null;
      };
      var output = 0;
      expect(
        await WeeklyReportExport(
          denied,
          denied,
          reportUser,
          reportShop,
          () => true,
        ).run(
          parseFinancialWeekReport(denied.week),
          (_) async => Uint8List(1),
          (bytes, name, allowed) async {
            output++;
            return 'saved';
          },
        ),
        'denied',
      );
      expect(output, 0);
      final interrupted = FakeShopReports()
        ..onWeekStore = () async {
          throw StateError('upload interrupted');
        };
      final flow = WeeklyReportExport(
        interrupted,
        interrupted,
        reportUser,
        reportShop,
        () => true,
      );
      final report = parseFinancialWeekReport(interrupted.week);
      expect(
        await flow.run(
          report,
          (_) async => Uint8List(1),
          (bytes, name, allowed) async => 'saved',
        ),
        'failed',
      );
      interrupted.onWeekStore = null;
      expect(
        await flow.run(
          report,
          (_) async => Uint8List(1),
          (bytes, name, allowed) async => 'cancelled',
        ),
        'cancelled',
      );
    },
  );

  test(
    'duplicate weekly export is busy and a stale confirmation is not output',
    () async {
      final gateway = FakeShopReports();
      final wait = Completer<Uint8List>();
      final flow = WeeklyReportExport(
        gateway,
        gateway,
        reportUser,
        reportShop,
        () => true,
      );
      final report = parseFinancialWeekReport(gateway.week);
      final first = flow.run(
        report,
        (_) => wait.future,
        (bytes, name, allowed) async => 'saved',
      );
      expect(
        await flow.run(
          report,
          (_) async => Uint8List(1),
          (bytes, name, allowed) async => 'saved',
        ),
        'busy',
      );
      wait.complete(Uint8List(1));
      expect(await first, 'saved');
      gateway.onWeekStore = () async {
        throw const ReportChanged();
      };
      expect(
        await flow.run(
          report,
          (_) async => Uint8List(1),
          (bytes, name, allowed) async => throw StateError('must not open'),
        ),
        'stale',
      );
    },
  );

  test(
    'HTTP weekly path rejects scope drift, bad bytes and stale confirmation',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7\n%%EOF\n'));
      final sha = await R2MediaClient.sha256Hex(bytes);
      final key = 'report-pdf/$reportShop/$sha.pdf';
      var wrongShop = true;
      var tamper = true;
      var stale = false;
      var replayed = false;
      final requests = <String>[];
      final gateway = HttpOpeningGateway(
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/get_financial_week_report_v1')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final week = deepReport(richWeek());
            if (wrongShop) week['shop_id'] = 'other';
            if (body['p_end_date'] == '2026-10-01') {
              week['end_date'] = '2026-10-22';
            }
            return http.Response(
              jsonEncode(week),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path.endsWith('/confirm_financial_week_pdf_v1')) {
            if (stale) {
              return http.Response(
                jsonEncode({'message': 'stale_report'}),
                400,
              );
            }
            return http.Response(
              jsonEncode({
                'object_key': key,
                'sha256': sha,
                'byte_size': bytes.length,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/r2-media')) {
            final body = jsonDecode(request.body);
            return http.Response(
              jsonEncode(switch (body['op']) {
                'upload' => {
                  'object_key': key,
                  'url': 'https://r2.example/put',
                  'headers': {'content-type': 'application/pdf'},
                },
                'confirm' => {
                  'object_key': key,
                  'sha256': sha,
                  'byte_size': bytes.length,
                  'replayed': replayed,
                },
                _ => {'url': 'https://r2.example/get'},
              }),
              200,
            );
          }
          if (request.url.path == '/put') return http.Response('', 200);
          if (request.url.path == '/get') {
            return http.Response.bytes(tamper ? [1, 2, 3] : bytes, 200);
          }
          return http.Response('{}', 200);
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'public',
        accessToken: () => 'token',
        currentUserId: () => reportUser,
      );
      await expectLater(
        gateway.financialWeekReport(
          reportUser,
          reportShop,
          endDate: '2026-10-22',
        ),
        throwsFormatException,
      );
      wrongShop = false;
      await expectLater(
        gateway.financialWeekReport(
          reportUser,
          reportShop,
          endDate: '2026-10-01',
        ),
        throwsFormatException,
      );
      final report = await gateway.financialWeekReport(
        reportUser,
        reportShop,
        endDate: '2026-10-22',
      );
      await expectLater(
        gateway.storeWeeklyReportPdf(reportUser, report, bytes),
        throwsFormatException,
      );
      tamper = false;
      expect(
        await gateway.storeWeeklyReportPdf(reportUser, report, bytes),
        bytes,
      );
      replayed = true;
      expect(
        await gateway.storeWeeklyReportPdf(reportUser, report, bytes),
        bytes,
      );
      stale = true;
      await expectLater(
        gateway.storeWeeklyReportPdf(reportUser, report, bytes),
        throwsA(isA<ReportChanged>()),
      );
      expect(
        requests.any((path) => path.endsWith('/confirm_financial_week_pdf_v1')),
        isTrue,
      );
      expect(
        requests.any((path) => path.endsWith('/confirm_financial_day_pdf_v1')),
        isFalse,
      );
      expect(requests.any((path) => path.contains('invoice')), isFalse);
    },
  );
}

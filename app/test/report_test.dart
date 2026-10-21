import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/reports/application/report_export.dart';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/media/data/r2_media_client.dart';
import 'report_fixtures.dart';

void main() {
  test(
    'exact report preserves values beyond binary integer precision and milligrams',
    () {
      final r = parseFinancialDayReport(reportFixture());
      expect(reportMoney(r.value('opening_cash')), '90,071,992,547,409.93');
      expect(reportMoney(r.value('net_cash')), '-101.23');
      expect(reportGrams(r.gold[2].sold), '2.001');
      expect(reportGrams(r.gold[0].bought), '1.234');
    },
  );
  test(
    'rejects partial details, wrong gold, duplicate rows and numeric JSON amounts',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => (m['transactions'] as List).removeLast(),
        (m) => m['gold'][2]['sold'] = '2000',
        (m) => m['transactions'][1]['id'] = m['transactions'][0]['id'],
        (m) => m['summary']['sales'] = 10001,
      ]) {
        final raw = reportFixture();
        change(raw);
        expect(() => parseFinancialDayReport(raw), throwsA(anything));
      }
    },
  );
  test('empty complete report is valid', () {
    expect(
      parseFinancialDayReport(reportFixture(empty: true)).transactions,
      isEmpty,
    );
  });
  test('R2 readback precedes output and temporary bytes are wiped', () async {
    final g = FakeReports();
    var calls = 0;
    Uint8List? received;
    final flow = ReportExport(g, reportUser, reportShop, () => true);
    final result = await flow.run(
      parseFinancialDayReport(g.data),
      (_) async => Uint8List.fromList([1, 2, 3]),
      (b, n, a) async {
        calls++;
        received = b;
        expect(g.stores, 1);
        expect(a(), isTrue);
        expect(n, 'تقرير-2026-10-21.pdf');
        return 'saved';
      },
    );
    expect(result, 'saved');
    expect(calls, 1);
    expect(received, [0, 0, 0]);
    expect(flow.busy, isFalse);
  });
  test('changed report during render blocks upload and output', () async {
    final g = FakeReports();
    var output = 0;
    final result = await ReportExport(g, reportUser, reportShop, () => true)
        .run(
          parseFinancialDayReport(g.data),
          (_) async {
            g.data['fingerprint'] = 'b' * 64;
            return Uint8List(1);
          },
          (b, n, a) async {
            output++;
            return 'saved';
          },
        );
    expect(result, 'stale');
    expect(g.stores, 0);
    expect(output, 0);
  });
  test('session loss after R2 upload blocks native output', () async {
    final g = FakeReports()..store = () async {};
    g.store = () async {
      g.session = null;
    };
    var output = 0;
    final result = await ReportExport(g, reportUser, reportShop, () => true)
        .run(parseFinancialDayReport(g.data), (_) async => Uint8List(1), (
          b,
          n,
          a,
        ) async {
          output++;
          return 'saved';
        });
    expect(result, 'denied');
    expect(output, 0);
  });
  test(
    'server reports a concurrent change during R2 confirmation as stale',
    () async {
      final g = FakeReports()
        ..store = () async {
          throw const ReportChanged();
        };
      final result = await ReportExport(g, reportUser, reportShop, () => true)
          .run(
            parseFinancialDayReport(g.data),
            (_) async => Uint8List(1),
            (b, n, a) async => throw StateError('must not open'),
          );
      expect(result, 'stale');
    },
  );
  test('duplicate export suppressed; failure permits retry', () async {
    final g = FakeReports();
    final wait = Completer<Uint8List>();
    final flow = ReportExport(g, reportUser, reportShop, () => true);
    final r = parseFinancialDayReport(g.data);
    final first = flow.run(
      r,
      (_) => wait.future,
      (b, n, a) async => 'cancelled',
    );
    expect(
      await flow.run(r, (_) async => Uint8List(1), (b, n, a) async => 'saved'),
      'busy',
    );
    wait.completeError(StateError('render'));
    expect(await first, 'failed');
    expect(
      await flow.run(
        r,
        (_) async => Uint8List(1),
        (b, n, a) async => 'cancelled',
      ),
      'cancelled',
    );
  });
  test('HTTP rejects cross-shop response and unverified R2 bytes', () async {
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7\n%%EOF\n'));
    final sha = await R2MediaClient.sha256Hex(bytes);
    final key = 'report-pdf/$reportShop/$sha.pdf';
    var wrongShop = true;
    var tamper = true;
    final requests = <String>[];
    final g = HttpOpeningGateway(
      client: MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.path.endsWith('/get_financial_day_report_v1')) {
          return http.Response(
            jsonEncode(
              reportFixture()..['shop_id'] = wrongShop ? 'other' : reportShop,
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (r.url.path.endsWith('/r2-media')) {
          final body = jsonDecode(r.body);
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
                'replayed': false,
              },
              _ => {'url': 'https://r2.example/get'},
            }),
            200,
          );
        }
        if (r.url.path == '/put') return http.Response('', 200);
        if (r.url.path == '/get') {
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
      g.financialDayReport(reportUser, reportShop, reportDayId),
      throwsA(anything),
    );
    wrongShop = false;
    final r = await g.financialDayReport(reportUser, reportShop, reportDayId);
    await expectLater(
      g.storeReportPdf(reportUser, r, bytes),
      throwsA(anything),
    );
    tamper = false;
    expect(await g.storeReportPdf(reportUser, r, bytes), bytes);
    expect(
      requests.any((s) => s.endsWith('/confirm_financial_day_pdf_v1')),
      isTrue,
    );
  });
}

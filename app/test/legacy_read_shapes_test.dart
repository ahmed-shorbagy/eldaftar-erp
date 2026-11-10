import 'dart:io';
import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'daily_ledger_http_test.dart' show dayId;
import 'meeting_calendar_and_count_test.dart' show calendarBody;
import 'support/legacy_361ad2e_ledger_codec.dart' as legacy;

/// Guards ADR 0044 C-D1 with the real parser of the owner's installed build
/// (`361ad2e`), copied verbatim into `test/support`. Any later change to the
/// legacy reads (home, date, operation page) must keep these fixtures passing.

Map<String, Object?> _feedRow(
  String kind,
  String label,
  String id,
  String sequence,
) => {
  'kind': kind,
  'label_ar': label,
  'operation_id': id,
  'actor_display_name': 'منى',
  'occurred_at': '2026-09-26T09:00:00Z',
  'occurred_at_cairo': '2026-09-26T12:00:00',
  'shop_sequence': sequence,
  'occurred_at_shop': '2026-09-26T12:00:00',
  'total_pounds': '200.00',
};

/// What the legacy home returns after private.legacy_361ad2e_feed: a sale,
/// a handed-over repair, and a later collection, all in 361ad2e words.
Map<String, Object?> legacyHome() => {
  ...calendarBody(),
  'feed': [
    _feedRow('sale', 'بيع', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1', '9'),
    _feedRow(
      'repair_fee',
      'أجرة إصلاح',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
      '8',
    ),
    _feedRow(
      'repair_fee',
      'أجرة إصلاح',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
      '7',
    ),
  ],
  'journal_context': {
    ...(calendarBody()['journal_context']! as Map<String, Object?>),
    'day_ids': [dayId],
  },
};

Map<String, Object?> _with(
  Map<String, Object?> body,
  void Function(Map<String, Object?>) edit,
) {
  final copy = jsonDecode(jsonEncode(body)) as Map<String, Object?>;
  edit(copy);
  return copy;
}

/// What get_daily_ledger_home_v2 returns for the same day.
Map<String, Object?> v2Home() => _with(legacyHome(), (b) {
  b['day_reset'] = false;
  b['last_closed_business_date'] = null;
  final summary = b['day_summary']! as Map<String, Object?>;
  summary['repair_piastres'] = '40000';
  summary['repair_count'] = 2;
  ((b['feed']! as List)[1] as Map)['label_ar'] = 'أجرة مرمة';
  final row = (b['feed']! as List)[2] as Map;
  row['kind'] = 'repair_fee_collection';
  row['label_ar'] = 'تحصيل متبقي مرمة';
});

void main() {
  test('legacy home output passes the real 361ad2e parser', () {
    expect(() => legacy.parseDailyLedger(legacyHome()), returnsNormally);
    expect(legacy.parseDailyLedger(legacyHome()).feed, hasLength(3));
  });

  group('each 2026-11-09/10 addition breaks the 361ad2e parser', () {
    final cases = <String, void Function(Map<String, Object?>)>{
      'day_reset': (b) => b['day_reset'] = true,
      'last_closed_business_date': (b) =>
          b['last_closed_business_date'] = '2026-09-25',
      'repair day_summary keys': (b) {
        final summary = b['day_summary']! as Map<String, Object?>;
        summary['repair_piastres'] = '0';
        summary['repair_count'] = 0;
      },
      'repair label «أجرة مرمة»': (b) =>
          ((b['feed']! as List)[1] as Map)['label_ar'] = 'أجرة مرمة',
      'kind repair_fee_collection': (b) {
        final row = (b['feed']! as List)[2] as Map;
        row['kind'] = 'repair_fee_collection';
        row['label_ar'] = 'تحصيل متبقي مرمة';
      },
      'kind debt_settlement': (b) {
        final row = (b['feed']! as List)[2] as Map;
        row['kind'] = 'debt_settlement';
        row['label_ar'] = 'سداد دين';
      },
      'unknown feed key': (b) =>
          ((b['feed']! as List)[0] as Map)['customer_id'] = null,
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(
          () => legacy.parseDailyLedger(_with(legacyHome(), entry.value)),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  test('the current parser accepts the v2 vocabulary', () {
    expect(parseDailyLedger(v2Home()).feed, hasLength(3));
    // ...and rejects the frozen legacy label, so it must never read v1.
    expect(
      () => parseDailyLedger(legacyHome()),
      throwsA(isA<FormatException>()),
    );
  });

  test('the current parser accepts debt and gold-obligation rows', () {
    for (final (kind, label) in const [
      ('debt_settlement', 'سداد دين'),
      ('gold_obligation_acquisition', 'استلام ذهب مقابل التزام'),
      ('gold_obligation_settlement', 'سداد التزام ذهب'),
    ]) {
      final body = _with(v2Home(), (b) {
        final row = (b['feed']! as List)[2] as Map;
        row['kind'] = kind;
        row['label_ar'] = label;
      });
      expect(() => parseDailyLedger(body), returnsNormally, reason: kind);
    }
  });

  test('HTTP gateway calls the _v2 home read', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
        jsonEncode(calendarBody()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final gateway = HttpOpeningGateway(
      client: client,
      supabaseUrl: 'https://example.test/',
      publishableKey: 'publishable-key',
      accessToken: () => 'access-token',
      currentUserId: () => 'owner-a',
    );
    await gateway.ledger(callerUserId: 'owner-a');
    expect(paths, ['/rest/v1/rpc/get_daily_ledger_home_v2']);
  });

  test('app code calls no legacy-frozen read name', () {
    // Older builds own these names (ADR 0044 C-D1). The current app must
    // read the _v2 names so legacy shapes can stay frozen.
    final source = [
      'lib/src/features/daily_ledger/data/http_opening_gateway.dart',
    ].map((path) => _read(path)).join('\n');
    for (final name in const [
      "'get_daily_ledger_home_v1'",
      "'get_ledger_date_v1'",
      "'get_financial_day_report_v1'",
      "'get_ledger_operation_page'",
    ]) {
      expect(source.contains(name), isFalse, reason: name);
    }
  });
}

String _read(String path) => File(path).readAsStringSync();

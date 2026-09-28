import 'dart:async';
import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/opening_flow.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const bigPiastres = '9007199254740993';
const maxPiastres = '9223372036854775807';
const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

String poundsFor(String piastres) =>
    (Piastres.parseWire(piastres) as Accepted<Piastres>).value.poundsText;

List<Map<String, Object?>> cashRows({
  String piastres = '1000000',
  String? pounds,
}) {
  final shown = pounds ?? poundsFor(piastres);
  return [
    for (final method in const [
      ['cash', 'نقدي'],
      ['instant_transfer', 'انستا'],
      ['wallet', 'محفظة'],
      ['card', 'فيزا'],
    ])
      {
        'method': method[0],
        'label_ar': method[1],
        'piastres': method[0] == 'cash' ? piastres : '0',
        'pounds': method[0] == 'cash' ? shown : '0.00',
      },
  ];
}

Map<String, Object?> uninitializedBody() => {
  'read_model_version': 1,
  'state': 'uninitialized',
  'entitlement_status': 'active',
  'can_confirm': true,
  'business_day': null,
  'cash': <Object?>[],
  'stock': <Object?>[],
  'scrap': <Object?>[],
  'feed': <Object?>[],
};

Map<String, Object?> confirmedBody({Object? piastres = '1000000'}) => {
  'read_model_version': 1,
  'state': 'confirmed',
  'entitlement_status': 'active',
  'can_confirm': false,
  'business_day': {
    'id': dayId,
    'business_date': '2026-09-26',
    'opened_at': '2026-09-26T00:30:00+00:00',
  },
  'cash': [
    for (final row in cashRows())
      row['method'] == 'cash'
          ? {
              ...row,
              'piastres': piastres,
              'pounds': piastres is String
                  ? poundsFor(piastres)
                  : row['pounds'],
            }
          : row,
  ],
  'stock': <Object?>[],
  'scrap': <Object?>[],
  'feed': [
    {
      'kind': 'opening_balances_confirmed',
      'label_ar': 'رصيد افتتاحي',
      'operation_id': operationId,
      'actor_display_name': 'منى',
      'occurred_at': '2026-09-26T00:30:00+00:00',
      'occurred_at_cairo': '2026-09-26T03:30:00',
    },
  ],
};

HttpOpeningGateway gateway(
  http.Client client, {
  String? Function()? currentUserId,
  String Function()? accessToken,
}) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test/',
  publishableKey: 'publishable-key',
  accessToken: accessToken ?? (() => 'access-token'),
  currentUserId: currentUserId ?? (() => 'owner-a'),
);

void expectHeaders(http.Request request) {
  expect(request.headers['apikey'], 'publishable-key');
  expect(request.headers['authorization'], 'Bearer access-token');
  expect(request.headers['content-type'], contains('application/json'));
  expect(request.headers['accept'], 'application/json');
}

void main() {
  test(
    'confirm posts the canonical payload and keeps a big decimal string',
    () async {
      final draft = OpeningDraft.compose(
        cash: {
          CashMethod.cash:
              (Piastres.parseWire(bigPiastres) as Accepted<Piastres>).value,
        },
      );
      final payload = (draft as Accepted<OpeningDraft>).value.toCanonicalJson();
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'operation_id': operationId,
            'business_day_id': dayId,
            'business_date': '2026-09-26',
            'replayed': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await gateway(client).confirm(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
        payload: payload,
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/rest/v1/rpc/confirm_opening_balances');
      expectHeaders(seen);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['p_idempotency_key'], '11111111-1111-4111-8111-111111111111');
      final sent = body['p_payload'] as Map<String, dynamic>;
      expect(sent['cash']['cash'], bigPiastres);
      expect(sent['cash']['cash'], isA<String>());
      expect(result, isA<ConfirmCommitted>());
    },
  );

  test('status and ledger use their rpc paths', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expectHeaders(request);
      if (request.url.path.endsWith('get_opening_status')) {
        expect(jsonDecode(request.body), {
          'p_idempotency_key': '11111111-1111-4111-8111-111111111111',
        });
        return http.Response(jsonEncode({'status': 'absent'}), 200);
      }
      expect(jsonDecode(request.body), <String, dynamic>{});
      return http.Response(jsonEncode(uninitializedBody()), 200);
    });
    final api = gateway(client);
    expect(
      await api.status(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      ),
      isA<StatusAbsent>(),
    );
    final ledger = await api.ledger(callerUserId: 'owner-a');
    expect(ledger.isUninitialized, isTrue);
    expect(paths, [
      '/rest/v1/rpc/get_opening_status',
      '/rest/v1/rpc/get_daily_ledger',
    ]);
  });

  test(
    'a decimal string above the safe integer range stays a string',
    () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(confirmedBody(piastres: bigPiastres))),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final ledger = await gateway(client).ledger(callerUserId: 'owner-a');
      final cash = ledger.cash.singleWhere((line) => line.method == 'cash');
      expect(cash.piastres, bigPiastres);
      expect(cash.piastres, isA<String>());
      expect(cash.pounds, poundsFor(bigPiastres));
      expect(ledger.feed.single.occurredAtCairo, '2026-09-26T03:30:00');
    },
  );

  test('a numeric version or numeric amount is rejected', () async {
    final numericVersion = MockClient((request) async {
      final body = uninitializedBody();
      body['read_model_version'] = 1.2;
      return http.Response(jsonEncode(body), 200);
    });
    expect(
      gateway(numericVersion).ledger(callerUserId: 'owner-a'),
      throwsA(isA<LedgerReadException>()),
    );

    final numericAmount = MockClient((request) async {
      return http.Response(jsonEncode(confirmedBody(piastres: 1000000)), 200);
    });
    expect(
      gateway(numericAmount).ledger(callerUserId: 'owner-a'),
      throwsA(isA<LedgerReadException>()),
    );
  });

  test('a raised PostgREST message maps to that code', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'shop_not_active', 'code': 'P0001'}),
        400,
      );
    });
    final result = await gateway(client).confirm(
      callerUserId: 'owner-a',
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
      payload: const {'version': 1},
    );
    expect(result, isA<ConfirmRejected>());
    expect((result as ConfirmRejected).code, 'shop_not_active');
  });

  test('an unmapped HTTP error stays unknown', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'not_a_contract_code', 'code': 'P0001'}),
        400,
      );
    });
    final result = await gateway(client).confirm(
      callerUserId: 'owner-a',
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
      payload: const {'version': 1},
    );
    expect(result, isA<ConfirmUnknown>());
  });

  test('the request timeout includes a slow response body', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response(jsonEncode(uninitializedBody()), 200);
    });
    final api = HttpOpeningGateway(
      client: client,
      supabaseUrl: 'https://example.test',
      publishableKey: 'publishable-key',
      accessToken: () => 'access-token',
      currentUserId: () => 'owner-a',
      timeout: const Duration(milliseconds: 1),
    );
    expect(
      await api.confirm(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
        payload: const {'version': 1},
      ),
      isA<ConfirmUnknown>(),
    );
  });

  test('malformed ledger shapes are rejected', () {
    expect(
      () => parseDailyLedger(confirmedBody(piastres: maxPiastres)),
      returnsNormally,
    );
    final overflow = confirmedBody();
    ((overflow['cash'] as List).first as Map)['piastres'] =
        '9223372036854775808';
    expect(() => parseDailyLedger(overflow), throwsFormatException);
    final aggregateOverflow = confirmedBody(piastres: maxPiastres);
    final otherMethod =
        ((aggregateOverflow['cash'] as List)[1] as Map<String, Object?>);
    otherMethod['piastres'] = '1';
    otherMethod['pounds'] = '0.01';
    expect(() => parseDailyLedger(aggregateOverflow), throwsFormatException);
    final mismatch = confirmedBody(piastres: bigPiastres);
    final cash = (mismatch['cash'] as List).first as Map<String, Object?>;
    cash['pounds'] = '10000.00';
    expect(() => parseDailyLedger(mismatch), throwsFormatException);

    final unknownMethod = confirmedBody();
    final methods = unknownMethod['cash'] as List;
    (methods.first as Map)['method'] = 'cheque';
    expect(() => parseDailyLedger(unknownMethod), throwsFormatException);

    final badPair = confirmedBody();
    badPair['stock'] = [
      {
        'category': 'bullion',
        'label_ar': 'سبائك',
        'karat': 21,
        'milligrams': '1000',
        'grams': '1.000',
        'count': '1',
      },
    ];
    expect(() => parseDailyLedger(badPair), throwsFormatException);

    final expiredWrites = uninitializedBody();
    expiredWrites['entitlement_status'] = 'expired';
    expiredWrites['can_confirm'] = true;
    expect(() => parseDailyLedger(expiredWrites), throwsFormatException);

    final confirmedWritable = confirmedBody();
    confirmedWritable['can_confirm'] = true;
    expect(() => parseDailyLedger(confirmedWritable), throwsFormatException);

    final duplicate = confirmedBody();
    duplicate['scrap'] = [
      {'karat': 21, 'label_ar': 'كسر', 'milligrams': '1000', 'grams': '1.000'},
      {'karat': 21, 'label_ar': 'كسر', 'milligrams': '500', 'grams': '0.500'},
    ];
    expect(() => parseDailyLedger(duplicate), throwsFormatException);

    final badDay = confirmedBody();
    (badDay['business_day'] as Map)['business_date'] = '2026-02-31';
    expect(() => parseDailyLedger(badDay), throwsFormatException);

    final shifted = confirmedBody();
    (shifted['business_day'] as Map)['opened_at'] = '2026-09-26T00:30:00+02:00';
    expect(() => parseDailyLedger(shifted), throwsFormatException);
    final feedOffset = confirmedBody();
    ((feedOffset['feed'] as List).first as Map)['occurred_at'] =
        '2026-09-26T00:30:00-05:00';
    expect(() => parseDailyLedger(feedOffset), throwsFormatException);
  });

  test('a mismatched owner sends no status or ledger request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final api = gateway(client, currentUserId: () => 'owner-b');
    expect(
      await api.status(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      ),
      isA<StatusRejected>().having(
        (result) => result.code,
        'code',
        'session_expired',
      ),
    );
    expect(
      api.ledger(callerUserId: 'owner-a'),
      throwsA(
        isA<LedgerReadException>().having(
          (error) => error.code,
          'code',
          'session_expired',
        ),
      ),
    );
    expect(calls, 0);
  });

  test(
    'an owner switch while status is open sends no later request as the new owner',
    () async {
      var owner = 'owner-a';
      final authorizations = <String>[];
      final started = Completer<void>();
      final release = Completer<void>();
      final client = MockClient((request) async {
        authorizations.add(request.headers['authorization'] ?? '');
        if (request.url.path.endsWith('get_opening_status')) {
          if (!started.isCompleted) started.complete();
          await release.future;
          return http.Response(jsonEncode({'status': 'absent'}), 200);
        }
        return http.Response(jsonEncode(uninitializedBody()), 200);
      });
      final api = gateway(
        client,
        currentUserId: () => owner,
        accessToken: () => 'token-$owner',
      );
      final draft = (OpeningDraft.compose() as Accepted<OpeningDraft>).value;
      final store = _Memory()
        ..saved = PendingOpening(
          idempotencyKey: '22222222-2222-4222-8222-222222222222',
          payload: draft.toCanonicalJson(),
        );
      final flow = OpeningFlowCoordinator(gateway: api, store: store);
      final pending = flow.open(
        userId: 'owner-a',
        shopId: '11111111-1111-4111-8111-111111111111',
        writesAllowed: true,
      );
      await started.future;
      owner = 'owner-b';
      release.complete();
      final result = await pending;
      expect(result, isA<OpeningUnresolved>());
      expect(
        authorizations.where((header) => header.contains('token-owner-b')),
        isEmpty,
      );
      expect(authorizations, ['Bearer token-owner-a']);
      expect(store.saved?.disposition, PendingDisposition.unresolved);
    },
  );
}

class _Memory implements PendingOpeningStore {
  PendingOpening? saved;

  @override
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  }) async => saved;

  @override
  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {
    saved = pending;
  }

  @override
  Future<void> retire({required String userId, required String shopId}) async {
    saved = null;
  }
}

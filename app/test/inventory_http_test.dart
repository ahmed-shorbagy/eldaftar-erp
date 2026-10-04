import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const catalogId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const key = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

HttpOpeningGateway gateway(http.Client client) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test/',
  publishableKey: 'publishable-key',
  accessToken: () => 'access-token',
  currentUserId: () => 'owner-a',
);

void expectPostHeaders(http.Request request) {
  expect(request.headers['apikey'], 'publishable-key');
  expect(request.headers['authorization'], 'Bearer access-token');
  expect(request.headers['content-type'], contains('application/json'));
  expect(request.headers['accept'], 'application/json');
}

DayAnchor get day =>
    (DayAnchor.tryCreate(dayId, '3') as InventoryAccepted<DayAnchor>).value;

void main() {
  test('addition posts the reviewed envelope unchanged', () async {
    late Map<String, dynamic> seen;
    late http.Request request;
    final client = MockClient((incoming) async {
      request = incoming;
      seen = jsonDecode(incoming.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'ok': true,
          'operation_id': operationId,
          'replayed': false,
          'business_day_id': dayId,
          'day_version': '4',
        }),
        200,
      );
    });
    final reviewed =
        (reviewAddition(
                  day: day,
                  reason: 'إضافة',
                  lines: [
                    AdditionLine(
                      itemName: 'خاتم',
                      category: 'worked_jewelry',
                      karat: 21,
                      milligrams: BigInt.from(1830),
                      count: BigInt.one,
                    ),
                  ],
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    final command = PendingFinancialCommand(
      key: key,
      kind: reviewed.kind,
      body: reviewed.envelope(key),
    );
    final result = await gateway(
      client,
    ).postStored(callerUserId: 'owner-a', command: command);
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://example.test/rest/v1/rpc/post_inventory_addition_v1',
    );
    expectPostHeaders(request);
    expect(seen, command.body);
    expect(seen.keys, ['p_idempotency_key', 'p_payload']);
    final payload = seen['p_payload'] as Map<String, dynamic>;
    expect(payload['version'], 1);
    expect(payload['kind'], 'inventory_addition');
    expect(payload['expected_day_version'], '3');
    expect((payload['lines'] as List).single['milligrams'], '1830');
    expect((payload['lines'] as List).single['denomination_id'], isNull);
    expect(result, isA<FinancialCommitted>());
    expect((result as FinancialCommitted).operationId, operationId);
    expect(result.replayed, isFalse);
  });

  test('catalog success accepts id when operation_id is absent', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/save_trader_v1'));
      return http.Response(
        jsonEncode({'ok': true, 'id': catalogId, 'replayed': true}),
        200,
      );
    });
    final reviewed =
        (reviewTraderSave(
                  day: day,
                  displayName: 'تاجر',
                  phone: '',
                  note: '',
                  active: true,
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    final result = await gateway(client).postStored(
      callerUserId: 'owner-a',
      command: PendingFinancialCommand(
        key: key,
        kind: reviewed.kind,
        body: reviewed.envelope(key),
      ),
    );
    expect((result as FinancialCommitted).operationId, catalogId);
    expect(result.replayed, isTrue);
  });

  test(
    'a missing receipt rpc is unavailable rather than an empty page',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/list_inventory_receipts_v1'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['p_recognition_policy'], 'deferred');
        expect(body['p_owner_kind'], 'shop');
        expect(body['p_limit'], 50);
        expect(body.containsKey('p_cursor'), isFalse);
        return http.Response(
          jsonEncode({'code': 'PGRST202', 'message': 'missing'}),
          404,
        );
      });
      final page = await gateway(client).receipts(
        callerUserId: 'owner-a',
        ownerKind: 'shop',
        recognition: 'deferred',
      );
      expect(page.available, isFalse);
      expect(page.items, isNull);
    },
  );

  test(
    'receipt remainders come from the server page, not a local allocation',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ok': true,
            'next_cursor': '2026-10-04T00:00:00Z|$operationId',
            'items': [
              {
                'receipt_id': operationId,
                'operation_id': operationId,
                'lot_id': operationId,
                'product_id': catalogId,
                'product_name': 'خاتم',
                'owner_kind': 'shop',
                'trader_id': null,
                'counterparty_name': 'تاجر',
                'category': 'worked_jewelry',
                'karat': 21,
                'milligrams': '10000',
                'count': '2',
                'remaining_milligrams': '4000',
                'remaining_count': '1',
                'recognition_policy': 'deferred',
                'received_at': '2026-10-04T00:00:00Z',
                'cursor': '2026-10-04T00:00:00Z|$operationId',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final page = await gateway(client).receipts(callerUserId: 'owner-a');
      expect(page.items!.single.remainingMilligrams, BigInt.from(4000));
      expect(page.items!.single.remainingCount, BigInt.one);
      expect(page.nextCursor, '2026-10-04T00:00:00Z|$operationId');
    },
  );

  test(
    'catalog pages keep a cursor instead of pretending fifty rows are complete',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/inventory_products'));
        expect(request.url.queryParameters['limit'], '51');
        final rows = [
          for (var index = 0; index < 51; index++)
            {
              'id':
                  '12121212-1212-4121-8121-${index.toString().padLeft(12, '0')}',
              'name': 'صنف $index',
              'category_code': 'worked_jewelry',
              'karat': 21,
              'created_at':
                  '2026-10-04T00:00:${index.toString().padLeft(2, '0')}Z',
            },
        ];
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final page = await gateway(client).products(callerUserId: 'owner-a');
      expect(page.items, hasLength(50));
      expect(
        page.nextCursor,
        '2026-10-04T00:00:49Z|12121212-1212-4121-8121-${49.toString().padLeft(12, '0')}',
      );
    },
  );

  test(
    'catalog status reads inventory_catalog_requests and not opening status',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.path, isNot(contains('get_opening_status')));
        expect(request.url.queryParameters['idempotency_key'], 'eq.$key');
        return http.Response('[]', 200);
      });
      final absent = await gateway(
        client,
      ).catalogStatus(callerUserId: 'owner-a', idempotencyKey: key);
      expect(absent, isA<StatusAbsent>());
      expect(paths.single, endsWith('/inventory_catalog_requests'));
    },
  );

  test('an owner change after a committed response stays unknown', () async {
    var owner = 'owner-a';
    final client = MockClient((request) async {
      owner = 'owner-b';
      return http.Response(
        jsonEncode({
          'ok': true,
          'operation_id': operationId,
          'replayed': false,
        }),
        200,
      );
    });
    final api = HttpOpeningGateway(
      client: client,
      supabaseUrl: 'https://example.test/',
      publishableKey: 'publishable-key',
      accessToken: () => 'access-token',
      currentUserId: () => owner,
    );
    final reviewed =
        (reviewAddition(
                  day: day,
                  reason: 'إضافة',
                  lines: [
                    AdditionLine(
                      itemName: 'خاتم',
                      category: 'worked_jewelry',
                      karat: 21,
                      milligrams: BigInt.from(1000),
                      count: BigInt.one,
                    ),
                  ],
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    final result = await api.postStored(
      callerUserId: 'owner-a',
      command: PendingFinancialCommand(
        key: key,
        kind: reviewed.kind,
        body: reviewed.envelope(key),
      ),
    );
    expect(result, isA<FinancialUnknown>());
  });

  test(
    'a delayed inventory read is discarded after the owner changes',
    () async {
      var owner = 'owner-a';
      final client = MockClient((request) async {
        owner = 'owner-b';
        return http.Response(
          jsonEncode({'ok': true, 'items': [], 'next_cursor': null}),
          200,
        );
      });
      final api = HttpOpeningGateway(
        client: client,
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      expect(
        api.lots(callerUserId: 'owner-a'),
        throwsA(
          isA<InventoryReadException>().having(
            (error) => error.code,
            'code',
            'discarded',
          ),
        ),
      );
    },
  );

  test(
    'a named lot sale posts trade v2 and leaves fifo trade v1 alone',
    () async {
      late String path;
      late Map<String, dynamic> seen;
      final client = MockClient((request) async {
        path = request.url.path;
        seen = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ok': true,
            'operation_id': operationId,
            'replayed': false,
          }),
          200,
        );
      });
      final reviewed =
          (reviewExplicitLotSale(
                    day: day,
                    lot: LotSnapshot(
                      id: operationId,
                      productId: catalogId,
                      productName: 'خاتم',
                      displayName: 'خاتم',
                      category: 'worked_jewelry',
                      karat: 21,
                      stockClass: StockClass.ownedAvailable,
                      remainingMilligrams: BigInt.from(10000),
                      remainingCount: BigInt.one,
                      originalMilligrams: BigInt.from(10000),
                      originalCount: BigInt.one,
                      legacyAggregate: false,
                      denominationId: null,
                    ),
                    milligrams: BigInt.from(10000),
                    count: BigInt.one,
                    totalPiastres: BigInt.from(250000),
                    tenders: [
                      TenderDraft(
                        method: 'cash',
                        piastres: BigInt.from(250000),
                      ),
                    ],
                    description: 'بيع دفعة',
                    customerName: 'عميل',
                    customerPhone: '',
                    note: '',
                  )
                  as InventoryAccepted<ReviewedCommand>)
              .value;
      final command = PendingFinancialCommand(
        key: key,
        kind: reviewed.kind,
        body: reviewed.envelope(key),
      );
      final result = await gateway(
        client,
      ).postStored(callerUserId: 'owner-a', command: command);
      expect(path, endsWith('/post_daily_ledger_trade_v2'));
      expect(seen, command.body);
      expect((result as FinancialCommitted).operationId, operationId);
    },
  );

  test('an overlong search is rejected before any request', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      return http.Response('{}', 500);
    });
    expect(
      () => gateway(client).lots(callerUserId: 'owner-a', query: 'س' * 121),
      throwsA(
        isA<InventoryReadException>().having(
          (error) => error.code,
          'code',
          'invalid_input',
        ),
      ),
    );
    expect(called, isFalse);
  });
}

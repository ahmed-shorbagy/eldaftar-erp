import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/customers/application/customer_command_flow.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'customer_fixtures.dart';
import 'customer_statistics_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

http.Response response(Object? body, int code) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> receipt() => {
  ...customerJson(name: 'عميل جديد'),
  'ok': true,
  'replayed': false,
  'command_kind': 'customer_create',
};
HttpOpeningGateway gateway(http.Client client, {String? Function()? user}) =>
    HttpOpeningGateway(
      client: client,
      supabaseUrl: 'https://example.test',
      publishableKey: 'test-public',
      accessToken: () => 'test-token',
      currentUserId: user ?? () => 'owner',
    );
void main() {
  test(
    'timeout after commit reconciles status with exact payload identity',
    () async {
      var posts = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('post_customer_create_v1')) {
          posts++;
          throw TimeoutException('reply lost');
        }
        final p = jsonDecode(r.body) as Map;
        expect(p['p_payload'], createCustomerPayload());
        expect(p['p_customer_id'], isNull);
        return response({
          'status': 'completed',
          'command_kind': 'customer_create',
          'customer_id': customerId,
          'result': receipt(),
        }, 200);
      });
      final store = MemoryLocker();
      final saved = await CustomerCommandFlow(
        gateway(client),
        store,
      ).submit('owner', 'shop', commandKey, createCustomerPayload());
      expect(saved.receipt, isNotNull);
      expect(posts, 1);
      expect(store.stored, isNull);
    },
  );
  test('malformed committed response remains pending', () async {
    final g = gateway(
      MockClient(
        (r) async => response({
          'ok': true,
          'command_kind': 'customer_create',
          'customer_id': customerId,
        }, 200),
      ),
    );
    final result = await CustomerCommandFlow(
      g,
      MemoryLocker(),
    ).submit('owner', 'shop', commandKey, createCustomerPayload());
    expect(result.pending, isNotNull);
    expect(result.receipt, isNull);
  });
  test('changed owner discards response', () async {
    String? user = 'owner';
    final g = gateway(
      MockClient((r) async {
        user = 'other';
        return response(receipt(), 200);
      }),
      user: () => user,
    );
    final r = await g.sendCustomer(
      callerUserId: 'owner',
      command: createCustomerCommand(),
    );
    expect(r.receipt, isNull);
    expect(r.error, isNull);
  });
  test('exact phone conflict is a visible server rejection', () async {
    final r = await gateway(
      MockClient((r) async => response({'message': 'phone_conflict'}, 400)),
    ).sendCustomer(callerUserId: 'owner', command: createCustomerCommand());
    expect(r.error, 'phone_conflict');
  });
  test(
    'codec rejects version overflow, duplicate primary, mismatched state',
    () {
      expect(
        () => parseCustomer(customerJson(version: '9223372036854775808')),
        throwsFormatException,
      );
      expect(
        () => parseCustomer(
          customerJson(
            phones: [
              {
                'raw': '01011111111',
                'normalized': '+201011111111',
                'is_primary': true,
              },
              {
                'raw': '+33123456789',
                'normalized': '+33123456789',
                'is_primary': true,
              },
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => parseCustomerReceipt({
          ...receipt(),
          'record_version': '2',
        }, createCustomerCommand()),
        throwsFormatException,
      );
    },
  );
  test('customer list pagination reads exact owner query and cursor', () async {
    final g = gateway(
      MockClient((r) async {
        final p = jsonDecode(r.body) as Map;
        expect(p['p_query'], 'عميل');
        expect(p['p_sort'], 'last_operation');
        expect(p['p_cursor'], 'next');
        return response({
          'items': [
            {
              ...customerJson(last: '2026-10-13T00:30:00'),
              'statistics': statisticsJson(
                utc: '2026-10-12T21:30:00.000000Z',
                local: '2026-10-13T00:30:00',
              ),
            },
          ],
          'next_cursor': null,
        }, 200);
      }),
    );
    final p = await g.customers(
      callerUserId: 'owner',
      query: 'عميل',
      sort: 'last_operation',
      filter: 'active',
      cursor: 'next',
    );
    expect(p.items.single.lastAtShop, '2026-10-13T00:30:00');
  });
  test(
    'expired and revoked reads do not return cached successful data',
    () async {
      final g = gateway(
        MockClient((r) async => response({'message': 'forbidden'}, 400)),
      );
      expect(
        () => g.customers(
          callerUserId: 'owner',
          query: '',
          sort: 'name',
          filter: 'active',
          cursor: null,
        ),
        throwsA(isA<CustomerReadException>()),
      );
    },
  );
}

import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'correction, partial return, and exchange use exact bigint bodies',
    () async {
      final seen = <String, Object?>{};
      final gateway = HttpOpeningGateway(
        client: MockClient((request) async {
          seen[request.url.path] = jsonDecode(request.body);
          expect(request.headers['apikey'], 'publishable');
          expect(request.headers['authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({
              'ok': true,
              'operation_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'replayed': false,
            }),
            200,
          );
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'publishable',
        accessToken: () => 'token',
        currentUserId: () => 'owner-a',
      );
      const correction = {
        'version': 1,
        'kind': 'ledger_correction',
        'expected_day_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'expected_day_version': '7',
        'reason': 'نقص',
        'counted': {
          'cash': {'cash': '9223372036854775806'},
        },
      };
      expect(
        await gateway.postCorrection(
          callerUserId: 'owner-a',
          idempotencyKey: _key,
          payload: correction,
        ),
        isA<FinancialCommitted>(),
      );
      const partial = {
        'version': 1,
        'kind': 'sale_return',
        'original_operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'expected_day_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'expected_day_version': '8',
        'consideration_piastres': '3000',
        'items': [
          {'item_index': '0', 'milligrams': '2000', 'count': '1'},
        ],
      };
      expect(
        await gateway.postPartialReturn(
          callerUserId: 'owner-a',
          idempotencyKey: _key,
          payload: partial,
        ),
        isA<FinancialCommitted>(),
      );
      const exchange = {
        'version': 1,
        'kind': 'exchange',
        'return': {'kind': 'sale_return'},
        'replacement': {'kind': 'sale', 'total_piastres': '1500'},
      };
      expect(
        await gateway.postExchange(
          callerUserId: 'owner-a',
          idempotencyKey: _key,
          payload: exchange,
        ),
        isA<FinancialCommitted>(),
      );
      expect(seen['/rest/v1/rpc/post_ledger_correction_v1'], {
        'p_idempotency_key': _key,
        'p_payload': correction,
      });
      expect(seen['/rest/v1/rpc/post_linked_return_v1'], {
        'p_idempotency_key': _key,
        'p_payload': partial,
      });
      expect(seen['/rest/v1/rpc/post_exchange_v1'], {
        'p_idempotency_key': _key,
        'p_payload': exchange,
      });
      for (final kind in ['ledger_correction', 'linked_return', 'exchange']) {
        final rpc = switch (kind) {
          'ledger_correction' => 'post_ledger_correction_v1',
          'linked_return' => 'post_linked_return_v1',
          _ => 'post_exchange_v1',
        };
        final body = {
          'p_idempotency_key': _key,
          'p_payload': kind == 'ledger_correction'
              ? correction
              : kind == 'linked_return'
              ? partial
              : exchange,
        };
        expect(
          await gateway.retryPending(
            callerUserId: 'owner-a',
            command: PendingFinancialCommand(key: _key, kind: kind, body: body),
          ),
          isA<FinancialCommitted>(),
        );
        expect(seen['/rest/v1/rpc/$rpc'], body);
      }
    },
  );

  test('maps return bounds and keeps the old full-return envelope', () async {
    final gateway = HttpOpeningGateway(
      client: MockClient((request) async {
        if (request.url.path.endsWith('get_return_remainder_v1')) {
          return http.Response(
            jsonEncode({
              'operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('post_linked_return_v1')) {
          return http.Response(
            jsonEncode({'message': 'return_exceeds_original', 'code': 'P0001'}),
            400,
          );
        }
        expect(jsonDecode(request.body), {
          'p_idempotency_key': _key,
          'p_original_operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'p_note': 'كامل',
        });
        return http.Response(
          jsonEncode({'message': 'already_returned', 'code': 'P0001'}),
          400,
        );
      }),
      supabaseUrl: 'https://example.test/',
      publishableKey: 'publishable',
      accessToken: () => 'token',
      currentUserId: () => 'owner-a',
    );
    expect(
      (await gateway.remainder(
        callerUserId: 'owner-a',
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ))['operation_id'],
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    final partial = await gateway.postPartialReturn(
      callerUserId: 'owner-a',
      idempotencyKey: _key,
      payload: const {'kind': 'sale_return'},
    );
    final full = await gateway.returnOperation(
      callerUserId: 'owner-a',
      idempotencyKey: _key,
      originalOperationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      note: 'كامل',
    );
    expect((partial as FinancialRejected).code, 'return_exceeds_original');
    expect((full as FinancialRejected).code, 'already_returned');
    expect(
      await gateway.postCorrection(
        callerUserId: 'other',
        idempotencyKey: _key,
        payload: const {'kind': 'ledger_correction'},
      ),
      isA<FinancialRejected>().having(
        (result) => result.code,
        'code',
        'session_expired',
      ),
    );
  });

  test('persisted compensation commands round-trip', () async {
    const store = PendingFinancialCommands();
    const partial = PendingFinancialCommand(
      key: _key,
      kind: 'linked_return',
      body: {
        'p_idempotency_key': _key,
        'p_payload': {
          'version': 1,
          'kind': 'sale_return',
          'original_operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'consideration_piastres': '3000',
          'items': <Object?>[],
          'expected_day_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'expected_day_version': '8',
        },
      },
    );
    await store.save('owner-a', 'shop-a', partial);
    expect((await store.read('owner-a', 'shop-a'))?.body, partial.body);
  });
}

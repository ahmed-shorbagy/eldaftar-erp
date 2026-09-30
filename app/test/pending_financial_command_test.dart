import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'retains one exact retry body per owner and shop across store instances',
    () async {
      const key = '11111111-1111-4111-8111-111111111111';
      const command = PendingFinancialCommand(
        key: key,
        kind: 'sale',
        body: {
          'p_idempotency_key': key,
          'p_payload': {'kind': 'sale', 'total_piastres': '125'},
        },
      );
      const store = PendingFinancialCommands();
      await store.save('owner-a', 'shop-a', command);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'pending_financial_owner-a_shop-a',
        ),
        isNull,
      );
      final recovered = await const PendingFinancialCommands().read(
        'owner-a',
        'shop-a',
      );
      expect(recovered?.key, key);
      expect(recovered?.body, command.body);
      expect(await store.read('owner-b', 'shop-a'), isNull);
      expect(await store.read('owner-a', 'shop-b'), isNull);
      await expectLater(
        store.save(
          'owner-a',
          'shop-a',
          const PendingFinancialCommand(
            key: '22222222-2222-4222-8222-222222222222',
            kind: 'expense',
            body: {
              'p_idempotency_key': '22222222-2222-4222-8222-222222222222',
              'p_payload': {'kind': 'expense'},
            },
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        store.save(
          'owner-a',
          'shop-a',
          const PendingFinancialCommand(
            key: key,
            kind: 'sale',
            body: {
              'p_idempotency_key': key,
              'p_payload': {'kind': 'sale', 'total_piastres': '999'},
            },
          ),
        ),
        throwsStateError,
      );
      await store.clear(
        'owner-a',
        'shop-a',
        '22222222-2222-4222-8222-222222222222',
      );
      expect((await store.read('owner-a', 'shop-a'))?.key, key);
      await store.clear('owner-a', 'shop-a', key);
      expect(await store.read('owner-a', 'shop-a'), isNull);
    },
  );

  test('purchase settlement retry preserves target and tender', () async {
    const key = '33333333-3333-4333-8333-333333333333';
    const command = PendingFinancialCommand(
      key: key,
      kind: 'purchase_settlement',
      body: {
        'p_idempotency_key': key,
        'p_purchase_operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'p_tenders': [
          {'method': 'cash', 'piastres': '2000000'},
        ],
      },
    );
    const store = PendingFinancialCommands();
    await store.save('owner-a', 'shop-a', command);
    expect((await store.read('owner-a', 'shop-a'))?.body, command.body);
  });

  test('moves a valid legacy retry into protected storage once', () async {
    const key = '44444444-4444-4444-8444-444444444444';
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pending_financial_owner-a_shop-a',
      jsonEncode({
        'key': key,
        'kind': 'sale',
        'body': {
          'p_idempotency_key': key,
          'p_payload': {'kind': 'sale', 'customer_name': 'عميل تجريبي'},
        },
      }),
    );
    const store = PendingFinancialCommands();
    expect((await store.read('owner-a', 'shop-a'))?.key, key);
    expect(preferences.getString('pending_financial_owner-a_shop-a'), isNull);
    expect(
      await const FlutterSecureStorage().read(
        key: 'pending_financial_owner-a_shop-a',
      ),
      contains('عميل تجريبي'),
    );
    await preferences.setString('pending_financial_owner-a_shop-a', 'stale');
    expect((await store.read('owner-a', 'shop-a'))?.key, key);
    expect(preferences.getString('pending_financial_owner-a_shop-a'), isNull);
  });
}

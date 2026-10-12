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

  PendingFinancialCommand command(String key) => PendingFinancialCommand(
    key: key,
    kind: 'repair_intake',
    body: {
      'p_idempotency_key': key,
      'p_payload': {
        'version': 1,
        'kind': 'repair_intake',
        'customer_name': 'عميل',
        'customer_phone': '',
        'item_description': 'خاتم',
        'measured_milligrams': '1255',
        'karat': 21,
        'issue': 'لحام',
        'intake_notes': '',
        'estimated_fee_piastres': null,
      },
    },
  );

  test(
    'overlapping saves from separate store instances preserve one original repair',
    () async {
      final first = command('55555555-5555-4555-8555-555555555555');
      final second = command('66666666-6666-4666-8666-666666666666');
      Future<bool> save(PendingFinancialCommand value) =>
          const PendingFinancialCommands()
              .save('owner', 'shop', value)
              .then(
                (_) => true,
                onError: (Object error) {
                  expect(error, isA<StateError>());
                  return false;
                },
              );
      final outcomes = await Future.wait([save(first), save(second)]);
      expect(outcomes, [true, false]);
      expect(
        (await const PendingFinancialCommands().read('owner', 'shop'))!.body,
        first.body,
      );
    },
  );

  test('overlapping old cleanup cannot delete a new repair envelope', () async {
    const store = PendingFinancialCommands();
    final first = command('55555555-5555-4555-8555-555555555555');
    final second = command('66666666-6666-4666-8666-666666666666');
    await store.save('owner', 'shop', first);
    await Future.wait([
      store.clear('owner', 'shop', first.key),
      const PendingFinancialCommands().save('owner', 'shop', second),
      const PendingFinancialCommands().clear('owner', 'shop', first.key),
    ]);
    expect((await store.read('owner', 'shop'))!.body, second.body);
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

  test('repair intake retry keeps the custody envelope', () async {
    const key = '55555555-5555-4555-8555-555555555555';
    const command = PendingFinancialCommand(
      key: key,
      kind: 'repair_intake',
      body: {
        'p_idempotency_key': key,
        'p_payload': {
          'version': 1,
          'kind': 'repair_intake',
          'customer_name': 'عميل',
          'customer_phone': '',
          'item_description': 'خاتم',
          'measured_milligrams': '1255',
          'karat': 21,
          'issue': 'مفصص',
          'intake_notes': '',
          'estimated_fee_piastres': '15000',
        },
      },
    );
    const store = PendingFinancialCommands();
    await store.save('owner-a', 'shop-a', command);
    expect((await store.read('owner-a', 'shop-a'))?.body, command.body);
    await expectLater(
      store.save(
        'owner-a',
        'shop-a',
        const PendingFinancialCommand(
          key: key,
          kind: 'repair_intake',
          body: {
            'p_idempotency_key': key,
            'p_payload': {'version': 1, 'kind': 'sale'},
          },
        ),
      ),
      throwsFormatException,
    );
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

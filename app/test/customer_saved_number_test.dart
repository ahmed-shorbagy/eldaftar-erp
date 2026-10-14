import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/customers/application/customer_command_flow.dart';
import 'package:eldafttar/src/features/customers/application/customer_contract.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/customers/domain/customer_saved_number.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'customer_fixtures.dart';
import 'customer_http_test.dart' show response;
import 'customer_statistics_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

const savedOwner = 'c1111111-1111-4111-8111-111111111111';
const numberId = 'c2222222-2222-4222-8222-222222222222';
const secondNumberId = 'c3333333-3333-4333-8333-333333333333';
Map<String, Object?> savedJson(
  String state, {
  String id = numberId,
  bool declared = true,
}) => {
  'number_id': id,
  'state': state,
  'actor_user_id': declared ? savedOwner : null,
  'actor_display_name': declared ? 'مالك الاختبار' : null,
  'declared_at': declared ? '2026-10-13T09:00:00.000000Z' : null,
  'declared_at_shop': declared ? '2026-10-13T12:00:00' : null,
};
List<Object?> savedPhones(String state, {bool declared = true}) => [
  {
    'raw': '٠١٠١١١١١١١١',
    'normalized': '+201011111111',
    'is_primary': true,
    'saved_number': savedJson(state, declared: declared),
  },
  {
    'raw': '+33123456789',
    'normalized': '+33123456789',
    'is_primary': false,
    'saved_number': savedJson('unknown', id: secondNumberId, declared: false),
  },
];
Map<String, Object?> savedPayload([String state = 'saved']) => {
  'version': 1,
  'kind': 'customer_saved_number',
  'customer_id': customerId,
  'expected_version': '1',
  'number_id': numberId,
  'normalized_number': '+201011111111',
  'state': state,
};
PendingFinancialCommand savedCommand([String state = 'saved']) =>
    PendingFinancialCommand(
      key: commandKey,
      kind: 'customer_saved_number',
      body: {'p_idempotency_key': commandKey, 'p_payload': savedPayload(state)},
    );
Map<String, Object?> savedReceiptJson([String state = 'saved']) => {
  ...customerJson(version: '2', phones: savedPhones(state)),
  'ok': true,
  'replayed': false,
  'command_kind': 'customer_saved_number',
  'declaration_event_id': operationId,
};

class SavedFake extends FakeCustomers {
  SavedFake() {
    row = {
      ...statisticsCustomerJson(empty: true),
      'phones': savedPhones('unknown', declared: false),
    };
  }
  Future<void>? readHold;
  @override
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  }) async {
    if (readHold != null) await readHold;
    if (readError != null) throw CustomerReadException(readError);
    return super.customer(
      callerUserId: callerUserId,
      id: id,
      notesCursor: notesCursor,
      historyCursor: historyCursor,
      linksCursor: linksCursor,
    );
  }

  @override
  Future<CustomerTransport> sendCustomer({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    if (command.kind != 'customer_saved_number') {
      return super.sendCustomer(callerUserId: callerUserId, command: command);
    }
    sent.add(command);
    if (hold != null) await hold;
    if (rejected != null) return CustomerTransport(error: rejected);
    final state = (command.body['p_payload'] as Map)['state'] as String;
    row = {...row, 'record_version': '2', 'phones': savedPhones(state)};
    committed = parseCustomerReceipt(savedReceiptJson(state), command);
    return unknown
        ? const CustomerTransport()
        : CustomerTransport(receipt: committed);
  }
}

void main() {
  for (final state in savedNumberStates) {
    test('honest $state and exact metadata envelope/receipt', () {
      final command = savedCommand(state);
      expect(
        matchesCustomerEnvelope(command.key, command.kind, command.body),
        true,
      );
      final result = parseCustomerReceipt(savedReceiptJson(state), command);
      expect(result.customer.phones.first.saved!.state, state);
      expect(result.customer.phones.last.saved!.state, 'unknown');
      expect(result.declarationEventId, operationId);
      expect(savedNumberLabel(state), isNot(contains('تم الإرسال')));
    });
  }
  test(
    'initial unknown has no provenance; cleared unknown retains provenance',
    () {
      expect(
        parseSavedNumber(savedJson('unknown', declared: false)).actorId,
        isNull,
      );
      expect(parseSavedNumber(savedJson('unknown')).actorId, savedOwner);
      for (final state in ['saved', 'not_saved']) {
        expect(
          () => parseSavedNumber(savedJson(state, declared: false)),
          throwsFormatException,
        );
      }
    },
  );
  test('malformed declaration history fails reading before UI can cast it', () {
    final history = {
      'items': [
        {
          'event_id': commandKey,
          'event_type': 'saved_number_changed',
          'created_at': '2026-10-13T09:00:00.000000Z',
          'created_at_shop': '2026-10-13T12:00:00',
          'actor_display_name': 'مالك',
          'actor_user_id': savedOwner,
          'payload': {
            ...savedPayload(),
            'before': 'unknown',
            'record_version': '2',
          },
        },
      ],
      'next_cursor': null,
    };
    expect(parseCustomerSection(history, type: 'history').items.length, 1);
    ((history['items'] as List).first['payload'] as Map)['normalized_number'] =
        null;
    expect(
      () => parseCustomerSection(history, type: 'history'),
      throwsFormatException,
    );
  });
  test(
    'number normalization/identity and invalid states freeze rather than repurpose flags',
    () {
      for (final change in [
        {'normalized_number': '01011111111'},
        {'number_id': 'wrong'},
        {'state': true},
        {'state': 'registered'},
        {'is_vip': true},
      ]) {
        final command = savedCommand();
        expect(
          matchesCustomerEnvelope(command.key, command.kind, {
            ...command.body,
            'p_payload': {...savedPayload(), ...change},
          }),
          false,
        );
      }
    },
  );
  test('malformed declaration receipts cannot clear pending', () {
    for (final change in [
      {'state': 'not_saved'},
      {'number_id': secondNumberId},
      {'declared_at': null},
      {'actor_user_id': null},
      {'declared_at': '2026-10-13T09:00:01.000000Z'},
    ]) {
      final phones = savedPhones('saved');
      (phones.first as Map)['saved_number'] = {
        ...savedJson('saved'),
        ...change,
      };
      expect(
        () => parseCustomerReceipt({
          ...savedReceiptJson(),
          'phones': phones,
        }, savedCommand()),
        throwsFormatException,
      );
    }
    expect(
      () => parseCustomerReceipt({
        ...savedReceiptJson(),
        'declaration_event_id': null,
      }, savedCommand()),
      throwsFormatException,
    );
  });
  test(
    'foreign actor receipt stays frozen even with otherwise valid provenance',
    () async {
      final fake = SavedFake();
      final phones = savedPhones('saved');
      (phones.first as Map)['saved_number'] = {
        ...savedJson('saved'),
        'actor_user_id': secondNumberId,
      };
      fake.statusOverride = CustomerTransport(
        receipt: parseCustomerReceipt({
          ...savedReceiptJson(),
          'phones': phones,
        }, savedCommand()),
      );
      final locker = MemoryLocker()..stored = savedCommand();
      final result = await CustomerCommandFlow(
        fake,
        locker,
      ).reconcile(savedOwner, 'shop', savedCommand());
      expect(result.pending, isNotNull);
      expect(locker.stored, isNotNull);
    },
  );
  test(
    'timeout after commit reconciles exact new status contract; no financial or invoice RPC',
    () async {
      final paths = <String>[];
      final g = HttpOpeningGateway(
        client: MockClient((r) async {
          paths.add(r.url.path);
          final p = jsonDecode(r.body) as Map;
          expect(p['p_payload'], savedPayload());
          if (r.url.path.endsWith('post_customer_saved_number_v1')) {
            throw TimeoutException('lost');
          }
          expect(r.url.path.endsWith('get_customer_command_status_v2'), true);
          expect(p['p_customer_id'], customerId);
          return response({
            'status': 'completed',
            'command_kind': 'customer_saved_number',
            'customer_id': customerId,
            'result': savedReceiptJson(),
          }, 200);
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'test-public',
        accessToken: () => 'token',
        currentUserId: () => savedOwner,
      );
      final store = MemoryLocker();
      final result = await CustomerCommandFlow(
        g,
        store,
      ).submit(savedOwner, 'shop', commandKey, savedPayload());
      expect(result.receipt, isNotNull);
      expect(store.stored, isNull);
      expect(paths.length, 2);
    },
  );
  test(
    'unknown restart is exact and cannot replace another pending command',
    () async {
      final g = SavedFake()..unknown = true;
      final store = MemoryLocker();
      final pending = await CustomerCommandFlow(
        g,
        store,
      ).submit(savedOwner, 'shop', commandKey, savedPayload());
      expect(pending.pending, isNotNull);
      final restored = PendingFinancialCommand(
        key: store.stored!.key,
        kind: store.stored!.kind,
        body: Map<String, Object?>.from(
          jsonDecode(jsonEncode(store.stored!.body)) as Map,
        ),
      );
      final retry = await CustomerCommandFlow(
        g,
        store,
      ).reconcile(savedOwner, 'shop', restored);
      expect(retry.pending!.body, savedCommand().body);
      expect(g.sent.length, 1);
      g.unknown = false;
      final done = await CustomerCommandFlow(
        g,
        store,
      ).reconcile(savedOwner, 'shop', restored);
      expect(done.receipt, isNotNull);
      expect(store.stored, isNull);
      store.stored = createCustomerCommand();
      final blocked = await CustomerCommandFlow(
        g,
        store,
      ).submit(savedOwner, 'shop', numberId, savedPayload());
      expect(blocked.error, 'other_pending');
      expect(store.stored!.kind, 'customer_create');
    },
  );
  test(
    'v3 rejects missing status rather than inventing not saved; v1 remains readable',
    () {
      final legacy = customerJson(
        phones: [
          {
            'raw': '01011111111',
            'normalized': '+201011111111',
            'is_primary': true,
          },
        ],
      );
      expect(parseCustomer(legacy).phones.single.saved, isNull);
      expect(
        () => parseCustomer(legacy, requireSavedNumbers: true),
        throwsFormatException,
      );
      expect(savedNumberLabel(null), 'حالة حفظ الرقم غير متاحة');
    },
  );
}

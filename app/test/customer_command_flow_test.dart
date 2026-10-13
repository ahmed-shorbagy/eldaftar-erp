import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/application/customer_command_flow.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'customer_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

void main() {
  test(
    'unknown outcome survives restore and reconciles original request without repost',
    () async {
      final g = FakeCustomers()..unknown = true;
      final store = MemoryLocker();
      final flow = CustomerCommandFlow(g, store);
      final first = await flow.submit(
        'owner',
        'shop',
        commandKey,
        createCustomerPayload(),
      );
      expect(first.pending, isNotNull);
      expect(store.stored!.body, createCustomerCommand().body);
      g.statusOverride = CustomerTransport(receipt: g.committed);
      final restored = await CustomerCommandFlow(
        g,
        store,
      ).reconcile('owner', 'shop', store.stored!, retry: true);
      expect(restored.receipt!.customer.name, 'عميل جديد');
      expect(g.sent, hasLength(1));
      expect(store.stored, isNull);
    },
  );
  test(
    'wrong kind or customer status never clears original envelope',
    () async {
      final g = FakeCustomers()..unknown = true;
      final store = MemoryLocker();
      final flow = CustomerCommandFlow(g, store);
      await flow.submit('owner', 'shop', commandKey, createCustomerPayload());
      g.statusOverride = CustomerTransport(
        receipt: CustomerReceipt(
          'customer_archive',
          parseCustomer(customerJson()),
        ),
      );
      final r = await flow.reconcile(
        'owner',
        'shop',
        store.stored!,
        retry: true,
      );
      expect(r.pending, isNotNull);
      expect(g.sent, hasLength(1));
      expect(store.stored, isNotNull);
    },
  );
  test('confirmed save with failed cleanup blocks new requests', () async {
    final g = FakeCustomers();
    final store = MemoryLocker()..clearError = StateError('disk');
    final r = await CustomerCommandFlow(
      g,
      store,
    ).submit('owner', 'shop', commandKey, createCustomerPayload());
    expect(r.receipt, isNotNull);
    expect(r.pending, isNotNull);
    expect(r.error, 'storage');
  });
  test('local persist failure sends no request', () async {
    final g = FakeCustomers();
    final store = MemoryLocker()..saveError = StateError('disk');
    final r = await CustomerCommandFlow(
      g,
      store,
    ).submit('owner', 'shop', commandKey, createCustomerPayload());
    expect(r.error, 'other_pending');
    expect(g.sent, isEmpty);
  });
  test('definitive rejection clears request and reports failure', () async {
    final g = FakeCustomers()..rejected = 'phone_conflict';
    final store = MemoryLocker();
    final r = await CustomerCommandFlow(
      g,
      store,
    ).submit('owner', 'shop', commandKey, createCustomerPayload());
    expect(r.receipt, isNull);
    expect(r.error, 'phone_conflict');
    expect(store.stored, isNull);
  });
  test(
    'absence after restart retries original key and frozen payload',
    () async {
      final g = FakeCustomers()
        ..statusOverride = const CustomerTransport(absent: true);
      final store = MemoryLocker()..stored = createCustomerCommand();
      final r = await CustomerCommandFlow(
        g,
        store,
      ).reconcile('owner', 'shop', store.stored!, retry: true);
      expect(r.receipt, isNotNull);
      expect(g.sent.single.key, commandKey);
      expect(g.sent.single.body, createCustomerCommand().body);
      expect(store.stored, isNull);
    },
  );
}

// Owner feedback of 2026-11-17 (ADR 0049): no opening-balances form. A new
// shop's daily ledger opens directly. The owner's app confirms zero opening
// balances by itself; cash and gold are entered later from the inventory page.
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_ledger_flow_test.dart' as fixtures;

const _committed = ConfirmCommitted(
  operationId: '33333333-3333-4333-8333-333333333333',
  businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  businessDate: '2026-09-26',
  replayed: false,
);

DailyLedgerController controllerFor(
  fixtures.ScriptGateway gateway,
  fixtures.MemoryStore store, {
  bool canOpen = true,
  bool shopIsActive = true,
}) {
  final controller = DailyLedgerController(
    gateway: gateway,
    store: store,
    userId: fixtures.userId,
    shopId: fixtures.shopId,
    shopIsActive: shopIsActive,
    canOpen: canOpen,
    newKey: () => '55555555-5555-4555-8555-555555555555',
  );
  addTearDown(controller.dispose);
  return controller;
}

DailyLedgerView staffUninitialized() => const DailyLedgerView(
  state: 'uninitialized',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: null,
  cash: [],
  stock: [],
  scrap: [],
  feed: [],
);

void main() {
  test('the owner of a new shop lands on the open ledger', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    );
    gateway.confirmHook = () {
      gateway.ledgerView = fixtures.sampleLedger();
      return _committed;
    };
    final store = fixtures.MemoryStore();
    final controller = controllerFor(gateway, store);

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.phase, LedgerPhase.confirmed);
    expect(controller.ledger!.isConfirmed, isTrue);
    expect(gateway.confirmCalls, 1);
    expect(store.saved, isNull);
  });

  test('what is confirmed is exactly a zero opening', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    );
    gateway.confirmHook = () {
      gateway.ledgerView = fixtures.sampleLedger();
      return _committed;
    };
    final controller = controllerFor(gateway, fixtures.MemoryStore());

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.payloads.single, {
      'version': 1,
      'cash': {
        'cash': '0',
        'instant_transfer': '0',
        'wallet': '0',
        'card': '0',
      },
      'stock': <Object?>[],
      'scrap': <Object?>[],
    });
  });

  test('a shop that is already open is not opened again', () async {
    final gateway = fixtures.ScriptGateway(ledgerView: fixtures.sampleLedger());
    final controller = controllerFor(gateway, fixtures.MemoryStore());

    await controller.start();
    await controller.refresh();

    expect(controller.phase, LedgerPhase.confirmed);
    expect(gateway.confirmCalls, 0);
  });

  test('staff never open the shop and wait for the owner', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    );
    final controller = controllerFor(
      gateway,
      fixtures.MemoryStore(),
      canOpen: false,
    );

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.confirmCalls, 0);
    expect(controller.phase, LedgerPhase.notOpened);
    expect(controller.canRetryOpen, isFalse);
    await controller.retryOpen();
    expect(gateway.confirmCalls, 0);
  });

  test('a reader the server does not let open posts nothing', () async {
    final gateway = fixtures.ScriptGateway(ledgerView: staffUninitialized());
    final controller = controllerFor(gateway, fixtures.MemoryStore());

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.confirmCalls, 0);
    expect(controller.phase, LedgerPhase.expiredEmpty);
  });

  test('an expired shop is not opened', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    );
    final controller = controllerFor(
      gateway,
      fixtures.MemoryStore(),
      shopIsActive: false,
    );

    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.confirmCalls, 0);
    expect(controller.phase, LedgerPhase.expiredEmpty);
  });

  test('a failed opening is tried once, then waits for the owner', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    )..confirmResult = const ConfirmRejected('shop_busy');
    final controller = controllerFor(gateway, fixtures.MemoryStore());

    await controller.start();
    await Future<void>.delayed(Duration.zero);
    final afterFirst = gateway.confirmCalls;
    expect(afterFirst, greaterThanOrEqualTo(1));
    expect(controller.phase, isNot(LedgerPhase.confirmed));
    expect(controller.phase, isNot(LedgerPhase.loading));
  });

  test('a lost reply is reconciled on the same key and opens once', () async {
    final gateway = fixtures.ScriptGateway(
      ledgerView: fixtures.uninitializedLedger(),
    )..confirmThrows = true;
    final store = fixtures.MemoryStore();
    final controller = controllerFor(gateway, store);

    await controller.start();
    await Future<void>.delayed(Duration.zero);
    // The reply was lost: the attempt is kept and shown as pending.
    expect(controller.phase, LedgerPhase.pending);
    expect(store.saved?.disposition, PendingDisposition.unresolved);
    final key = store.saved!.idempotencyKey;

    gateway
      ..confirmThrows = false
      ..statuses = const [StatusAbsent()]
      ..confirmHook = () {
        gateway.ledgerView = fixtures.sampleLedger();
        return _committed;
      };
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(controller.phase, LedgerPhase.confirmed);
    expect(gateway.keys.toSet(), {key}, reason: 'one opening, one key');
    expect(store.saved, isNull);
  });
}

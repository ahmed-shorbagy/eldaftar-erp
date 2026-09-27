import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_flow.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:flutter_test/flutter_test.dart';

const userId = 'user-1';
const shopId = '11111111-1111-4111-8111-111111111111';

DailyLedgerView uninitializedLedger() => const DailyLedgerView(
  state: 'uninitialized',
  entitlementStatus: 'active',
  canConfirm: true,
  businessDay: null,
  cash: [],
  stock: [],
  scrap: [],
  feed: [],
);

DailyLedgerView sampleLedger() => const DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: LedgerBusinessDay(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    businessDate: '2026-09-26',
    openedAt: '2026-09-26T00:30:00Z',
  ),
  cash: [
    LedgerCashLine(
      method: 'cash',
      labelAr: 'نقدي',
      piastres: '1000000',
      pounds: '10000.00',
    ),
    LedgerCashLine(
      method: 'instant_transfer',
      labelAr: 'انستا',
      piastres: '0',
      pounds: '0.00',
    ),
    LedgerCashLine(
      method: 'wallet',
      labelAr: 'محفظة',
      piastres: '0',
      pounds: '0.00',
    ),
    LedgerCashLine(
      method: 'card',
      labelAr: 'فيزا',
      piastres: '0',
      pounds: '0.00',
    ),
  ],
  stock: [],
  scrap: [],
  feed: [
    LedgerFeedLine(
      kind: 'opening_balances_confirmed',
      labelAr: 'رصيد افتتاحي',
      operationId: '33333333-3333-4333-8333-333333333333',
      actorDisplayName: 'منى',
      occurredAt: '2026-09-26T00:30:00Z',
      occurredAtCairo: '2026-09-26T03:30:00',
    ),
  ],
);

class MemoryStore implements PendingOpeningStore {
  PendingOpening? saved;
  bool failWrites = false;

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
    if (failWrites) throw StateError('disk');
    saved = pending;
  }

  @override
  Future<void> retire({required String userId, required String shopId}) async {
    saved = null;
  }
}

class ScriptGateway implements OpeningGateway {
  ScriptGateway({this.ledgerView});

  int confirmCalls = 0;
  int statusCalls = 0;
  int ledgerCalls = 0;
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];
  ConfirmResult confirmResult = const ConfirmUnknown();
  FutureOr<ConfirmResult> Function()? confirmHook;
  List<StatusResult> statuses = const [StatusUnknown()];
  DailyLedgerView? ledgerView;
  bool ledgerThrows = false;
  bool statusThrows = false;
  bool confirmThrows = false;
  Completer<void>? statusGate;

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    if (confirmThrows) throw StateError('socket');
    confirmCalls++;
    keys.add(idempotencyKey);
    payloads.add(payload);
    final hook = confirmHook;
    if (hook != null) return await hook();
    return confirmResult;
  }

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    if (statusThrows) throw StateError('socket');
    final gate = statusGate;
    if (gate != null) await gate.future;
    final index = statusCalls;
    statusCalls++;
    if (index >= statuses.length) return statuses.last;
    return statuses[index];
  }

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    ledgerCalls++;
    if (ledgerThrows || ledgerView == null) {
      throw const LedgerReadException();
    }
    return ledgerView!;
  }
}

OpeningDraft zeroDraft() {
  final result = OpeningDraft.compose();
  return (result as Accepted<OpeningDraft>).value;
}

void main() {
  test('unknown outcome keeps one pending key', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmUnknown()
      ..statuses = const [StatusUnknown()];
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '11111111-1111-4111-8111-111111111111',
    );
    final result = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(result, isA<OpeningUnresolved>());
    expect(store.saved?.idempotencyKey, '11111111-1111-4111-8111-111111111111');
    expect(gateway.confirmCalls, 1);
  });

  test('completed status loads the ledger and does not post again', () async {
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: zeroDraft().toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: sampleLedger())
      ..statuses = const [
        StatusCompleted('33333333-3333-4333-8333-333333333333'),
      ];
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningReady>());
    expect(gateway.confirmCalls, 0);
    expect(gateway.ledgerCalls, 1);
  });

  test('absent status retries the same key and payload', () async {
    final draft = zeroDraft();
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: draft.toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger())
      ..statuses = const [StatusAbsent()];
    gateway.confirmHook = () {
      gateway.ledgerView = sampleLedger();
      return const ConfirmCommitted(
        operationId: '33333333-3333-4333-8333-333333333333',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      );
    };
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningReady>());
    expect(gateway.confirmCalls, 1);
    expect(gateway.keys.single, '22222222-2222-4222-8222-222222222222');
    expect(gateway.payloads.single, draft.toCanonicalJson());
  });

  test('validation failure keeps the key for a corrected draft', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmRejected('invalid_input');
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '44444444-4444-4444-8444-444444444444',
    );
    final first = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(first, isA<OpeningRejectedDraft>());
    expect(store.saved?.idempotencyKey, '44444444-4444-4444-8444-444444444444');
    final parsed = Piastres.parseWire('125') as Accepted<Piastres>;
    final corrected = OpeningDraft.compose(
      cash: {CashMethod.cash: parsed.value},
    );
    final second = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: (corrected as Accepted<OpeningDraft>).value,
      writesAllowed: true,
    );
    expect(second, isA<OpeningRejectedDraft>());
    expect(gateway.keys, [
      '44444444-4444-4444-8444-444444444444',
      '44444444-4444-4444-8444-444444444444',
    ]);
    expect(gateway.payloads[1]['cash'], isNot(gateway.payloads[0]['cash']));
  });

  test('storage failure does not send', () async {
    final store = MemoryStore()..failWrites = true;
    final gateway = ScriptGateway();
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(result, isA<OpeningStorageFailed>());
    expect(gateway.confirmCalls, 0);
    expect(store.saved, isNull);
  });

  test('a second submit while in flight is one call', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway(ledgerView: sampleLedger());
    final release = Completer<ConfirmResult>();
    final started = Completer<void>();
    gateway.confirmHook = () {
      if (!started.isCompleted) started.complete();
      return release.future;
    };
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '88888888-8888-4888-8888-888888888888',
    );
    final first = flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    await started.future;
    final second = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(second, isA<OpeningIgnored>());
    release.complete(
      const ConfirmCommitted(
        operationId: '33333333-3333-4333-8333-333333333333',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      ),
    );
    expect(await first, isA<OpeningReady>());
    expect(gateway.confirmCalls, 1);
  });

  test('a confirmed post with a failed refresh is not a failed post', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()
      ..ledgerThrows = true
      ..confirmResult = const ConfirmCommitted(
        operationId: 'op-9',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      );
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '55555555-5555-4555-8555-555555555555',
    );
    final result = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(result, isA<OpeningRefreshFailed>());
    expect((result as OpeningRefreshFailed).operationId, 'op-9');
    expect(result, isNot(isA<OpeningFailed>()));
  });

  test(
    'session expiry keeps the key and the next sign-in resolves it',
    () async {
      final store = MemoryStore();
      final gateway = ScriptGateway(ledgerView: sampleLedger())
        ..confirmResult = const ConfirmUnknown()
        ..statuses = const [
          StatusRejected('session_expired'),
          StatusCompleted('33333333-3333-4333-8333-333333333333'),
        ];
      final flow = OpeningFlowCoordinator(
        gateway: gateway,
        store: store,
        newKey: () => '66666666-6666-4666-8666-666666666666',
      );
      final pending = await flow.confirm(
        userId: userId,
        shopId: shopId,
        draft: zeroDraft(),
        writesAllowed: true,
      );
      expect(pending, isA<OpeningUnresolved>());
      expect(
        store.saved?.idempotencyKey,
        '66666666-6666-4666-8666-666666666666',
      );
      final next = OpeningFlowCoordinator(gateway: gateway, store: store);
      final resolved = await next.open(
        userId: userId,
        shopId: shopId,
        writesAllowed: true,
      );
      expect(resolved, isA<OpeningReady>());
      expect(gateway.confirmCalls, 1);
      expect(store.saved, isNull);
    },
  );

  test('a new use case reloads the retained key', () async {
    final draft = zeroDraft();
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '77777777-7777-4777-8777-777777777777',
        payload: draft.toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger())
      ..statuses = const [StatusAbsent()];
    gateway.confirmHook = () {
      gateway.ledgerView = sampleLedger();
      return const ConfirmCommitted(
        operationId: '33333333-3333-4333-8333-333333333333',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: true,
      );
    };
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    await flow.open(userId: userId, shopId: shopId, writesAllowed: true);
    expect(gateway.keys.single, '77777777-7777-4777-8777-777777777777');
  });

  test('a corrupt pending record does not send', () async {
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: 'not-a-uuid',
        payload: zeroDraft().toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger());
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningStorageFailed>());
    expect(gateway.confirmCalls, 0);
    expect(gateway.statusCalls, 0);
  });

  test('an unknown payload stays frozen after restart', () async {
    final draft = zeroDraft();
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: draft.toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger())
      ..statuses = const [StatusUnknown()];
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningUnresolved>());
    expect(store.saved?.payload, draft.toCanonicalJson());
    expect(gateway.confirmCalls, 0);
    final again = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: draft,
      writesAllowed: true,
    );
    expect(again, isA<OpeningUnresolved>());
    expect(
      (again as OpeningUnresolved).idempotencyKey,
      '22222222-2222-4222-8222-222222222222',
    );
    expect(store.saved?.payload, draft.toCanonicalJson());
    expect(gateway.confirmCalls, 0);
  });

  test('an expired shop does not confirm a stored absent attempt', () async {
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: zeroDraft().toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger())
      ..statuses = const [StatusAbsent()];
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: false,
    );
    expect(result, isA<OpeningUnresolved>());
    expect(gateway.confirmCalls, 0);
    expect(gateway.statusCalls, 1);
    expect(store.saved, isNotNull);
  });

  test('a thrown status keeps the pending attempt', () async {
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: zeroDraft().toCanonicalJson(),
      );
    final gateway = ScriptGateway()..statusThrows = true;
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningUnresolved>());
    expect(gateway.confirmCalls, 0);
    expect(store.saved?.disposition, PendingDisposition.unresolved);
  });

  test('a thrown confirm keeps the frozen payload', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()..confirmThrows = true;
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '11111111-1111-4111-8111-111111111111',
    );
    final result = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(result, isA<OpeningUnresolved>());
    expect(store.saved?.payload, zeroDraft().toCanonicalJson());
    expect(store.saved?.disposition, PendingDisposition.unresolved);
  });

  test('completed status on an uninitialized ledger is not success', () async {
    final store = MemoryStore()
      ..saved = PendingOpening(
        idempotencyKey: '22222222-2222-4222-8222-222222222222',
        payload: zeroDraft().toCanonicalJson(),
      );
    final gateway = ScriptGateway(ledgerView: uninitializedLedger())
      ..statuses = const [
        StatusCompleted('33333333-3333-4333-8333-333333333333'),
      ];
    final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
    final result = await flow.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(result, isA<OpeningRefreshFailed>());
    expect(gateway.confirmCalls, 0);
    expect(store.saved?.disposition, PendingDisposition.acknowledged);
  });

  test('a validation rejection reopens on the same key', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()
      ..confirmResult = const ConfirmRejected('overflow');
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => '44444444-4444-4444-8444-444444444444',
    );
    await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    final restarted = OpeningFlowCoordinator(gateway: gateway, store: store);
    final opened = await restarted.open(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );
    expect(opened, isA<OpeningRejectedDraft>());
    final rejected = opened as OpeningRejectedDraft;
    expect(rejected.idempotencyKey, '44444444-4444-4444-8444-444444444444');
    expect(rejected.code, 'overflow');
    expect(gateway.confirmCalls, 1);
  });

  test(
    'expiry while absent status is in flight does not retry the write',
    () async {
      final store = MemoryStore()
        ..saved = PendingOpening(
          idempotencyKey: '22222222-2222-4222-8222-222222222222',
          payload: zeroDraft().toCanonicalJson(),
        );
      final release = Completer<void>();
      final gateway = ScriptGateway(ledgerView: uninitializedLedger())
        ..statuses = const [StatusAbsent()]
        ..statusGate = release;
      var allowWrite = true;
      final flow = OpeningFlowCoordinator(
        gateway: gateway,
        store: store,
        writesStillAllowed: () => allowWrite,
      );
      final pending = flow.open(
        userId: userId,
        shopId: shopId,
        writesAllowed: true,
      );
      await Future<void>.delayed(Duration.zero);
      allowWrite = false;
      release.complete();
      final result = await pending;
      expect(result, isA<OpeningUnresolved>());
      expect(gateway.confirmCalls, 0);
      expect(store.saved?.disposition, PendingDisposition.unresolved);
    },
  );

  test(
    'dispose while absent status is in flight does not retry the write',
    () async {
      final store = MemoryStore()
        ..saved = PendingOpening(
          idempotencyKey: '22222222-2222-4222-8222-222222222222',
          payload: zeroDraft().toCanonicalJson(),
        );
      final release = Completer<void>();
      final gateway = ScriptGateway(ledgerView: uninitializedLedger())
        ..statuses = const [StatusAbsent()]
        ..statusGate = release;
      var live = true;
      final flow = OpeningFlowCoordinator(
        gateway: gateway,
        store: store,
        sessionLive: () => live,
      );
      final pending = flow.open(
        userId: userId,
        shopId: shopId,
        writesAllowed: true,
      );
      await Future<void>.delayed(Duration.zero);
      live = false;
      release.complete();
      final result = await pending;
      expect(result, isA<OpeningUnresolved>());
      expect(gateway.confirmCalls, 0);
      expect(store.saved?.disposition, PendingDisposition.unresolved);
    },
  );
}

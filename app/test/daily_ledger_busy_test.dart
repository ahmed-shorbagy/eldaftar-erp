import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_flow.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_ledger_flow_test.dart' as fixtures;

class RefreshGateway extends fixtures.ScriptGateway {
  RefreshGateway() : super(ledgerView: fixtures.uninitializedLedger());

  Completer<DailyLedgerView>? deferredRead;

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) {
    final deferred = deferredRead;
    return deferred == null
        ? super.ledger(callerUserId: callerUserId)
        : deferred.future;
  }
}

class DeniedLedgerGateway extends fixtures.ScriptGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    throw const LedgerReadException('forbidden');
  }
}

void main() {
  test(
    'access loss after an already-confirmed response stays visible',
    () async {
      final gateway = DeniedLedgerGateway()
        ..confirmResult = const ConfirmRejected('opening_already_confirmed');
      final store = fixtures.MemoryStore();
      final flow = OpeningFlowCoordinator(gateway: gateway, store: store);
      final result = await flow.confirm(
        userId: fixtures.userId,
        shopId: fixtures.shopId,
        draft: fixtures.zeroDraft(),
        writesAllowed: true,
      );
      expect(result, isA<OpeningUnresolved>());
      expect((result as OpeningUnresolved).noticeCode, 'forbidden');
      expect(store.saved, isNotNull);
      expect(gateway.confirmCalls, 1);
    },
  );

  test('a refresh while the ledger is opening sends one confirm', () async {
    final gateway = RefreshGateway();
    final opened = Completer<ConfirmResult>();
    gateway.confirmHook = () => opened.future;
    final controller = DailyLedgerController(
      gateway: gateway,
      store: fixtures.MemoryStore(),
      userId: fixtures.userId,
      shopId: fixtures.shopId,
      shopIsActive: true,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.phase, LedgerPhase.loading);
    expect(gateway.confirmCalls, 1);

    // A sync tick arrives before the server answers.
    await controller.refresh();
    expect(gateway.confirmCalls, 1);

    gateway.ledgerView = fixtures.sampleLedger();
    opened.complete(
      const ConfirmCommitted(
        operationId: '33333333-3333-4333-8333-333333333333',
        businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        businessDate: '2026-09-26',
        replayed: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.confirmCalls, 1);
    expect(controller.phase, LedgerPhase.confirmed);
  });
}

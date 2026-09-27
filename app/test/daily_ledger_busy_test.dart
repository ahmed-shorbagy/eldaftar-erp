import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_flow.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
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

  test(
    'confirm during refresh retains review and can submit afterward',
    () async {
      final gateway = RefreshGateway();
      final controller = DailyLedgerController(
        gateway: gateway,
        store: fixtures.MemoryStore(),
        userId: fixtures.userId,
        shopId: fixtures.shopId,
        shopIsActive: true,
      );
      addTearDown(controller.dispose);
      await controller.start();
      controller.cash[CashMethod.cash]!.text = '1.25';
      controller.reviewEntered();
      expect(controller.phase, LedgerPhase.review);

      gateway.deferredRead = Completer<DailyLedgerView>();
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await controller.confirmReview();
      expect(gateway.confirmCalls, 0);
      expect(controller.phase, LedgerPhase.review);
      expect(controller.fieldsLocked, isFalse);

      gateway.deferredRead!.complete(fixtures.uninitializedLedger());
      await refresh;
      gateway.deferredRead = null;
      expect(controller.cash[CashMethod.cash]!.text, '1.25');
      expect(controller.reviewDraft!.cash[CashMethod.cash].wire, '125');

      gateway.confirmHook = () {
        gateway.ledgerView = fixtures.sampleLedger();
        return const ConfirmCommitted(
          operationId: '33333333-3333-4333-8333-333333333333',
          businessDayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          businessDate: '2026-09-26',
          replayed: false,
        );
      };
      await controller.confirmReview();
      expect(gateway.confirmCalls, 1);
      expect(controller.phase, LedgerPhase.confirmed);
    },
  );
}

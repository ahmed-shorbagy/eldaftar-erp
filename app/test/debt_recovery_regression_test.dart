import 'dart:async';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_codec.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'debt_widget_test.dart' as fixture;
import 'repair_command_flow_test.dart' show MemoryLocker;

Map<String, Object?> resultWire() => {
  'ok': true,
  'replayed': false,
  'command_kind': 'debt_declare',
  'source_kind': 'standalone',
  'source_id': fixture.sourceId,
  'display_status': 'open',
  'original_amount': '1000',
  'settled_amount': '0',
  'cancelled_amount': '0',
  'remaining_amount': '1000',
  'ledger_effect': 'none',
  'operation_id': null,
  'cash_piastres': '0',
  'gold_milligrams': '0',
  'gold_count': '0',
  'custody_milligrams': '0',
  'saleable_stock_milligrams': '0',
};

class Gateway extends fixture.FakeDebts {
  DebtRpcResult reply = const DebtRpcUnknown();
  DebtRemoteStatus status = const DebtRemoteUnknown();
  PendingFinancialCommand? sent;
  int details = 0;
  @override
  Future<DebtRpcResult> submitCommand({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    submits++;
    sent = command;
    return reply;
  }

  @override
  Future<DebtRemoteStatus> readCommandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => status;
  @override
  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  }) async {
    details++;
    return fixture.sampleDetail();
  }
}

class BrokenLocker extends MemoryLocker {
  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      throw StateError('disk_read_failure');
}

class DelayedGateway extends Gateway {
  final old = Completer<DebtPage>();
  @override
  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) => callerUserId == fixture.userId
      ? old.future
      : Future.value(
          const DebtPage(items: [], nextCursor: null, timeZone: 'Africa/Cairo'),
        );
}

Future<void> open(
  WidgetTester tester,
  Gateway gateway,
  MemoryLocker locker, {
  Listenable? ticks,
  String user = fixture.userId,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    fixture.host(
      DebtScreen(
        gateway: gateway,
        store: locker,
        userId: user,
        shopId: fixture.shopId,
        readOnly: false,
        syncTicks: ticks,
        newKey: () => fixture.key,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> declareReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('debt-open-declare')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('debt-party')), 'طرف جديد');
  await tester.enterText(find.byKey(const Key('debt-reason')), 'دين تاريخي');
  await tester.enterText(find.byKey(const Key('debt-amount')), '10');
  await tester.ensureVisible(find.byKey(const Key('debt-submit')));
  await tester.tap(find.byKey(const Key('debt-submit')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });
  test('status validates nested result and all header identities', () {
    final valid = resultWire();
    for (final bad in [
      {...valid, 'original_amount': 'broken'},
      {...valid, 'remaining_amount': '999'},
      {...valid, 'source_kind': 'gold_obligation'},
      {...valid, 'command_kind': 'debt_settle'},
      {...valid, 'custody_milligrams': '1'},
      {...valid, 'ledger_effect': 'move'},
    ]) {
      expect(
        () => parseDebtCommandStatus({
          'status': 'completed',
          'command_kind': 'debt_declare',
          'source_kind': 'standalone',
          'source_id': fixture.sourceId,
          'result': bad,
        }),
        throwsFormatException,
      );
    }
    final parsed = parseDebtCommandStatus({
      'status': 'completed',
      'command_kind': 'debt_declare',
      'source_kind': 'standalone',
      'source_id': fixture.sourceId,
      'result': valid,
    });
    expect(
      (parsed as DebtRemoteCompleted).committed.original,
      BigInt.from(1000),
    );
  });
  testWidgets(
    'unknown declaration freezes all new writes then reconciles original key',
    (tester) async {
      final gateway = Gateway(), locker = MemoryLocker();
      await open(tester, gateway, locker);
      await declareReview(tester);
      await tester.ensureVisible(find.byKey(const Key('debt-confirm')));
      await tester.tap(find.byKey(const Key('debt-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('debt-pending')), findsOneWidget);
      expect(find.byKey(const Key('debt-confirm')), findsNothing);
      expect(find.byKey(const Key('debt-open-declare')), findsNothing);
      expect(gateway.submits, 1);
      final original = locker.stored!;
      gateway.status = DebtRemoteCompleted(
        committed: parseDebtCommand(resultWire()),
      );
      await tester.ensureVisible(find.byKey(const Key('debt-retry')));
      await tester.tap(find.byKey(const Key('debt-retry')));
      await tester.pumpAndSettle();
      expect(gateway.submits, 1);
      expect(gateway.sent!.body, original.body);
      expect(locker.stored, isNull);
      expect(find.byKey(const Key('debt-success')), findsOneWidget);
    },
  );
  testWidgets('other feature pending and failed local read block debt writes', (
    tester,
  ) async {
    final gateway = Gateway();
    final locker = MemoryLocker()
      ..stored = const PendingFinancialCommand(
        key: fixture.key,
        kind: 'repair_intake',
        body: {},
      );
    await open(tester, gateway, locker);
    expect(find.byKey(const Key('debt-other-pending')), findsOneWidget);
    expect(find.byKey(const Key('debt-open-declare')), findsNothing);
    expect(locker.stored, isNotNull);
    await open(tester, gateway, BrokenLocker());
    expect(find.byKey(const Key('debt-error')), findsOneWidget);
    expect(find.byKey(const Key('debt-reload')), findsOneWidget);
    expect(find.byKey(const Key('debt-open-declare')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('an old identity read is discarded after account change', (
    tester,
  ) async {
    final gateway = DelayedGateway(), locker = MemoryLocker();
    await open(tester, gateway, locker, settle: false);
    await open(tester, gateway, locker, user: 'new-owner');
    gateway.old.complete(
      DebtPage(
        items: [fixture.sampleSummary()],
        nextCursor: null,
        timeZone: 'Africa/Cairo',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('طرف تاريخي'), findsNothing);
    expect(find.text('لا توجد ديون في هذا العرض.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('open detail re-reads on sync and stale review offers recovery', (
    tester,
  ) async {
    final ticks = ChangeNotifier(),
        gateway = Gateway(),
        locker = MemoryLocker();
    await open(tester, gateway, locker, ticks: ticks);
    await tester.tap(find.byKey(const Key('debt-item-${fixture.sourceId}')));
    await tester.pumpAndSettle();
    final before = gateway.details;
    ticks.notifyListeners();
    await tester.pumpAndSettle();
    expect(gateway.details, before + 1);
    await tester.tap(find.byKey(const Key('debt-back')));
    await tester.pumpAndSettle();
    await declareReview(tester);
    ticks.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('debt-confirm')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const Key('debt-reload-review')));
    await tester.tap(find.byKey(const Key('debt-reload-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debt-party')), findsOneWidget);
    expect(find.byKey(const Key('debt-confirm')), findsNothing);
  });
}

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repair_widget_test.dart';

class _ClosedDay extends FakeRepairs {
  _ClosedDay({super.summary});

  @override
  Future<RepairContext> context({required String callerUserId}) async {
    final open = await super.context(callerUserId: callerUserId);
    return RepairContext(
      timeZone: open.timeZone,
      day: const RepairDayContext(state: 'closed'),
      cashMethods: open.cashMethods,
    );
  }
}

class _Unknown extends FakeRepairs {
  _Unknown({super.summary});

  @override
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    posts++;
    posted = command;
    return const RepairRpcUnknown();
  }

  @override
  Future<RepairRemoteStatus> commandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const RepairRemoteUnknown();
}

void main() {
  Future<void> openDetail(WidgetTester tester, FakeRepairs gateway) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: RepairScreen(
          gateway: gateway,
          store: MemoryLocker(),
          userId: userId,
          shopId: shopId,
          readOnly: false,
          newKey: () => key,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    expect(find.textContaining('الوزن الأصلي'), findsOneWidget);
  }

  testWidgets('a ready repair has no collect button', (tester) async {
    await openDetail(tester, FakeRepairs(summary: sample()));
    expect(find.byKey(const Key('repair-collect')), findsNothing);
  });

  testWidgets('a delivered open-day balance offers collect', (tester) async {
    await openDetail(tester, FakeRepairs(summary: sample(status: 'delivered')));
    expect(find.byKey(const Key('repair-collect')), findsOneWidget);
  });

  testWidgets('an archived repair with nothing left has no collect button', (
    tester,
  ) async {
    await openDetail(tester, FakeRepairs(summary: sample(status: 'archived')));
    expect(find.byKey(const Key('repair-collect')), findsNothing);
  });

  testWidgets('an archived open-day balance offers collect', (tester) async {
    final delivered = sample(status: 'delivered');
    final archived = RepairSummary(
      id: delivered.id,
      status: 'archived',
      recordVersion: delivered.recordVersion,
      customerName: delivered.customerName,
      customerPhone: delivered.customerPhone,
      itemDescription: delivered.itemDescription,
      measuredMilligrams: delivered.measuredMilligrams,
      karat: delivered.karat,
      issue: delivered.issue,
      custodyHeld: false,
      estimatedFeePiastres: delivered.estimatedFeePiastres,
      finalFeePiastres: delivered.finalFeePiastres,
      collectedPiastres: delivered.collectedPiastres,
      outstandingPiastres: delivered.outstandingPiastres,
      intakeAt: delivered.intakeAt,
      intakeAtShop: delivered.intakeAtShop,
    );
    await openDetail(tester, FakeRepairs(summary: archived));
    expect(find.byKey(const Key('repair-collect')), findsOneWidget);
  });

  testWidgets('a closed day hides collect', (tester) async {
    await openDetail(tester, _ClosedDay(summary: sample(status: 'delivered')));
    expect(find.byKey(const Key('repair-collect')), findsNothing);
  });

  testWidgets('review shows the cash increase and confirm sends the contract', (
    tester,
  ) async {
    final gateway = FakeRepairs(summary: sample(status: 'delivered'));
    final locker = MemoryLocker();
    var collected = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: RepairScreen(
          gateway: gateway,
          store: locker,
          userId: userId,
          shopId: shopId,
          readOnly: false,
          newKey: () => key,
          onCollected: () => collected++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-collect')));
    await tester.pumpAndSettle();
    expect(find.textContaining('المتبقي:'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('repair-collect-amount')),
      '200',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('repair-collect-review')));
    await tester.pumpAndSettle();
    expect(find.text('المبلغ أكبر من المتبقي.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('repair-collect-amount')),
      '120',
    );
    await tester.enterText(
      find.byKey(const Key('repair-tender-amount-0')),
      '120',
    );
    await tester.tap(find.byKey(const Key('repair-collect-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('تزيد النقدية:'), findsOneWidget);
    expect(find.textContaining('يصبح المتبقي:'), findsOneWidget);
    await tester.tap(find.byKey(const Key('repair-collect-confirm')));
    await tester.pumpAndSettle();
    expect(collected, 1);
    expect(find.text('تم تحصيل المبلغ وإضافته إلى النقدية.'), findsOneWidget);
    final payload = gateway.posted!.body['p_payload'] as Map;
    expect(payload, {
      'version': 1,
      'repair_id': repairId,
      'expected_version': '2',
      'day_id': '33333333-3333-4333-8333-333333333333',
      'day_version': '1',
      'amount_piastres': '12000',
      'tenders': [
        {'method': 'cash', 'piastres': '12000'},
      ],
    });
    expect(locker.stored, isNull);
  });

  testWidgets('an unknown collect result keeps the key and offers a check', (
    tester,
  ) async {
    final gateway = _Unknown(summary: sample(status: 'delivered'));
    final locker = MemoryLocker();
    await pumpRepair(tester, gateway: gateway, locker: locker);
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-collect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-collect-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-collect-confirm')));
    await tester.pumpAndSettle();
    expect(locker.stored?.key, key);
    expect(find.text('التحقق وإعادة المحاولة'), findsOneWidget);
  });
}

import 'dart:async';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:eldafttar/src/features/repairs/data/repair_codec.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_ticks.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'repair_widget_test.dart';
import 'repair_pending_navigation_test.dart' as navigation;

class DelayedSearch extends FakeRepairs {
  final oldPage = Completer<RepairPage>();
  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) {
    if (query == 'قديم') return oldPage.future;
    if (query == 'جديد') return Future.value(RepairPage(items: [sample()]));
    return Future.value(const RepairPage(items: []));
  }
}

class BrokenLocker extends MemoryLocker {
  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      throw const FormatException('unreadable');
}

class MissingBackend extends FakeRepairs {
  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) async => throw const RepairReadException('rpc_unavailable');
}

void main() {
  testWidgets(
    'missing repair migration shows unavailable state without enabling intake',
    (tester) async {
      final remote = MissingBackend();
      await pumpRepair(tester, gateway: remote, locker: MemoryLocker());
      expect(
        find.text('الصيانة غير متاحة في هذا الاتصال حاليًا.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('repair-new')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('repair-read-retry')), findsOneWidget);
      expect(remote.posts, 0);
    },
  );

  testWidgets('unreadable retry storage remains visible and blocks mutations', (
    tester,
  ) async {
    final remote = FakeRepairs();
    await pumpRepair(tester, gateway: remote, locker: BrokenLocker());
    expect(find.textContaining('تعذّر قراءة الطلب المحفوظ'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('repair-new')))
          .onPressed,
      isNull,
    );
    expect(remote.posts, 0);
  });

  testWidgets(
    'another workflow pending request remains intact and blocks repair intake',
    (tester) async {
      const pending = PendingFinancialCommand(
        key: key,
        kind: 'expense',
        body: {
          'p_idempotency_key': key,
          'p_payload': {'kind': 'expense'},
        },
      );
      final locker = MemoryLocker()..stored = pending;
      await pumpRepair(tester, gateway: FakeRepairs(), locker: locker);
      expect(find.textContaining('طلب دفتر محفوظ'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('repair-new')))
            .onPressed,
        isNull,
      );
      expect(locker.stored, pending);
    },
  );

  testWidgets(
    'expired entitlement removes write controls on an already open repair',
    (tester) async {
      var writable = true;
      final ticks = ChangeNotifier();
      addTearDown(ticks.dispose);
      await tester.pumpWidget(
        navigation.host(
          RepairScreen(
            gateway: FakeRepairs(summary: sample()),
            store: MemoryLocker(),
            userId: userId,
            shopId: shopId,
            readOnly: false,
            canWrite: () => writable,
            syncTicks: ticks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('عميل الإصلاح'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repair-handover-open')), findsOneWidget);
      writable = false;
      ticks.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repair-handover-open')), findsNothing);
      expect(find.textContaining('للقراءة فقط'), findsOneWidget);
    },
  );

  test(
    'repair-only sync invalidates open routes and reconnect preserves the repair revision',
    () {
      final ticks = ShopSyncTicks();
      var notifications = 0;
      ticks.addListener(() => notifications++);
      ticks.apply({ShopSyncScope.repair});
      expect(notifications, 1);
      expect(ticks.repair, 1);
      expect(ticks.ledger, 0);
      const first = ShopSyncSnapshot(
        shopId: 'shop',
        revision: 1,
        repairRevision: 1,
      );
      const next = ShopSyncSnapshot(
        shopId: 'shop',
        revision: 2,
        repairRevision: 2,
      );
      expect(next.changedFrom(first), {ShopSyncScope.repair});
      expect(next.asCatchUp().repairRevision, 2);
      expect(
        next.asCatchUp().changedFrom(first),
        contains(ShopSyncScope.repair),
      );
      ticks.dispose();
    },
  );

  test('repair read boundary rejects PostgreSQL bigint overflow', () {
    expect(
      () => parseRepairContext({
        'time_zone': 'Africa/Cairo',
        'day': {'state': 'uninitialized'},
        'cash_methods': [
          {'method': 'cash', 'balance_piastres': '9223372036854775808'},
        ],
      }),
      throwsFormatException,
    );
  });

  testWidgets('restored unknown repair disables every new mutation entry', (
    tester,
  ) async {
    final locker = MemoryLocker()
      ..stored = PendingFinancialCommand(
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
    final remote = FakeRepairs(summary: sample());
    await pumpRepair(tester, gateway: remote, locker: locker);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('repair-new')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('repair-handover-open')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('repair-cancel')))
          .onPressed,
      isNull,
    );
    expect(remote.posts, 0);
    expect(locker.stored!.key, key);
  });

  testWidgets('a delayed old search cannot replace the current results', (
    tester,
  ) async {
    final remote = DelayedSearch();
    await pumpRepair(tester, gateway: remote, locker: MemoryLocker());
    await tester.enterText(find.byKey(const Key('repair-search')), 'قديم');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('repair-search')), 'جديد');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('عميل الإصلاح'), findsOneWidget);
    remote.oldPage.complete(const RepairPage(items: []));
    await tester.pumpAndSettle();
    expect(find.text('عميل الإصلاح'), findsOneWidget);
  });

  testWidgets(
    'switching partial delivery to none ignores earlier tender drafts',
    (tester) async {
      final remote = FakeRepairs(summary: sample());
      await pumpRepair(tester, gateway: remote, locker: MemoryLocker());
      await tester.tap(find.text('عميل الإصلاح'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('repair-handover-open')));
      await tester.tap(find.byKey(const Key('repair-handover-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('repair-handover-final')),
        '200',
      );
      await tester.tap(find.byKey(const Key('repair-collection-part')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('repair-collected')), '80');
      await tester.enterText(
        find.byKey(const Key('repair-tender-amount-0')),
        '80',
      );
      await tester.tap(find.byKey(const Key('repair-collection-none')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('repair-handover-review')),
      );
      await tester.tap(find.byKey(const Key('repair-handover-review')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repair-handover-summary')), findsOneWidget);
      expect(find.textContaining('200'), findsWidgets);
      expect(
        find.text('لا يُسجّل نقد ولا حركة في دفتر اليوم.'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('repair-handover-confirm')),
      );
      await tester.tap(find.byKey(const Key('repair-handover-confirm')));
      await tester.pumpAndSettle();
      final payload = remote.posted!.body['p_payload'] as Map;
      expect(payload['collection'], 'none');
      expect(payload['collected_piastres'], '0');
      expect(payload['tenders'], isEmpty);
      expect(payload.containsKey('expected_day_id'), isFalse);
    },
  );

  testWidgets('detail audit labels stay Arabic', (tester) async {
    await pumpRepair(
      tester,
      gateway: FakeRepairs(summary: sample(status: 'delivered')),
      locker: MemoryLocker(),
    );
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    expect(find.textContaining('repair_intake'), findsNothing);
    expect(find.textContaining('استلام القطعة'), findsOneWidget);
    expect(find.textContaining('Africa/Cairo'), findsNothing);
  });
}

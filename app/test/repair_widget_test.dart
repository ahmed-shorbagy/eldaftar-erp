import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const repairId = '66666666-6666-4666-8666-666666666666';
const userId = 'owner-1';
const shopId = 'shop-1';
const key = '55555555-5555-4555-8555-555555555555';

class MemoryLocker implements FinancialCommandLocker {
  PendingFinancialCommand? stored;
  var saves = 0;

  @override
  Future<void> clear(String userId, String shopId, String key) async {
    if (stored?.key == key) stored = null;
  }

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      stored;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    saves++;
    stored = command;
  }
}

class FakeRepairs implements RepairGateway {
  FakeRepairs({this.summary});

  RepairSummary? summary;
  PendingFinancialCommand? posted;
  var posts = 0;
  RepairRpcResult result = const RepairRpcCommitted(
    repairId: repairId,
    replayed: false,
    result: {'ok': true},
  );

  @override
  Future<RepairRemoteStatus> commandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const RepairRemoteAbsent();

  @override
  Future<RepairContext> context({required String callerUserId}) async =>
      RepairContext(
        timeZone: 'Africa/Cairo',
        day: RepairDayContext(
          state: 'open',
          dayId: '33333333-3333-4333-8333-333333333333',
          businessDate: '2026-10-12',
          dayVersion: BigInt.one,
        ),
        cashMethods: [
          RepairCashMethod(
            method: 'cash',
            balancePiastres: BigInt.from(500000),
          ),
        ],
      );

  @override
  Future<RepairDetail> detail({
    required String callerUserId,
    required String repairId,
  }) async {
    final item = summary!;
    return RepairDetail(
      summary: item,
      intakeNotes: 'ملاحظة الاستلام',
      financialOperationId: null,
      cancellationReason: null,
      archivedFromStatus: null,
      intakeActorUserId: userId,
      timeZone: 'Africa/Cairo',
      events: const [
        RepairEventView(
          id: '77777777-7777-4777-8777-777777777777',
          eventType: 'repair_intake',
          actorUserId: userId,
          actorDisplayName: 'مالك المتجر',
          createdAt: '2026-10-12T08:00:00+00:00',
          createdAtShop: '2026-10-12T10:00:00',
        ),
      ],
      custodyEvents: [
        RepairCustodyView(
          id: '88888888-8888-4888-8888-888888888888',
          direction: 'intake',
          measuredMilligrams: item.measuredMilligrams,
          karat: item.karat,
          createdAtShop: '2026-10-12T10:00:00',
        ),
      ],
    );
  }

  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) async => RepairPage(items: [?summary]);

  @override
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    posts++;
    posted = command;
    return result;
  }
}

RepairSummary sample({String status = 'ready'}) => RepairSummary(
  id: repairId,
  status: status,
  recordVersion: BigInt.two,
  customerName: 'عميل الإصلاح',
  customerPhone: '01001234567',
  itemDescription: 'خاتم مفصص',
  measuredMilligrams: BigInt.from(1255),
  karat: 21,
  issue: 'مفصص',
  custodyHeld: status != 'delivered' && status != 'cancelled',
  estimatedFeePiastres: BigInt.from(15000),
  finalFeePiastres: status == 'delivered' ? BigInt.from(20000) : null,
  collectedPiastres: status == 'delivered' ? BigInt.from(8000) : BigInt.zero,
  outstandingPiastres: status == 'delivered' ? BigInt.from(12000) : BigInt.zero,
  intakeAt: '2026-10-12T08:00:00+00:00',
  intakeAtShop: '2026-10-12T10:00:00',
);

Future<void> pumpRepair(
  WidgetTester tester, {
  required FakeRepairs gateway,
  required MemoryLocker locker,
  bool readOnly = false,
  Size size = const Size(390, 844),
  Listenable? ticks,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: RepairScreen(
        gateway: gateway,
        store: locker,
        userId: userId,
        shopId: shopId,
        readOnly: readOnly,
        syncTicks: ticks,
        newKey: () => key,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('intake review shows custody and exact milligrams before save', (
    tester,
  ) async {
    final gateway = FakeRepairs();
    final locker = MemoryLocker();
    await pumpRepair(tester, gateway: gateway, locker: locker);
    await tester.tap(find.byKey(const Key('repair-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('repair-customer-name')),
      'عميل الإصلاح',
    );
    await tester.enterText(find.byKey(const Key('repair-item')), 'خاتم');
    await tester.enterText(find.byKey(const Key('repair-grams')), '1.255');
    await tester.tap(find.byKey(const Key('repair-karat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('repair-issue')), 'مفصص');
    await tester.enterText(find.byKey(const Key('repair-estimate')), '150');
    await tester.tap(find.byKey(const Key('repair-intake-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1,255 ملليجرام'), findsOneWidget);
    expect(find.text('المخزون القابل للبيع: 0'), findsOneWidget);
    expect(find.text('النقد: 0'), findsOneWidget);
    expect(gateway.posts, 0);
    expect(locker.saves, 0);
    await tester.tap(find.byKey(const Key('repair-intake-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.posts, 1);
    expect(locker.saves, 1);
    expect(gateway.posted?.kind, 'repair_intake');
    final payload = gateway.posted!.body['p_payload']! as Map;
    expect(payload['measured_milligrams'], '1255');
    expect(payload['estimated_fee_piastres'], '15000');
    expect(find.byKey(const Key('repair-success')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty intake validates on submit and does not send', (
    tester,
  ) async {
    final gateway = FakeRepairs();
    await pumpRepair(tester, gateway: gateway, locker: MemoryLocker());
    await tester.tap(find.byKey(const Key('repair-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-intake-submit')));
    await tester.pumpAndSettle();
    expect(find.text('هذا الحقل مطلوب.'), findsWidgets);
    expect(gateway.posts, 0);
  });

  testWidgets('unpaid handover and cancel require explicit confirmation', (
    tester,
  ) async {
    final gateway = FakeRepairs(summary: sample());
    await pumpRepair(tester, gateway: gateway, locker: MemoryLocker());
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    expect(find.textContaining('الوزن الأصلي'), findsOneWidget);
    expect(find.textContaining('12 أكتوبر 2026، 10:00:00'), findsWidgets);
    await tester.tap(find.byKey(const Key('repair-handover-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-collection-none')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-handover-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا يُسجّل نقد'), findsOneWidget);
    expect(find.text('المخزون القابل للبيع: 0'), findsOneWidget);
    expect(gateway.posts, 0);
    await tester.tap(find.byKey(const Key('repair-handover-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.posts, 1);
    final payload = gateway.posted!.body['p_payload']! as Map;
    expect(payload['collection'], 'none');
    expect(payload['collected_piastres'], '0');
    expect(payload.containsKey('expected_day_id'), isFalse);

    gateway.posts = 0;
    gateway.summary = sample(status: 'in_progress');
    await tester.tap(find.byKey(const Key('repair-back-to-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('repair-cancel')));
    await tester.tap(find.byKey(const Key('repair-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.posts, 0);
    expect(find.textContaining('راجع الحقول'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('repair-cancel-reason')),
      'العميل استرد القطعة',
    );
    await tester.tap(find.byKey(const Key('repair-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.posts, 1);
    expect(
      (gateway.posted!.body['p_payload']! as Map)['confirm_return'],
      isTrue,
    );
  });

  testWidgets('archive keeps outstanding copy and read only blocks writes', (
    tester,
  ) async {
    final gateway = FakeRepairs(summary: sample(status: 'delivered'));
    await pumpRepair(tester, gateway: gateway, locker: MemoryLocker());
    await tester.tap(find.text('عميل الإصلاح'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-archive')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا تعكس النقد'), findsOneWidget);
    expect(find.textContaining('120'), findsWidgets);
    await tester.tap(find.byKey(const Key('repair-archive-confirm')));
    await tester.pumpAndSettle();
    expect(
      (gateway.posted!.body['p_payload']! as Map)['confirm_archive'],
      isTrue,
    );

    await pumpRepair(
      tester,
      gateway: FakeRepairs(),
      locker: MemoryLocker(),
      readOnly: true,
    );
    expect(find.textContaining('للقراءة فقط'), findsOneWidget);
    expect(find.byKey(const Key('repair-new')), findsNothing);
  });

  testWidgets('pending retry and stale review do not send a second body', (
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
            'issue': 'مفصص',
            'intake_notes': '',
            'estimated_fee_piastres': null,
          },
        },
      );
    final gateway = FakeRepairs();
    final ticks = ChangeNotifier();
    await pumpRepair(tester, gateway: gateway, locker: locker, ticks: ticks);
    expect(find.byKey(const Key('repair-pending-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('repair-pending-retry')));
    await tester.pumpAndSettle();
    expect(gateway.posts, 1);
    expect(gateway.posted?.key, key);
    await tester.tap(find.byKey(const Key('repair-back-to-list')));
    await tester.pumpAndSettle();

    gateway.posts = 0;
    locker.stored = null;
    await tester.tap(find.byKey(const Key('repair-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('repair-customer-name')),
      'عميل',
    );
    await tester.enterText(find.byKey(const Key('repair-item')), 'خاتم');
    await tester.enterText(find.byKey(const Key('repair-grams')), '1.260');
    await tester.tap(find.byKey(const Key('repair-karat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('repair-issue')), 'لحام');
    await tester.tap(find.byKey(const Key('repair-intake-submit')));
    await tester.pumpAndSettle();
    ticks.notifyListeners();
    await tester.pumpAndSettle();
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('repair-intake-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(gateway.posts, 0);
  });

  testWidgets('more navigation exposes repairs or an unavailable explanation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> pump({WidgetBuilder? repairs}) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          home: ShopWorkspace(
            shop: const ShopAccount(
              id: shopId,
              name: 'متجر',
              role: 'owner',
              entitlement: ShopEntitlement.active,
            ),
            onSignOut: () async {},
            onToggleTheme: (_) async {},
            repairBuilder: repairs,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
    }

    await pump();
    expect(
      find.byKey(const Key('workspace-repairs-unavailable')),
      findsOneWidget,
    );
    expect(find.text('الصيانة غير متاحة في هذا الاتصال.'), findsOneWidget);
    expect(find.byKey(const Key('workspace-help')), findsNothing);

    await pump(
      repairs: (_) => RepairScreen(
        gateway: FakeRepairs(),
        store: MemoryLocker(),
        userId: userId,
        shopId: shopId,
        readOnly: false,
      ),
    );
    await tester.tap(find.byKey(const Key('workspace-repairs')));
    await tester.pumpAndSettle();
    expect(find.text('استلام قطعة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

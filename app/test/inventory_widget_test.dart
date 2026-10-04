import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_command_flow.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/purchase_cash_settlement_screen.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_forms.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_screen.dart';
import 'package:eldafttar/src/features/inventory/presentation/trader_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const userId = 'owner-1';
const shopId = 'shop-1';
const traderId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

DayAnchor get day =>
    (DayAnchor.tryCreate(dayId, '2') as InventoryAccepted<DayAnchor>).value;

class MemoryGuide implements OnboardingStore {
  final steps = <String, int>{};
  final done = <String>{};

  @override
  Future<bool> isComplete(String path) async => done.contains(path);

  @override
  Future<int> readStep(String path) async => steps[path] ?? 0;

  @override
  Future<void> saveStep(String path, int step) async => steps[path] = step;

  @override
  Future<void> markComplete(String path) async => done.add(path);
}

class MemoryLocker implements FinancialCommandLocker {
  PendingFinancialCommand? value;

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      value;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async => value = command;

  @override
  Future<void> clear(String userId, String shopId, String key) async {
    if (value?.key == key) value = null;
  }
}

class QuietOpening implements OpeningGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      const DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: null,
        cash: [],
        stock: [],
        scrap: [],
        feed: [],
      );

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => Future.error(UnimplementedError());
}

class QuietInventory implements InventoryGateway {
  QuietInventory(this.onPost);
  final Future<FinancialCommandResult> Function(
    PendingFinancialCommand command,
  )?
  onPost;
  int posts = 0;

  @override
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) {
    posts++;
    final post = onPost;
    if (post == null) return Future.value(const FinancialUnknown());
    return post(command);
  }

  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) async => InventoryTotals(const []);

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) async => const LotPage([], null);

  @override
  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  }) async => const MovementPage([], null);

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const TraderPage([], null);

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) => Future.error(const InventoryReadException('not_found'));

  @override
  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  }) async => const TraderActivityPage([], null);

  @override
  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  }) async => const ReceiptPage.ready([], null);

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.missing();

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.missing();

  @override
  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();
}

class _TraderInventory extends QuietInventory {
  _TraderInventory() : super(null);

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const TraderPage([
    TraderSummary(
      id: traderId,
      displayName: 'تاجر الاختبار',
      phone: '',
      active: true,
      createdAt: '2026-10-04T08:00:00Z',
      cursor: '',
    ),
  ], null);

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) async => TraderDetail(
    id: traderId,
    displayName: 'تاجر الاختبار',
    phone: '',
    note: '',
    active: true,
    createdAt: '2026-10-04T08:00:00Z',
    originalHeldMilligrams: BigInt.zero,
    currentHeldMilligrams: BigInt.zero,
    pendingReceiptCount: BigInt.zero,
    cashPayableRemainingPiastres: BigInt.from(15000),
    goldRemaining: const [],
    buckets: const [],
  );

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) async => ReadPage.ready([
    TraderObligation(
      operationId: operationId,
      unit: 'egp_piastres',
      karat: null,
      original: BigInt.from(20000),
      remaining: BigInt.from(15000),
      createdAt: '2026-10-04T08:00:00Z',
      cursor: '',
    ),
  ], null);
}

class _CashSettlement implements PurchaseSettlementGateway {
  @override
  Future<FinancialCommandResult> settlePurchaseCash({
    required String callerUserId,
    required String idempotencyKey,
    required String purchaseOperationId,
    required List<Map<String, Object?>> tenders,
  }) async => const FinancialUnknown();
}

/// The page [ListView] scrolls vertically and stays in semantics.
/// Text fields also insert [Scrollable]s, so an unfiltered finder matches
/// more than one.
Finder get _pageScroll => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      widget.axisDirection == AxisDirection.down &&
      !widget.excludeFromSemantics,
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  home: child,
);

InventoryFormScope _scope({
  required InventoryCommandFlow flow,
  required MemoryLocker store,
  bool readOnly = false,
}) => InventoryFormScope(
  flow: flow,
  userId: userId,
  shopId: shopId,
  readOnly: readOnly,
  day: day,
  reloadDay: () async => day,
);

Future<void> _fillAddition(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('add-name')), 'خاتم');
  await tester.enterText(find.byKey(const Key('add-grams')), '10');
  await tester.enterText(find.byKey(const Key('add-count')), '1');
  await tester.enterText(find.byKey(const Key('add-reason')), 'جرد');
  await tester.pump();
}

void main() {
  testWidgets('addition review shows the effect before confirm', (
    tester,
  ) async {
    final locker = MemoryLocker();
    final inventory = QuietInventory(null);
    final flow = InventoryCommandFlow(
      gateway: inventory,
      statusGateway: QuietOpening(),
      store: locker,
    );
    await tester.pumpWidget(
      _host(
        InventoryAdditionForm(
          scope: _scope(flow: flow, store: locker),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillAddition(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-review')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-review')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('يزيد المتاح للبيع: 10.000 جرام'),
      findsOneWidget,
    );
    expect(find.textContaining('حفظ الخادم الأمر'), findsNothing);
    expect(inventory.posts, 0);
    expect(locker.value, isNull);
  });

  testWidgets('submit stays disabled until the server commits', (tester) async {
    final completer = Completer<FinancialCommandResult>();
    final locker = MemoryLocker();
    final inventory = QuietInventory((command) => completer.future);
    final flow = InventoryCommandFlow(
      gateway: inventory,
      statusGateway: QuietOpening(),
      store: locker,
    );
    await tester.pumpWidget(
      _host(
        InventoryAdditionForm(
          scope: _scope(flow: flow, store: locker),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillAddition(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-review')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-review')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-submit')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-submit')));
    await tester.pump();
    final busy = tester.widget<FilledButton>(
      find.byKey(const Key('command-submit')),
    );
    expect(busy.onPressed, isNull);
    expect(find.textContaining('حفظ الخادم الأمر'), findsNothing);
    completer.complete(const FinancialCommitted(operationId, replayed: false));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory-status')),
      -200,
      scrollable: _pageScroll,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('حفظ الخادم الأمر'), findsOneWidget);
    expect(locker.value, isNull);
  });

  testWidgets('a rejected command is not described as saved', (tester) async {
    final locker = MemoryLocker();
    final inventory = QuietInventory(
      (_) async => const FinancialRejected('insufficient_lot'),
    );
    final flow = InventoryCommandFlow(
      gateway: inventory,
      statusGateway: QuietOpening(),
      store: locker,
    );
    await tester.pumpWidget(
      _host(
        InventoryAdditionForm(
          scope: _scope(flow: flow, store: locker),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillAddition(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-review')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-review')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-submit')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-submit')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory-status')),
      -200,
      scrollable: _pageScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text('الرصيد المؤكد لا يكفي.'), findsOneWidget);
    expect(find.textContaining('حفظ الخادم'), findsNothing);
    expect(locker.value, isNull);
  });

  testWidgets('read-only inventory disables writes and saves nothing', (
    tester,
  ) async {
    final locker = MemoryLocker();
    final inventory = QuietInventory(null);
    await tester.pumpWidget(
      _host(
        InventoryScreen(
          gateway: inventory,
          statusGateway: QuietOpening(),
          userId: userId,
          shopId: shopId,
          shopName: 'متجر',
          readOnly: true,
          onboardingStore: MemoryGuide()
            ..done.add('inventory-help_${userId}_$shopId'),
          store: locker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory-add')),
      300,
      scrollable: _pageScroll,
    );
    final add = tester.widget<FilledButton>(
      find.byKey(const Key('inventory-add')),
    );
    expect(add.onPressed, isNull);
    expect(inventory.posts, 0);
    expect(locker.value, isNull);
    expect(find.textContaining('حفظ الخادم'), findsNothing);
  });

  testWidgets('the guide focuses search and skip keeps the step', (
    tester,
  ) async {
    final guide = MemoryGuide();
    final locker = MemoryLocker();
    await tester.pumpWidget(
      _host(
        InventoryScreen(
          gateway: QuietInventory(null),
          statusGateway: QuietOpening(),
          userId: userId,
          shopId: shopId,
          shopName: 'متجر',
          readOnly: false,
          onboardingStore: guide,
          store: locker,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-action')));
    await tester.pump();
    final search = tester.widget<TextField>(
      find.byKey(const Key('inventory-search')),
    );
    expect(search.focusNode!.hasFocus, isTrue);
    expect(guide.steps['inventory-help_${userId}_$shopId'], 1);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pump();
    expect(guide.steps['inventory-help_${userId}_$shopId'], 1);
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    expect(locker.value, isNull);
  });

  testWidgets('an edit after review cannot submit the stale values', (
    tester,
  ) async {
    final locker = MemoryLocker();
    final inventory = QuietInventory(null);
    final flow = InventoryCommandFlow(
      gateway: inventory,
      statusGateway: QuietOpening(),
      store: locker,
    );
    await tester.pumpWidget(
      _host(
        InventoryAdditionForm(
          scope: _scope(flow: flow, store: locker),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillAddition(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-review')),
      200,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('command-review')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-grams')), '11');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('command-submit')),
      200,
      scrollable: _pageScroll,
    );
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('command-submit')),
    );
    expect(submit.onPressed, isNull);
    expect(inventory.posts, 0);
    expect(locker.value, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory-status')),
      -200,
      scrollable: _pageScroll,
    );
    expect(find.textContaining('تغيّرت البيانات'), findsOneWidget);
  });

  testWidgets('cash settlement opens the existing payable workflow', (
    tester,
  ) async {
    final inventory = _TraderInventory();
    await tester.pumpWidget(
      _host(
        TraderScreen(
          gateway: inventory,
          statusGateway: QuietOpening(),
          userId: userId,
          shopId: shopId,
          shopName: 'متجر',
          readOnly: false,
          store: MemoryLocker(),
          settlementGateway: _CashSettlement(),
          sharePdf: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trader-row-$traderId')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('trader-obligation-$operationId')),
      300,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const Key('trader-obligation-$operationId')));
    await tester.pumpAndSettle();
    expect(find.byType(PurchaseCashSettlementScreen), findsOneWidget);
    expect(find.text('سداد مستحق شراء'), findsOneWidget);
  });
}

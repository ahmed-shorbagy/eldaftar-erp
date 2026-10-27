import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repair_command_flow_test.dart' show MemoryLocker;

const userId = 'd1111111-1111-4111-8111-111111111111';
const shopId = 'd1222222-2222-4222-8222-222222222222';
const sourceId = 'd3000000-0000-4000-8000-000000000201';
const key = 'd3000000-0000-4000-8000-000000000202';

DebtSummary sampleSummary() => DebtSummary(
  debtKey: 'standalone:$sourceId',
  sourceKind: DebtSourceKind.standalone,
  sourceId: sourceId,
  direction: DebtDirection.shopOwes,
  unit: DebtUnit.money,
  karat: null,
  partyName: 'طرف تاريخي',
  contactPhone: '',
  reason: 'دين خارجي',
  externalReference: 'EXT-1',
  original: BigInt.from(1000),
  settled: BigInt.zero,
  remaining: BigInt.from(1000),
  displayStatus: 'open',
  recordVersion: BigInt.one,
  createdAt: '2026-10-13T20:00:00.000000Z',
  createdAtShop: '2026-10-13T22:00:00',
);

DebtDetail sampleDetail() => DebtDetail(
  summary: sampleSummary(),
  timeZone: 'Africa/Cairo',
  canSettle: true,
  canCancel: true,
  canArchive: true,
  noLedgerAllowed: true,
  history: const [
    DebtHistoryEntry(
      id: key,
      at: '2026-10-13T20:00:00.000000Z',
      atShop: '2026-10-13T22:00:00',
      eventType: 'declared',
      kind: 'declared',
      label: 'تسجيل دين',
      payload: {},
    ),
  ],
);

class FakeDebts implements DebtGateway {
  FakeDebts({this.failRead = false, this.unknownSubmit = false});

  final bool failRead;
  final bool unknownSubmit;
  var submits = 0;

  @override
  Future<DebtContext> readContext({required String callerUserId}) async =>
      DebtContext(
        timeZone: 'Africa/Cairo',
        day: DebtDayContext(
          state: 'open',
          dayId: 'd3000000-0000-4000-8000-000000000203',
          businessDate: '2026-10-13',
          dayVersion: BigInt.one,
        ),
        cashMethods: [],
        lots: [],
      );

  @override
  Future<DebtRemoteStatus> readCommandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const DebtRemoteAbsent();

  @override
  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  }) async => sampleDetail();

  @override
  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) async {
    if (failRead) throw const DebtReadException('forbidden');
    return DebtPage(
      items: [sampleSummary()],
      nextCursor: null,
      timeZone: 'Africa/Cairo',
    );
  }

  @override
  Future<DebtRpcResult> submitCommand({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    submits++;
    if (unknownSubmit) return const DebtRpcUnknown();
    return DebtRpcCommitted(
      sourceId: sourceId,
      sourceKind: 'standalone',
      commandKind: command.kind,
      replayed: false,
      effect: DebtEffect.zero,
      displayStatus: 'open',
      original: BigInt.from(1050),
      settled: BigInt.zero,
      remaining: BigInt.from(1050),
      ledgerEffect: 'none',
      operationId: null,
      result: const {},
    );
  }
}

Widget host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  home: child,
);

void main() {
  testWidgets('list and detail show original settled and remaining', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        DebtScreen(
          gateway: FakeDebts(),
          store: MemoryLocker(),
          userId: userId,
          shopId: shopId,
          readOnly: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('طرف تاريخي'), findsOneWidget);
    expect(find.text('بحث'), findsOneWidget);
    await tester.tap(find.byKey(Key('debt-item-$sourceId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debt-remaining')), findsOneWidget);
    expect(find.textContaining('المتبقي'), findsOneWidget);
    expect(find.text('تسجيل دين'), findsOneWidget);
  });

  testWidgets('declare form validates then reviews a zero-effect record', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeDebts();
    await tester.pumpWidget(
      host(
        DebtScreen(
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
    await tester.tap(find.byKey(const Key('debt-open-declare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('debt-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debt-review')), findsNothing);
    expect(find.text('اكتب اسم الطرف.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('debt-party')), 'طرف جديد');
    await tester.enterText(find.byKey(const Key('debt-reason')), 'سبب تاريخي');
    await tester.enterText(find.byKey(const Key('debt-amount')), '10.50');
    await tester.tap(find.byKey(const Key('debt-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'تسجيل دين تاريخي. لا يتحرك نقد أو ذهب أو أمانة أو مخزون قابل للبيع.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('10.50'), findsWidgets);
    await tester.tap(find.byKey(const Key('debt-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debt-success')), findsOneWidget);
    expect(gateway.submits, 1);
  });

  testWidgets('read failure stays visible in read-only mode', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        DebtScreen(
          gateway: FakeDebts(failRead: true),
          store: MemoryLocker(),
          userId: userId,
          shopId: shopId,
          readOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debt-error')), findsOneWidget);
    expect(find.byKey(const Key('debt-open-declare')), findsNothing);
  });

  testWidgets('workspace more menu opens debts from the provided gateway', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        ShopWorkspace(
          shop: const ShopAccount(
            id: shopId,
            name: 'متجر اختبار',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          debtBuilder: (_) => DebtScreen(
            gateway: FakeDebts(),
            store: MemoryLocker(),
            userId: userId,
            shopId: shopId,
            readOnly: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    // The debts link renders only when a debt gateway is provided; it can sit
    // below the fold of the lazy more menu at narrow widths.
    final debts = find.byKey(const Key('workspace-debts'));
    if (debts.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        debts,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }
    expect(debts, findsOneWidget);
    await tester.ensureVisible(debts);
    await tester.tap(debts);
    await tester.pumpAndSettle();
    expect(find.text('طرف تاريخي'), findsOneWidget);
  });
}

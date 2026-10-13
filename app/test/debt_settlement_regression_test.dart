import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:flutter/material.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'debt_widget_test.dart' as f;
import 'repair_command_flow_test.dart' show MemoryLocker;

class SettlementGateway extends f.FakeDebts {
  SettlementGateway(this.mode);
  final String mode;
  PendingFinancialCommand? sent;
  DebtSummary get summary => DebtSummary(
    debtKey: 'standalone:${f.sourceId}',
    sourceKind: DebtSourceKind.standalone,
    sourceId: f.sourceId,
    direction: mode == 'gold-in'
        ? DebtDirection.owedToShop
        : DebtDirection.shopOwes,
    unit: mode == 'money' ? DebtUnit.money : DebtUnit.gold,
    karat: mode == 'money'
        ? null
        : mode == 'gold-in'
        ? 24
        : 18,
    partyName: 'طرف سداد اصطناعي',
    contactPhone: '',
    reason: 'التزام سابق',
    externalReference: 'FLOW-$mode',
    original: BigInt.from(mode == 'money' ? 1000 : 2000),
    settled: BigInt.zero,
    remaining: BigInt.from(mode == 'money' ? 1000 : 2000),
    displayStatus: 'open',
    recordVersion: BigInt.one,
    createdAt: '2026-10-13T10:00:00Z',
    createdAtShop: '2026-10-13T13:00:00',
  );
  @override
  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) async =>
      DebtPage(items: [summary], nextCursor: null, timeZone: 'Africa/Cairo');
  @override
  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  }) async => DebtDetail(
    summary: summary,
    timeZone: 'Africa/Cairo',
    canSettle: true,
    canCancel: true,
    canArchive: true,
    noLedgerAllowed: true,
    history: [],
  );
  @override
  Future<DebtContext> readContext({required String callerUserId}) async =>
      DebtContext(
        timeZone: 'Africa/Cairo',
        day: DebtDayContext(
          state: 'open',
          dayId: f.key,
          businessDate: '2026-10-13',
          dayVersion: BigInt.one,
        ),
        cashMethods: [
          DebtCashMethod(method: 'cash', balancePiastres: BigInt.from(10000)),
        ],
        lots: [
          DebtLot(
            id: f.key,
            category: 'scrap',
            karat: 18,
            displayName: 'كسر مملوك',
            milligrams: BigInt.from(10000),
            count: null,
            tracksCount: false,
          ),
        ],
      );
  @override
  Future<DebtRpcResult> submitCommand({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    submits++;
    sent = command;
    final body = command.body['p_payload'] as Map;
    final amount = BigInt.parse(body['amount'] as String);
    return parseDebtCommand({
      'ok': true,
      'replayed': false,
      'command_kind': command.kind,
      'source_kind': 'standalone',
      'source_id': f.sourceId,
      'display_status': amount == summary.original ? 'settled' : 'open',
      'original_amount': summary.original.toString(),
      'settled_amount': amount.toString(),
      'cancelled_amount': '0',
      'remaining_amount': (summary.original - amount).toString(),
      'ledger_effect': 'move',
      'operation_id': f.key,
      'cash_piastres': mode == 'money' ? (-amount).toString() : '0',
      'gold_milligrams': mode == 'money'
          ? '0'
          : (mode == 'gold-in' ? amount : -amount).toString(),
      'gold_count': mode == 'gold-in' ? '1' : '0',
      'custody_milligrams': '0',
      'saleable_stock_milligrams': mode == 'gold-in' ? amount.toString() : '0',
    });
  }
}

Future<void> prepareSettlement(
  WidgetTester tester,
  SettlementGateway gateway, {
  double width = 390,
  ThemeMode theme = ThemeMode.light,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final screen = DebtScreen(
    gateway: gateway,
    store: MemoryLocker(),
    userId: f.userId,
    shopId: f.shopId,
    readOnly: false,
    newKey: () => f.key,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: theme,
      home: capture == null
          ? screen
          : RepaintBoundary(key: capture, child: screen),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('debt-item-${f.sourceId}')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('debt-settle')));
  await tester.tap(find.byKey(const Key('debt-settle')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('debt-settle-amount')),
    gateway.mode == 'money' ? '5' : '1.255',
  );
  await tester.enterText(
    find.byKey(const Key('debt-settle-reason')),
    'سداد مضبوط',
  );
  if (gateway.mode == 'money') {
    await tester.enterText(find.byKey(const Key('debt-tender-0')), '5');
  } else if (gateway.mode == 'gold-in') {
    expect(find.text('سبائك'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('debt-receipt-product')),
      'سبيكة مملوكة',
    );
    await tester.enterText(find.byKey(const Key('debt-receipt-count')), '1');
  } else {
    await tester.ensureVisible(find.byKey(const Key('debt-lot-pick-${f.key}')));
    await tester.tap(find.byKey(const Key('debt-lot-pick-${f.key}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('debt-lot-grams-${f.key}')),
      '1.255',
    );
  }
  await tester.ensureVisible(find.byKey(const Key('debt-submit')));
  await tester.tap(find.byKey(const Key('debt-submit')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final mode in ['money', 'gold-in', 'gold-out']) {
    testWidgets('review and confirm exact $mode settlement', (tester) async {
      final gateway = SettlementGateway(mode);
      await prepareSettlement(tester, gateway);
      expect(gateway.submits, 0);
      expect(find.byKey(const Key('debt-review')), findsOneWidget);
      expect(find.textContaining('المتبقي بعد السداد'), findsOneWidget);
      if (mode != 'money') {
        expect(find.textContaining('1,255 ملليجرام'), findsWidgets);
        expect(
          find.textContaining(
            mode == 'gold-in' ? 'استلام ذهب مملوك' : 'تسليم من المخزون المملوك',
          ),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(find.byKey(const Key('debt-confirm')));
      await tester.tap(find.byKey(const Key('debt-confirm')));
      await tester.pumpAndSettle();
      expect(gateway.submits, 1);
      expect(find.byKey(const Key('debt-success')), findsOneWidget);
      final payload = gateway.sent!.body['p_payload'] as Map;
      expect(payload['amount'], mode == 'money' ? '500' : '1255');
      expect(
        payload['karat'],
        mode == 'money'
            ? null
            : mode == 'gold-in'
            ? 24
            : 18,
      );
    });
  }
}

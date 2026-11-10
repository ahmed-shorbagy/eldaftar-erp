import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/cash_transfer_screen.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _cash = [
  LedgerCashLine(
    method: 'cash',
    labelAr: 'نقدي',
    piastres: '10000',
    pounds: '100.00',
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
];

class _TransferGateway implements CashTransferGateway, OpeningGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Locker implements FinancialCommandLocker {
  @override
  Future<void> clear(String userId, String shopId, String key) async {}

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      null;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {}
}

class _Repairs implements RepairGateway {
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
        cashMethods: const [],
      );

  @override
  Future<RepairDetail> detail({
    required String callerUserId,
    required String repairId,
  }) => throw UnimplementedError();

  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) async => const RepairPage(items: []);

  @override
  Future<RepairRpcResult> collectOutstanding({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => post(
    callerUserId: callerUserId,
    command: repairCollectCommand(idempotencyKey, payload),
  );

  @override
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) => throw UnimplementedError();
}

Future<void> _expectDismissed(
  WidgetTester tester, {
  required Key field,
  required Finder outside,
}) async {
  await tester.tap(find.byKey(field));
  await tester.pump();
  final focused = FocusManager.instance.primaryFocus;
  expect(focused, isNotNull);
  expect(tester.testTextInput.isVisible, isTrue);
  await tester.tap(outside);
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, isNot(focused));
  expect(tester.testTextInput.isVisible, isFalse);
}

void main() {
  testWidgets('cash transfer note closes on tap outside and on Done', (
    tester,
  ) async {
    final gateway = _TransferGateway();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CashTransferScreen(
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-a',
            shopId: 'shop-a',
            cash: _cash,
          ),
        ),
      ),
    );
    await _expectDismissed(
      tester,
      field: const Key('transfer-note'),
      outside: find.text('تحويل نقدية'),
    );

    await tester.tap(find.byKey(const Key('transfer-note')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('repair intake note closes when the title is tapped', (
    tester,
  ) async {
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
          gateway: _Repairs(),
          store: _Locker(),
          userId: 'owner-1',
          shopId: 'shop-1',
          readOnly: false,
          newKey: () => '55555555-5555-4555-8555-555555555555',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair-new')));
    await tester.pumpAndSettle();
    await _expectDismissed(
      tester,
      field: const Key('repair-notes'),
      outside: find.text('استلام مرمة'),
    );
  });
}

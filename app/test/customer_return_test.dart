import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReturnGateway
    implements FinancialGateway, OpeningGateway, CustomerReturnGateway {
  FinancialCommandResult result = const FinancialCommitted(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    replayed: false,
  );
  StatusResult statusResult = const StatusAbsent();
  var reconcileAfterUnknown = false;
  var _checks = 0;
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];

  @override
  Future<FinancialCommandResult> postCustomerReturn({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    keys.add(idempotencyKey);
    payloads.add(payload);
    return result;
  }

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => result;

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async => result;

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    if (!reconcileAfterUnknown) return statusResult;
    _checks += 1;
    return _checks == 1
        ? const StatusUnknown()
        : const StatusCompleted('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  }

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const ConfirmUnknown();

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      throw UnimplementedError();

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(state: 'open');

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) async => result;

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) async => result;

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {};
}

DailyLedgerView _ledger() => DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: const LedgerBusinessDay(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    businessDate: '2026-11-08',
    openedAt: '2026-11-08T08:00:00+00:00',
  ),
  cash: const [
    LedgerCashLine(
      method: 'cash',
      labelAr: 'كاش',
      piastres: '1000000',
      pounds: '10000.00',
    ),
  ],
  stock: const [],
  scrap: const [],
  feed: const [],
  journalContext: LedgerJournalContext(
    businessDate: '2026-11-08',
    dayIds: const ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'],
    serverNow: DateTime.utc(2026, 11, 8, 10),
    nextMidnightAt: DateTime.utc(2026, 11, 9),
    returnCount: 0,
    noteCount: 0,
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('the returns row opens إضافة مرتجع and hides without the grant', (
    tester,
  ) async {
    final gateway = _ReturnGateway();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) => ConfirmedLedgerDashboard(
                ledger: _ledger(),
                shopId: 'shop-1',
                onAddReturn: () {
                  opened = true;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FinancialTradeScreen(
                        kind: FinancialKind.customerReturn,
                        gateway: gateway,
                        statusGateway: gateway,
                        userId: 'owner-1',
                        shopId: 'shop-1',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ledger-add-return')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('ledger-add-return')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ledger-add-return')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.byType(FinancialTradeScreen), findsOneWidget);
    expect(find.byKey(const Key('trade-select-كسر')), findsNothing);
    await tester.dragUntilVisible(
      find.text('طريقة رد المبلغ'),
      find.descendant(
        of: find.byType(FinancialTradeScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -200),
    );
    expect(find.text('طريقة رد المبلغ'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConfirmedLedgerDashboard(
              ledger: _ledger(),
              shopId: 'shop-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-add-return')), findsNothing);
  });

  testWidgets('a ring return posts the contract and reviews cash and stock', (
    tester,
  ) async {
    final gateway = _ReturnGateway();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: FinancialTradeScreen(
            kind: FinancialKind.customerReturn,
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-1',
            shopId: 'shop-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-select-خاتم')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '2.00');
    await tester.tap(find.byKey(const Key('trade-karat-0-worked_jewelry-18')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '5000',
    );
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('تنقص النقدية'), findsOneWidget);
    expect(find.textContaining('يزيد مخزون خاتم عيار 21'), findsOneWidget);
    expect(
      find.text('مجموع وسائل الدفع لا يساوي المبلغ المطلوب.'),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payloads.single, {
      'version': 1,
      'kind': 'customer_return',
      'total_piastres': '500000',
      'tenders': [
        {'method': 'cash', 'piastres': '500000'},
      ],
      'items': [
        {
          'category': 'worked_jewelry',
          'karat': 21,
          'milligrams': '2000',
          'count': '1',
          'item_name': 'خاتم',
          'line_price_piastres': null,
        },
      ],
      'customer_name': '',
      'customer_phone': '',
      'note': '',
    });
  });

  testWidgets('an unknown return offers التحقق من الحالة and then reconciles', (
    tester,
  ) async {
    final gateway = _ReturnGateway()
      ..result = const FinancialUnknown()
      ..reconcileAfterUnknown = true;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: FinancialTradeScreen(
            kind: FinancialKind.customerReturn,
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-1',
            shopId: 'shop-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-select-خاتم')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '2.00');
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '5000',
    );
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-check-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-check-status')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(gateway.keys, hasLength(1));
  });
}

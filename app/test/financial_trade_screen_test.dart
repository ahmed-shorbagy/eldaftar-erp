import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_close_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFinancialGateway implements FinancialGateway, OpeningGateway {
  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => result;
  FinancialCommandResult result = const FinancialCommitted(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    replayed: false,
  );
  StatusResult statusResult = const StatusAbsent();
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];
  final closeCounts = <Map<String, Object?>>[];
  bool pendingExistedAtPost = false;

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async {
    pendingExistedAtPost =
        (await const PendingFinancialCommands().read(
          'owner-1',
          'shop-1',
        ))?.key ==
        idempotencyKey;
    keys.add(idempotencyKey);
    payloads.add(draft.toJson());
    return result;
  }

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => statusResult;

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
  }) async {
    closeCounts.add(counted);
    return result;
  }

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

Future<void> pumpTrade(
  WidgetTester tester,
  FakeFinancialGateway gateway,
  FinancialKind kind,
) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FinancialTradeScreen(
          kind: kind,
          gateway: gateway,
          statusGateway: gateway,
          userId: 'owner-1',
          shopId: 'shop-1',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> nextTrade(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('trade-next')));
  await tester.pumpAndSettle();
}

Future<void> beginTrade(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('trade-select-name')),
    'صنف تجريبي',
  );
  await nextTrade(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('close blocks a discrepancy and posts only matching counts', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    const day = FinancialDayState(
      state: 'open',
      dayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      businessDate: '2026-09-28',
      dayVersion: 2,
      counts: {
        'cash': {
          'cash': '100',
          'instant_transfer': '0',
          'wallet': '0',
          'card': '0',
        },
        'stock': [],
        'scrap': [],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DailyCloseScreen(
            gateway: gateway,
            statusGateway: gateway,
            userId: 'owner-close',
            shopId: 'shop-close',
            day: day,
          ),
        ),
      ),
    );
    for (final method in ['cash', 'instant_transfer', 'wallet', 'card']) {
      await tester.enterText(
        find.byKey(Key('close-cash-$method')),
        method == 'cash' ? '1.01' : '0',
      );
    }
    await tester.tap(find.byKey(const Key('close-review')));
    await tester.pump();
    expect(find.textContaining('يوجد فرق'), findsOneWidget);
    expect(gateway.closeCounts, isEmpty);
    await tester.enterText(find.byKey(const Key('close-cash-cash')), '1.00');
    await tester.tap(find.byKey(const Key('close-review')));
    await tester.pump();
    expect(find.byKey(const Key('close-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.closeCounts, hasLength(1));
    expect((gateway.closeCounts.single['cash'] as Map)['cash'], '100');
  });
  testWidgets('sale reviews exact cash and gold before one server post', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    await pumpTrade(tester, gateway, FinancialKind.sale);
    await beginTrade(tester);
    await tester.enterText(find.byKey(const Key('trade-name-0')), 'خاتم');
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
    await nextTrade(tester);
    await tester.dragUntilVisible(
      find.byKey(const Key('trade-tender-amount-0')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '4200.25',
    );
    if (find.byKey(const Key('trade-next')).evaluate().isNotEmpty) {
      await nextTrade(tester);
    }
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(find.text('4,200.25 جنيه'), findsWidgets);
    expect(find.text('1.830 جرام'), findsOneWidget);
    expect(gateway.keys, isEmpty);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(1));
    expect(gateway.pendingExistedAtPost, isTrue);
    expect(gateway.payloads.single['total_piastres'], '420025');
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(find.byKey(const Key('trade-confirm')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial purchase reviews paid cash, payable, and owned gold', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    await pumpTrade(tester, gateway, FinancialKind.purchase);
    await beginTrade(tester);
    await tester.enterText(find.byKey(const Key('trade-name-0')), 'سوار');
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '10.000');
    await nextTrade(tester);
    await tester.dragUntilVisible(
      find.byKey(const Key('trade-purchase-price')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.enterText(
      find.byKey(const Key('trade-purchase-price')),
      '60000',
    );
    await tester.enterText(
      find.byKey(const Key('trade-seller-name')),
      'تاجر تجريبي',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('trade-tender-amount-0')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '20000',
    );
    if (find.byKey(const Key('trade-next')).evaluate().isNotEmpty) {
      await nextTrade(tester);
    }
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('يبقى مستحقاً للبائع: 40,000'), findsOneWidget);
    expect(find.textContaining('تنتقل الملكية إلى المتجر'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payloads.single['purchase_obligation_piastres'], '4000000');
    expect(gateway.payloads.single['total_piastres'], '6000000');
  });

  testWidgets('scrap quick sale reviews scrap loss and split cash gain', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    await pumpTrade(tester, gateway, FinancialKind.scrapSale);
    await beginTrade(tester);
    expect(find.byKey(const Key('trade-count-0')), findsNothing);
    await tester.enterText(find.byKey(const Key('trade-name-0')), 'كسر');
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '0.375');
    await nextTrade(tester);
    await tester.dragUntilVisible(
      find.byKey(const Key('trade-tender-amount-0')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '100',
    );
    await tester.ensureVisible(find.byKey(const Key('trade-add-tender')));
    await tester.tap(find.byKey(const Key('trade-add-tender')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('trade-tender-amount-1')));
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-1')),
      '25.25',
    );
    if (find.byKey(const Key('trade-next')).evaluate().isNotEmpty) {
      await nextTrade(tester);
    }
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ينقص الكسر'), findsOneWidget);
    expect(find.text('0.375 جرام'), findsOneWidget);
    expect(gateway.payloads, isEmpty);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.payloads.single['kind'], 'scrap_sale');
    expect(gateway.payloads.single['total_piastres'], '12525');
    expect(gateway.pendingExistedAtPost, isTrue);
  });

  testWidgets('unknown outcome retries with the same key after absent status', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway()..result = const FinancialUnknown();
    await pumpTrade(tester, gateway, FinancialKind.expense);
    await tester.enterText(find.byKey(const Key('trade-description')), 'نقل');
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '10',
    );
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يؤكد الخادم العملية'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[0], gateway.keys[1]);
    expect(gateway.payloads[0], gateway.payloads[1]);
  });

  testWidgets(
    'explicit pricing is reviewed before the exact adjusted amount posts',
    (tester) async {
      final gateway = FakeFinancialGateway();
      await pumpTrade(tester, gateway, FinancialKind.sale);
      await beginTrade(tester);
      await tester.enterText(find.byKey(const Key('trade-name-0')), 'خاتم');
      await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
      await nextTrade(tester);
      await tester.dragUntilVisible(
        find.byKey(const Key('trade-price-details')),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.tap(find.byKey(const Key('trade-price-details')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('trade-tender-amount-0')),
        '1040.02',
      );
      for (final entry in {
        'trade-base-price': '1000.01',
        'trade-workmanship': '50.02',
        'trade-discount': '20.04',
        'trade-other-charges': '10.03',
        'trade-other-label': 'تغليف',
      }.entries) {
        await tester.dragUntilVisible(
          find.byKey(Key(entry.key)),
          find.byType(ListView),
          const Offset(0, -180),
        );
        await tester.enterText(find.byKey(Key(entry.key)), entry.value);
      }
      await nextTrade(tester);
      await tester.tap(find.byKey(const Key('trade-review')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('الخصم: 20.04 جنيه'),
        find.byType(ListView),
        const Offset(0, -180),
      );
      expect(find.text('المصنعية: 50.02 جنيه'), findsOneWidget);
      expect(gateway.payloads, isEmpty);
      await tester.tap(find.byKey(const Key('trade-confirm')));
      await tester.pumpAndSettle();
      expect(gateway.payloads.single['total_piastres'], '104002');
      expect(
        (gateway.payloads.single['pricing'] as Map)['discount_piastres'],
        '2004',
      );
      expect(gateway.pendingExistedAtPost, isTrue);
    },
  );
}

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_ledger_widget_test.dart' as ledger_fixtures;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'repair_widget_test.dart' as repair;

class LedgerGateway extends FakeFinancialGateway {
  var statusCalls = 0;
  var financialRetries = 0;
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      ledger_fixtures.confirmedLedger();
  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    statusCalls++;
    return const StatusAbsent();
  }

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    financialRetries++;
    return const FinancialRejected('invalid_input');
  }
}

Widget host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.light(),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
    'ledger repair recovery never calls the financial replay API or clears the envelope',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pending = PendingFinancialCommand(
        key: repair.key,
        kind: 'repair_intake',
        body: {
          'p_idempotency_key': repair.key,
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
      const store = PendingFinancialCommands();
      await store.save(repair.userId, repair.shopId, pending);
      final gateway = LedgerGateway();
      var opens = 0;
      await tester.pumpWidget(
        host(
          DailyLedgerScreen(
            shop: const ShopAccount(
              id: repair.shopId,
              name: 'متجر اختبار',
              role: 'owner',
              entitlement: ShopEntitlement.active,
            ),
            gateway: gateway,
            store: ledger_fixtures.MemoryStore(),
            userId: repair.userId,
            onToggleTheme: (_) async {},
            onOpenRepairs: () async {
              opens++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ledger-retry-pending')));
      await tester.tap(find.byKey(const Key('ledger-retry-pending')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(gateway.statusCalls, 0);
      expect(gateway.financialRetries, 0);
      expect(
        (await store.read(repair.userId, repair.shopId))!.body,
        pending.body,
      );
      expect(find.text('متابعة طلب الصيانة'), findsOneWidget);
    },
  );

  testWidgets('removing the owning workspace closes the repair route', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, _) => show
              ? ShopWorkspace(
                  shop: const ShopAccount(
                    id: repair.shopId,
                    name: 'متجر اختبار',
                    role: 'owner',
                    entitlement: ShopEntitlement.active,
                  ),
                  onSignOut: () async {},
                  onToggleTheme: (_) async {},
                  repairBuilder: (_) => RepairScreen(
                    gateway: repair.FakeRepairs(summary: repair.sample()),
                    store: repair.MemoryLocker(),
                    userId: repair.userId,
                    shopId: repair.shopId,
                    readOnly: false,
                  ),
                )
              : const Scaffold(body: Text('تسجيل الدخول')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-repairs')));
    await tester.pumpAndSettle();
    expect(find.text('عميل الإصلاح'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('عميل الإصلاح'), findsNothing);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

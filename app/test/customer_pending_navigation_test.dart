import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_widget_test.dart' as ledger_fixtures;
import 'debt_widget_test.dart' show shopId, userId;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

const key = 'd3000000-0000-4000-8000-000000000202';

class _LedgerGateway extends FakeFinancialGateway {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'ledger customer recovery opens customers and keeps the envelope',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pending = PendingFinancialCommand(
        key: key,
        kind: 'customer_create',
        body: {
          'p_idempotency_key': key,
          'p_payload': {
            'version': 1,
            'kind': 'customer_create',
            'display_name': 'عميل اختبار',
            'phones': [],
            'is_vip': false,
            'has_open_request': false,
          },
        },
      );
      const store = PendingFinancialCommands();
      await store.save(userId, shopId, pending);
      final gateway = _LedgerGateway();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          home: DailyLedgerScreen(
            shop: const ShopAccount(
              id: shopId,
              name: 'متجر اختبار',
              role: 'owner',
              entitlement: ShopEntitlement.active,
            ),
            gateway: gateway,
            store: ledger_fixtures.MemoryStore(),
            userId: userId,
            onToggleTheme: (_) async {},
            onOpenCustomers: () async {
              opens++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('متابعة طلب العميل'), findsOneWidget);
      expect(find.text('متابعة طلب الصيانة'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('ledger-retry-pending')));
      await tester.tap(find.byKey(const Key('ledger-retry-pending')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(gateway.statusCalls, 0);
      expect(gateway.financialRetries, 0);
      expect((await store.read(userId, shopId))!.body, pending.body);
    },
  );
}

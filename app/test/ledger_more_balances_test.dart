import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

class LiveMoreGateway extends FakeFinancialGateway {
  LiveMoreGateway(this.view);
  DailyLedgerView view;
  int reads = 0;

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    reads += 1;
    return view;
  }
}

class DeniedMoreGateway extends FakeFinancialGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    throw const LedgerReadException('forbidden');
  }
}

ShopAccount shop({String id = 'more-shop', String name = 'مجوهرات كذا'}) =>
    ShopAccount(
      id: id,
      name: name,
      role: 'owner',
      entitlement: ShopEntitlement.active,
    );

Future<void> pumpMore(
  WidgetTester tester, {
  required OpeningGateway gateway,
  ShopAccount? account,
  String userId = 'owner-1',
  Listenable? ticks,
  int refresh = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.dark(),
      home: ShopWorkspace(
        shop: account ?? shop(),
        gateway: gateway,
        store: MemoryStore(),
        userId: userId,
        refreshGeneration: refresh,
        syncTicks: ticks,
        onSignOut: () async {},
        onToggleTheme: (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'More loads live remaining metric and inventory from the gateway',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ticks = ChangeNotifier();
      final gateway = LiveMoreGateway(confirmedLedger());
      await pumpMore(tester, gateway: gateway, ticks: ticks);
      expect(find.textContaining('أهلاً مجوهرات كذا'), findsOneWidget);
      await tester.tap(find.byKey(const Key('workspace-nav-4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-metric-expense')), findsOneWidget);
      expect(find.byKey(const Key('more-inventory-scrap')), findsOneWidget);
      expect(gateway.reads, greaterThan(0));
      final before = gateway.reads;
      ticks.notifyListeners();
      await tester.pumpAndSettle();
      expect(gateway.reads, greaterThan(before));
      await tester.tap(find.byKey(const Key('more-inventory-scrap')));
      await tester.pumpAndSettle();
      expect(find.text('المخزون والكسر'), findsWidgets);
      await tester.tap(find.byKey(const Key('detail-close')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('More clears balances when access is lost', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpMore(tester, gateway: DeniedMoreGateway());
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more-balances-error')), findsOneWidget);
    expect(find.byKey(const Key('more-metric-expense')), findsNothing);
    expect(find.byKey(const Key('more-inventory-scrap')), findsNothing);
  });

  testWidgets('More remaining metric follows the saved shop layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'ledger_layout_more-shop': [
        'metric:expense',
        'metric:total_gold',
        'metric:sale',
        'metric:purchase',
        'metric:sale_gold',
        'metric:purchase_gold',
        'remaining:total_cash',
      ],
    });
    await pumpMore(tester, gateway: LiveMoreGateway(confirmedLedger()));
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more-metric-total_cash')), findsOneWidget);
    expect(find.byKey(const Key('more-cash-methods')), findsOneWidget);
    expect(find.byKey(const Key('more-metric-expense')), findsNothing);
  });
}

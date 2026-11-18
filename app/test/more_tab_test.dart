import 'package:eldafttar/src/features/audit_trail/domain/audit_trail.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

class _ConfirmedLedger extends FakeFinancialGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      confirmedLedger();
}

class _EmptyAudit implements AuditTrailGateway {
  @override
  Future<AuditTrailPage> list({
    AuditTrailFamily? family,
    DateTime? beforeAt,
    String? beforeId,
    int limit = 20,
  }) async => AuditTrailPage(
    entries: const [],
    nextCursorAt: null,
    nextCursorId: null,
    timeZone: 'Africa/Cairo',
    snapshotAt: DateTime.utc(2026, 11, 8),
  );
}

Widget _page(String title) => Scaffold(body: Text(title));

ShopAccount _shop({
  required String role,
  Set<ShopPermission> grants = const {},
}) => ShopAccount(
  id: 'shop',
  name: 'متجر الاختبار',
  role: role,
  entitlement: ShopEntitlement.active,
  grants: grants,
);

Future<void> _pump(
  WidgetTester tester, {
  required ShopAccount shop,
  Size size = const Size(390, 900),
  bool withPages = true,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ShopWorkspace(
          shop: shop,
          // A confirmed ledger with stock, scrap and cash, so a figure would
          // show if «المزيد» still read one.
          gateway: _ConfirmedLedger(),
          store: MemoryStore(),
          userId: 'owner-1',
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          analyticsBuilder: withPages ? (_) => _page('التحليلات') : null,
          traderBuilder: withPages ? (_) => _page('الحسابات') : null,
          repairBuilder: withPages ? (_) => _page('المرمات') : null,
          debtBuilder: withPages ? (_) => _page('النوتة') : null,
          closingStaffBuilder: withPages ? (_) => _page('فريق العد') : null,
          reportsBuilder: (_) => const Scaffold(body: Text('صفحة التقارير')),
          auditTrailGateway: withPages ? _EmptyAudit() : null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Owner feedback 2026-11-17 (handoff step 4): the old app's page names.
  testWidgets('المزيد names the pages «الحسابات» and «النوتة»', (tester) async {
    await _pump(tester, shop: _shop(role: 'owner'));
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    final traders = find.byKey(const Key('workspace-traders'));
    final debts = find.byKey(const Key('workspace-debts'));
    expect(
      find.descendant(of: traders, matching: find.text('الحسابات')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: debts, matching: find.text('النوتة')),
      findsOneWidget,
    );
    expect(find.text('التجار والأمانات'), findsNothing);
    expect(find.text('الديون'), findsNothing);
  });

  // Owner feedback 2026-11-17 (handoff step 4): «المزيد» lists pages and
  // settings only, in both themes.
  for (final brightness in Brightness.values) {
    testWidgets('المزيد shows no ledger or inventory figures ($brightness)', (
      tester,
    ) async {
      await _pump(
        tester,
        shop: _shop(role: 'owner'),
        brightness: brightness,
      );
      await tester.tap(find.byKey(const Key('workspace-nav-4')));
      await tester.pumpAndSettle();
      expect(find.text('الصفحات'), findsOneWidget);
      for (final gone in [
        'الأرقام والمخزون',
        'باقي أرقام الدفتر',
        'المخزون والكسر',
        'لا توجد أرصدة مؤكدة لهذا المحل.',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.byKey(const Key('more-inventory-scrap')), findsNothing);
      expect(find.byKey(const Key('more-cash-methods')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => '${widget.key}'.contains('more-metric-'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('owner sees every former drawer page and no menu', (
    tester,
  ) async {
    await _pump(tester, shop: _shop(role: 'owner'));
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('المزيد'), findsWidgets);
    expect(find.byIcon(Icons.grid_view_rounded), findsWidgets);
    for (final key in [
      'workspace-reports',
      'workspace-analytics',
      'workspace-traders',
      'workspace-repairs',
      'workspace-debts',
      'workspace-closing-staff',
      'workspace-audit-trail',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    for (final id in [0, 1, 2, 4]) {
      await tester.tap(find.byKey(Key('workspace-nav-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-menu')), findsNothing);
    }
  });

  testWidgets('employee without reports sees none of the moved pages', (
    tester,
  ) async {
    await _pump(tester, shop: _shop(role: 'employee'));
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    for (final key in [
      'workspace-reports',
      'workspace-analytics',
      'workspace-traders',
      'workspace-repairs',
      'workspace-debts',
      'workspace-closing-staff',
      'workspace-audit-trail',
    ]) {
      expect(find.byKey(Key(key)), findsNothing);
    }
    for (final id in [0, 1, 2, 4]) {
      await tester.tap(find.byKey(Key('workspace-nav-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-menu')), findsNothing);
    }
  });

  testWidgets('mobile reports opened from المزيد keep that tab selected', (
    tester,
  ) async {
    await _pump(tester, shop: _shop(role: 'owner'), withPages: false);
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-reports')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة التقارير'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(find.byKey(const Key('workspace-menu')), findsNothing);
  });
}

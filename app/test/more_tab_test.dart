import 'package:eldafttar/src/features/audit_trail/domain/audit_trail.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ShopWorkspace(
          shop: shop,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          analyticsBuilder: withPages ? (_) => _page('التحليلات') : null,
          traderBuilder: withPages ? (_) => _page('التجار') : null,
          repairBuilder: withPages ? (_) => _page('الصيانة') : null,
          debtBuilder: withPages ? (_) => _page('الديون') : null,
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

import 'package:eldafttar/src/features/audit_trail/domain/audit_trail.dart';
import 'package:eldafttar/src/features/audit_trail/presentation/audit_trail_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AuditTrailEntry entryOf(
  String id, {
  String label = 'بيع',
  AuditTrailFamily family = AuditTrailFamily.post,
  String? actor = 'موظف البيع',
  String sequence = '4',
}) => AuditTrailEntry(
  id: id,
  action: 'sale_confirmed',
  actionLabel: label,
  family: family,
  actorUserId: 'actor',
  actorDisplayName: actor,
  createdAt: DateTime.utc(2026, 10, 28, 11),
  createdAtShop: '2026-10-28 13:00:00',
  operationId: 'op-$id',
  shopSequence: sequence,
  businessDate: '2026-10-28',
  summary: 'تسلسل $sequence · 2026-10-28',
);

class FakeAuditTrailGateway implements AuditTrailGateway {
  FakeAuditTrailGateway({
    List<AuditTrailEntry>? first,
    List<AuditTrailEntry>? older,
  }) : first = first ?? [entryOf('row-1')],
       older = older ?? const [];

  List<AuditTrailEntry> first;
  List<AuditTrailEntry> older;
  AuditTrailFailure? failure;
  final List<({AuditTrailFamily? family, String? beforeId})> calls = [];

  @override
  Future<AuditTrailPage> list({
    AuditTrailFamily? family,
    DateTime? beforeAt,
    String? beforeId,
    int limit = 20,
  }) async {
    calls.add((family: family, beforeId: beforeId));
    final failed = failure;
    if (failed != null) throw AuditTrailException(failed);
    if (beforeId != null) {
      return AuditTrailPage(
        entries: older,
        nextCursorAt: null,
        nextCursorId: null,
        timeZone: 'Africa/Cairo',
        snapshotAt: DateTime.utc(2026, 10, 28, 16),
      );
    }
    return AuditTrailPage(
      entries: first,
      nextCursorAt: older.isEmpty ? null : DateTime.utc(2026, 10, 28, 11),
      nextCursorId: older.isEmpty ? null : 'cursor-older',
      timeZone: 'Africa/Cairo',
      snapshotAt: DateTime.utc(2026, 10, 28, 15),
    );
  }
}

Future<void> pumpAudit(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows rows, an unknown actor and no edit or delete action', (
    tester,
  ) async {
    final gateway = FakeAuditTrailGateway(
      first: [
        entryOf('row-1', label: 'حذف عملية', family: AuditTrailFamily.delete),
        entryOf(
          'row-2',
          actor: null,
          label: 'خصم مخزون',
          family: AuditTrailFamily.deduction,
        ),
      ],
    );
    await pumpAudit(tester, AuditTrailScreen(gateway: gateway));

    expect(find.text('سجل العمليات'), findsWidgets);
    expect(find.text('حذف عملية'), findsOneWidget);
    expect(find.text('الاسم غير متاح'), findsOneWidget);
    expect(find.textContaining('تسلسل 4'), findsWidgets);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(
      find.text('صفحة السجل للقراءة فقط. لا يغيّر عرض السجل أي رصيد أو عملية.'),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.text('حذف عملية'))),
      TextDirection.rtl,
    );
  });

  testWidgets('empty, retry and keyset load more stay honest', (tester) async {
    final gateway = FakeAuditTrailGateway(first: const []);
    gateway.failure = AuditTrailFailure.unavailable;
    await pumpAudit(tester, AuditTrailScreen(gateway: gateway));
    expect(find.byKey(const Key('audit-error')), findsOneWidget);
    expect(find.byKey(const Key('audit-empty')), findsNothing);

    gateway.failure = null;
    await tester.tap(find.byKey(const Key('audit-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('audit-empty')), findsOneWidget);

    gateway.first = [entryOf('row-1')];
    gateway.older = [entryOf('row-old', sequence: '1')];
    await tester.tap(find.byKey(const Key('audit-filter-post')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('audit-entry-row-1')), findsOneWidget);
    expect(find.byKey(const Key('audit-load-more')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('audit-load-more')));

    await tester.tap(find.byKey(const Key('audit-load-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('audit-entry-row-old')), findsOneWidget);
    expect(find.byKey(const Key('audit-load-more')), findsNothing);
    expect(gateway.calls.last.beforeId, 'cursor-older');
  });

  testWidgets(
    'access loss replaces the feed and a family filter is server-side',
    (tester) async {
      final gateway = FakeAuditTrailGateway();
      gateway.failure = AuditTrailFailure.accessLost;
      await pumpAudit(tester, AuditTrailScreen(gateway: gateway));
      expect(find.byKey(const Key('audit-access-loss')), findsOneWidget);
      expect(find.byKey(const Key('audit-load-more')), findsNothing);
      expect(find.byKey(const Key('audit-empty')), findsNothing);

      final live = FakeAuditTrailGateway(first: [entryOf('kept')]);
      await pumpAudit(
        tester,
        AuditTrailScreen(key: const Key('audit-filter-screen'), gateway: live),
      );
      expect(live.calls, isNotEmpty);
      await tester.tap(find.byKey(const Key('audit-filter-deduction')));
      await tester.pumpAndSettle();
      expect(live.calls.last.family, AuditTrailFamily.deduction);
      expect(live.calls.last.beforeId, isNull);
    },
  );

  testWidgets(
    'المزيد shows سجل العمليات for the owner and hides it from staff',
    (tester) async {
      final gateway = FakeAuditTrailGateway();
      await pumpAudit(
        tester,
        ShopWorkspace(
          shop: const ShopAccount(
            id: 'shop',
            name: 'متجر السجل',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          auditTrailGateway: gateway,
        ),
      );
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-audit-trail')), findsOneWidget);
      await tester.tap(find.byKey(const Key('workspace-audit-trail')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'صفحة السجل للقراءة فقط. لا يغيّر عرض السجل أي رصيد أو عملية.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('audit-entry-row-1')), findsOneWidget);

      await pumpAudit(
        tester,
        ShopWorkspace(
          shop: const ShopAccount(
            id: 'shop',
            name: 'متجر السجل',
            role: 'employee',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          auditTrailGateway: gateway,
        ),
      );
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-audit-trail')), findsNothing);
    },
  );
}

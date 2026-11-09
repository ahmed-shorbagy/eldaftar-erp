import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_date_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_archive_screen.dart';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shop = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _user = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _operation = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

class _Reports implements ReportGateway {
  @override
  Object? reportSession(String userId) => userId;

  @override
  Future<List<ReportDay>> reportDays(String userId, String shopId) async =>
      const [
        ReportDay('1', '2026-11-07', 'closed', '2026-11-07T08:00:00'),
        ReportDay('2', '2026-11-08', 'closed', '2026-11-08T09:30:00'),
        ReportDay('3', '2026-11-08', 'closed', '2026-11-08T18:00:00'),
        ReportDay('4', '2026-11-09', 'open', '2026-11-09T08:00:00'),
      ];

  @override
  Future<FinancialDayReport> financialDayReport(
    String userId,
    String shopId,
    String dayId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> storeReportPdf(
    String userId,
    FinancialDayReport report,
    Uint8List bytes,
  ) => throw UnimplementedError();
}

class _Dates implements LedgerDateGateway {
  String? requested;
  @override
  Future<LedgerDateSnapshot> readLedgerDate({
    required String userId,
    required String shopId,
    String? businessDate,
    String? beforeSequence,
  }) async {
    requested = businessDate;
    return LedgerDateSnapshot(
      shopId: shopId,
      businessDate: businessDate ?? '2026-11-08',
      serverDate: '2026-11-09',
      dayIds: const ['dddddddd-dddd-4ddd-8ddd-dddddddddddd'],
      summary: const LedgerDaySummary(
        salePiastres: '0',
        purchasePiastres: '0',
        expensePiastres: '0',
        saleCount: 0,
        purchaseCount: 0,
        expenseCount: 0,
      ),
      page: LedgerOperationPage(
        shopId: shopId,
        dayId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        direction: 'backward',
        limit: 20,
        hasMore: false,
        serverSequence: '1',
        snapshotSequence: '1',
        items: const [
          LedgerFeedLine(
            kind: 'sale',
            labelAr: 'بيع',
            operationId: _operation,
            actorDisplayName: 'مالك',
            occurredAt: '2026-11-08T07:00:00Z',
            occurredAtCairo: '2026-11-08T09:00:00',
            shopSequence: '2',
          ),
        ],
      ),
    );
  }
}

class _Money implements FinancialGateway {
  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {
    'operation_id': operationId,
    'kind': 'sale',
    'payload': <String, Object?>{},
  };

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) => throw UnimplementedError();

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) =>
      throw UnimplementedError();

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'closed days are listed once, newest first, and open a read-only day',
    (tester) async {
      final dates = _Dates();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          theme: AppTheme.light(),
          home: LedgerArchiveScreen(
            reportGateway: _Reports(),
            dateGateway: dates,
            financialGateway: _Money(),
            userId: _user,
            shopId: _shop,
            canRead: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger-archive-2026-11-09')), findsNothing);
      expect(
        find.byKey(const Key('ledger-archive-2026-11-08')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ledger-archive-2026-11-07')),
        findsOneWidget,
      );
      expect(find.text('مقفول · فُتح 18:00'), findsOneWidget);
      final tiles = find.byType(ListTile);
      expect(
        tester.widget<ListTile>(tiles.at(0)).key,
        const Key('ledger-archive-2026-11-08'),
      );
      await tester.tap(find.byKey(const Key('ledger-archive-2026-11-08')));
      await tester.pumpAndSettle();
      expect(find.text('دفتر الأحد 8 نوفمبر 2026'), findsOneWidget);
      expect(dates.requested, '2026-11-08');
      await tester.tap(find.text('بيع'));
      await tester.pumpAndSettle();
      expect(find.text('تعديل'), findsNothing);
      expect(find.text('مسح العملية'), findsNothing);
    },
  );

  testWidgets('initialDate opens that closed day directly', (tester) async {
    final dates = _Dates();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: LedgerArchiveScreen(
          reportGateway: _Reports(),
          dateGateway: dates,
          financialGateway: _Money(),
          userId: _user,
          shopId: _shop,
          canRead: () => true,
          initialDate: '2026-11-07',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('دفتر السبت 7 نوفمبر 2026'), findsOneWidget);
    expect(dates.requested, '2026-11-07');
  });

  testWidgets(
    'the archive link is on more for an owner and hidden without reports',
    (tester) async {
      Future<void> pump(ShopAccount shop) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            home: ShopWorkspace(
              shop: shop,
              onSignOut: () async {},
              onToggleTheme: (_) async {},
              ledgerArchiveBuilder: (_) => const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('workspace-nav-4')));
        await tester.pumpAndSettle();
      }

      await pump(
        const ShopAccount(
          id: _shop,
          name: 'متجر',
          role: 'owner',
          entitlement: ShopEntitlement.active,
        ),
      );
      expect(find.byKey(const Key('workspace-ledger-archive')), findsOneWidget);
      await pump(
        const ShopAccount(
          id: _shop,
          name: 'متجر',
          role: 'employee',
          entitlement: ShopEntitlement.active,
        ),
      );
      expect(find.byKey(const Key('workspace-ledger-archive')), findsNothing);
    },
  );
}

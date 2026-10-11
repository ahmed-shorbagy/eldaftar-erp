import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_ticks.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingOperationGateway implements FinancialGateway {
  int loads = 0;
  String label = 'عملية أولى';

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async {
    loads++;
    return {
      'shop_sequence': '1',
      'actor_display_name': label,
      'payload': const <String, Object?>{},
    };
  }

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(state: 'open');

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => const FinancialUnknown();
}

void main() {
  testWidgets(
    'open invoice detail refetches from ticks without leaving the route',
    (tester) async {
      final gateway = CountingOperationGateway();
      final ticks = ShopSyncTicks();
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
          home: FinancialOperationScreen(
            gateway: gateway,
            userId: 'owner-1',
            syncTicks: ticks,
            line: const LedgerFeedLine(
              kind: 'sale',
              labelAr: 'بيع',
              operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              actorDisplayName: 'المالك',
              occurredAt: '2026-10-04T08:00:00Z',
              occurredAtCairo: '2026-10-04 10:00',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('عملية أولى'), findsOneWidget);
      expect(gateway.loads, 1);
      gateway.label = 'عملية بعد المزامنة';
      ticks.apply({ShopSyncScope.invoice});
      await tester.pumpAndSettle();
      expect(gateway.loads, 2);
      expect(find.textContaining('عملية بعد المزامنة'), findsOneWidget);
      expect(find.text('بيع'), findsWidgets);
    },
  );
}

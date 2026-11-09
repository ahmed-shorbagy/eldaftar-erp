import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/pending_invoice_sends_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Invoices implements FinancialGateway, InvoiceDispatchGateway {
  _Invoices(this.page);
  final PendingInvoicePage page;

  @override
  Future<PendingInvoicePage> pendingInvoiceSends({
    required String callerUserId,
    int? beforeSequence,
  }) async => page;

  @override
  Future<InvoiceDispatchState> dispatchState({
    required String callerUserId,
    required String operationId,
  }) => throw UnimplementedError();

  @override
  Future<FinancialCommandResult> confirmWhatsappSend({
    required String callerUserId,
    required String operationId,
    required String idempotencyKey,
  }) => throw UnimplementedError();

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
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
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

Future<void> _pump(WidgetTester tester, PendingInvoicePage page) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: PendingInvoiceSendsScreen(
          gateway: _Invoices(page),
          userId: 'owner',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending invoices show the open-day sale and hide a purchase', (
    tester,
  ) async {
    await _pump(
      tester,
      PendingInvoicePage(const [
        PendingInvoice(
          operationId: '11111111-1111-4111-8111-111111111111',
          kind: 'sale',
          shopSequence: '3',
          occurredAtCairo: '2026-11-09T10:00:00',
          customerName: 'عميل البيع',
        ),
        PendingInvoice(
          operationId: '22222222-2222-4222-8222-222222222222',
          kind: 'purchase',
          shopSequence: '4',
          occurredAtCairo: '2026-11-09T11:00:00',
          customerName: 'تاجر الشراء',
        ),
      ], null),
    );
    expect(find.textContaining('بيع رقم 3'), findsOneWidget);
    expect(find.textContaining('شراء'), findsNothing);
    expect(find.textContaining('تاجر الشراء'), findsNothing);
    expect(
      find.text('فواتير البيع غير المرسلة في اليوم المفتوح فقط.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty pending page uses the open-day empty text', (
    tester,
  ) async {
    await _pump(tester, PendingInvoicePage(const [], null));
    expect(
      find.text('لا توجد فواتير بيع معلقة في اليوم المفتوح.'),
      findsOneWidget,
    );
  });
}

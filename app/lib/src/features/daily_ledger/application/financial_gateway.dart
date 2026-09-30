import '../domain/financial_draft.dart';
import 'pending_financial_command.dart';

sealed class FinancialCommandResult {
  const FinancialCommandResult();
}

final class FinancialCommitted extends FinancialCommandResult {
  const FinancialCommitted(this.operationId, {required this.replayed});
  final String operationId;
  final bool replayed;
}

final class FinancialRejected extends FinancialCommandResult {
  const FinancialRejected(this.code);
  final String code;
}

final class FinancialUnknown extends FinancialCommandResult {
  const FinancialUnknown();
}

final class FinancialCountMismatch extends FinancialCommandResult {
  const FinancialCountMismatch(this.expectedCounts, this.dayVersion);
  final Map<String, Object?> expectedCounts;
  final int dayVersion;
}

final class FinancialDayState {
  const FinancialDayState({
    required this.state,
    this.dayId,
    this.businessDate,
    this.dayVersion,
    this.counts,
  });

  final String state;
  final String? dayId;
  final String? businessDate;
  final int? dayVersion;
  final Map<String, Object?>? counts;

  bool get isOpen => state == 'open';
  bool get isClosed => state == 'closed';
}

abstract class FinancialGateway {
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  });
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  });

  Future<FinancialDayState> dayState({required String callerUserId});

  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  });

  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  });

  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  });
}

final class InvoiceDispatchState {
  const InvoiceDispatchState({required this.ownerConfirmed, this.confirmedAt});
  final bool ownerConfirmed;
  final DateTime? confirmedAt;
}

final class PendingInvoice {
  const PendingInvoice({
    required this.operationId,
    required this.kind,
    required this.shopSequence,
    required this.occurredAtCairo,
    required this.customerName,
  });
  final String operationId;
  final String kind;
  final String shopSequence;
  final String occurredAtCairo;
  final String customerName;
}

final class PendingInvoicePage {
  const PendingInvoicePage(this.items, this.nextBeforeSequence);
  final List<PendingInvoice> items;
  final int? nextBeforeSequence;
}

abstract class InvoiceDispatchGateway {
  Future<PendingInvoicePage> pendingInvoiceSends({
    required String callerUserId,
    int? beforeSequence,
  });
  Future<InvoiceDispatchState> dispatchState({
    required String callerUserId,
    required String operationId,
  });

  Future<FinancialCommandResult> confirmWhatsappSend({
    required String callerUserId,
    required String operationId,
    required String idempotencyKey,
  });
}

abstract class PurchaseSettlementGateway {
  Future<FinancialCommandResult> settlePurchaseCash({
    required String callerUserId,
    required String idempotencyKey,
    required String purchaseOperationId,
    required List<Map<String, Object?>> tenders,
  });
}

abstract class CashTransferGateway {
  Future<FinancialCommandResult> transferCash({
    required String callerUserId,
    required String idempotencyKey,
    required String fromMethod,
    required String toMethod,
    required String amountPiastres,
    required String note,
  });
}

abstract class ScrapToStockGateway {
  Future<FinancialCommandResult> convertScrapToStock({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  });
}

abstract class LinkedReturnGateway {
  Future<FinancialCommandResult> returnOperation({
    required String callerUserId,
    required String idempotencyKey,
    required String originalOperationId,
    required String note,
  });
}

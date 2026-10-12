import '../../daily_ledger/application/pending_financial_command.dart';

class RepairReadException implements Exception {
  const RepairReadException([this.code]);
  final String? code;

  @override
  String toString() => 'RepairReadException($code)';
}

sealed class RepairRpcResult {
  const RepairRpcResult();
}

final class RepairRpcCommitted extends RepairRpcResult {
  const RepairRpcCommitted({
    required this.repairId,
    required this.replayed,
    required this.result,
  });

  final String repairId;
  final bool replayed;
  final Map<String, Object?> result;
}

final class RepairRpcRejected extends RepairRpcResult {
  const RepairRpcRejected(this.code);
  final String code;
}

final class RepairRpcUnknown extends RepairRpcResult {
  const RepairRpcUnknown();
}

sealed class RepairRemoteStatus {
  const RepairRemoteStatus();
}

final class RepairRemoteCompleted extends RepairRemoteStatus {
  const RepairRemoteCompleted({required this.repairId, required this.kind});
  final String repairId;
  final String kind;
}

final class RepairRemoteAbsent extends RepairRemoteStatus {
  const RepairRemoteAbsent();
}

final class RepairRemoteUnknown extends RepairRemoteStatus {
  const RepairRemoteUnknown();
}

final class RepairRemoteRejected extends RepairRemoteStatus {
  const RepairRemoteRejected(this.code);
  final String code;
}

final class RepairCashMethod {
  const RepairCashMethod({required this.method, required this.balancePiastres});
  final String method;
  final BigInt balancePiastres;
}

final class RepairDayContext {
  const RepairDayContext({
    required this.state,
    this.dayId,
    this.businessDate,
    this.dayVersion,
  });

  final String state;
  final String? dayId;
  final String? businessDate;
  final BigInt? dayVersion;

  bool get isOpen => state == 'open' && dayId != null && dayVersion != null;
}

final class RepairContext {
  const RepairContext({
    required this.timeZone,
    required this.day,
    required this.cashMethods,
  });

  final String timeZone;
  final RepairDayContext day;
  final List<RepairCashMethod> cashMethods;
}

final class RepairSummary {
  const RepairSummary({
    required this.id,
    required this.status,
    required this.recordVersion,
    required this.customerName,
    required this.customerPhone,
    required this.itemDescription,
    required this.measuredMilligrams,
    required this.karat,
    required this.issue,
    required this.custodyHeld,
    required this.estimatedFeePiastres,
    required this.finalFeePiastres,
    required this.collectedPiastres,
    required this.outstandingPiastres,
    required this.intakeAt,
    required this.intakeAtShop,
  });

  final String id;
  final String status;
  final BigInt recordVersion;
  final String customerName;
  final String customerPhone;
  final String itemDescription;
  final BigInt measuredMilligrams;
  final int karat;
  final String issue;
  final bool custodyHeld;
  final BigInt? estimatedFeePiastres;
  final BigInt? finalFeePiastres;
  final BigInt collectedPiastres;
  final BigInt outstandingPiastres;
  final String intakeAt;
  final String intakeAtShop;
}

final class RepairPage {
  const RepairPage({required this.items, this.nextCursor});
  final List<RepairSummary> items;
  final String? nextCursor;
}

final class RepairEventView {
  const RepairEventView({
    required this.id,
    required this.eventType,
    required this.actorUserId,
    required this.actorDisplayName,
    required this.createdAt,
    required this.createdAtShop,
  });

  final String id;
  final String eventType;
  final String actorUserId;
  final String actorDisplayName;
  final String createdAt;
  final String createdAtShop;
}

final class RepairCustodyView {
  const RepairCustodyView({
    required this.id,
    required this.direction,
    required this.measuredMilligrams,
    required this.karat,
    required this.createdAtShop,
  });

  final String id;
  final String direction;
  final BigInt measuredMilligrams;
  final int karat;
  final String createdAtShop;
}

final class RepairDetail {
  const RepairDetail({
    required this.summary,
    required this.intakeNotes,
    required this.financialOperationId,
    required this.cancellationReason,
    required this.archivedFromStatus,
    required this.intakeActorUserId,
    required this.timeZone,
    required this.events,
    required this.custodyEvents,
  });

  final RepairSummary summary;
  final String intakeNotes;
  final String? financialOperationId;
  final String? cancellationReason;
  final String? archivedFromStatus;
  final String intakeActorUserId;
  final String timeZone;
  final List<RepairEventView> events;
  final List<RepairCustodyView> custodyEvents;
}

abstract class RepairGateway {
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  });

  Future<RepairRemoteStatus> commandStatus({
    required String callerUserId,
    required String idempotencyKey,
  });

  Future<RepairContext> context({required String callerUserId});

  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  });

  Future<RepairDetail> detail({
    required String callerUserId,
    required String repairId,
  });
}

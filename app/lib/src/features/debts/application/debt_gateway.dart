import '../../daily_ledger/application/pending_financial_command.dart';
import '../domain/debt_rules.dart';

class DebtReadException implements Exception {
  const DebtReadException([this.code]);
  final String? code;

  @override
  String toString() => 'DebtReadException($code)';
}

sealed class DebtRpcResult {
  const DebtRpcResult();
}

final class DebtRpcCommitted extends DebtRpcResult {
  const DebtRpcCommitted({
    required this.sourceId,
    required this.sourceKind,
    required this.commandKind,
    required this.replayed,
    required this.effect,
    required this.displayStatus,
    required this.original,
    required this.settled,
    required this.remaining,
    required this.ledgerEffect,
    required this.operationId,
    required this.result,
  });

  final String sourceId;
  final String sourceKind;
  final String commandKind;
  final bool replayed;
  final DebtEffect effect;
  final String displayStatus;
  final BigInt original;
  final BigInt settled;
  final BigInt remaining;
  BigInt get cancelled => original - settled - remaining;
  final String ledgerEffect;
  final String? operationId;
  final Map<String, Object?> result;
}

final class DebtRpcRejected extends DebtRpcResult {
  const DebtRpcRejected(this.code);
  final String code;
}

final class DebtRpcUnknown extends DebtRpcResult {
  const DebtRpcUnknown();
}

sealed class DebtRemoteStatus {
  const DebtRemoteStatus();
}

final class DebtRemoteCompleted extends DebtRemoteStatus {
  const DebtRemoteCompleted({required this.committed});
  final DebtRpcCommitted committed;
  String get sourceId => committed.sourceId;
  String get sourceKind => committed.sourceKind;
  String get kind => committed.commandKind;
}

final class DebtRemoteAbsent extends DebtRemoteStatus {
  const DebtRemoteAbsent();
}

final class DebtRemoteUnknown extends DebtRemoteStatus {
  const DebtRemoteUnknown();
}

final class DebtRemoteRejected extends DebtRemoteStatus {
  const DebtRemoteRejected(this.code);
  final String code;
}

final class DebtCashMethod {
  const DebtCashMethod({required this.method, required this.balancePiastres});
  final String method;
  final BigInt balancePiastres;
}

final class DebtDayContext {
  const DebtDayContext({
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

final class DebtLot {
  const DebtLot({
    required this.id,
    required this.category,
    required this.karat,
    required this.displayName,
    required this.milligrams,
    required this.count,
    required this.tracksCount,
  });

  final String id;
  final String category;
  final int karat;
  final String displayName;
  final BigInt milligrams;
  final BigInt? count;
  final bool tracksCount;

  bool get scrap => !tracksCount;
}

final class DebtContext {
  const DebtContext({
    required this.timeZone,
    required this.day,
    required this.cashMethods,
    required this.lots,
  });

  final String timeZone;
  final DebtDayContext day;
  final List<DebtCashMethod> cashMethods;
  final List<DebtLot> lots;
}

final class DebtSummary {
  const DebtSummary({
    required this.debtKey,
    required this.sourceKind,
    required this.sourceId,
    required this.direction,
    required this.unit,
    required this.karat,
    required this.partyName,
    required this.contactPhone,
    required this.reason,
    required this.externalReference,
    required this.original,
    required this.settled,
    required this.remaining,
    required this.displayStatus,
    required this.recordVersion,
    required this.createdAt,
    required this.createdAtShop,
  });

  final String debtKey;
  final DebtSourceKind sourceKind;
  final String sourceId;
  final DebtDirection direction;
  final DebtUnit unit;
  final int? karat;
  final String partyName;
  final String? contactPhone;
  final String reason;
  final String? externalReference;
  final BigInt original;
  final BigInt settled;
  final BigInt remaining;
  BigInt get cancelled => original - settled - remaining;
  final String displayStatus;
  final BigInt? recordVersion;
  final String createdAt;
  final String createdAtShop;
}

final class DebtPage {
  const DebtPage({
    required this.items,
    required this.nextCursor,
    required this.timeZone,
  });
  final List<DebtSummary> items;
  final String? nextCursor;
  final String timeZone;
}

final class DebtHistoryEntry {
  const DebtHistoryEntry({
    required this.id,
    required this.at,
    required this.atShop,
    required this.eventType,
    required this.kind,
    required this.label,
    required this.payload,
    this.actorUserId,
    this.actorDisplayName,
  });

  final String id;
  final String at;
  final String atShop;
  final String eventType;
  final String kind;
  final String label;
  final Map<String, Object?> payload;
  final String? actorUserId;
  final String? actorDisplayName;
}

final class DebtDetail {
  const DebtDetail({
    required this.summary,
    required this.timeZone,
    required this.canSettle,
    required this.canCancel,
    required this.canArchive,
    required this.noLedgerAllowed,
    required this.history,
  });

  final DebtSummary summary;
  final String timeZone;
  final bool canSettle;
  final bool canCancel;
  final bool canArchive;
  final bool noLedgerAllowed;
  final List<DebtHistoryEntry> history;
}

abstract class DebtGateway {
  Future<DebtRpcResult> submitCommand({
    required String callerUserId,
    required PendingFinancialCommand command,
  });

  Future<DebtRemoteStatus> readCommandStatus({
    required String callerUserId,
    required String idempotencyKey,
  });

  Future<DebtContext> readContext({required String callerUserId});

  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  });

  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  });
}

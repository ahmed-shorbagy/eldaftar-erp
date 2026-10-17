import '../../daily_ledger/application/pending_financial_command.dart';
import '../domain/debt_rules.dart';
import 'debt_due_gateway.dart';

final class DebtNativeRow {
  const DebtNativeRow({
    required this.due,
    required this.time,
    required this.version,
    required this.freshness,
    required this.triggerAt,
    required this.timeValid,
  });
  final DebtDueRow due;
  final String? time;
  final BigInt version;
  final String freshness;
  final DateTime? triggerAt;
  final bool timeValid;
  Map<String, Object?> payload(String? time) => {
    'version': 1,
    'kind': 'debt_native',
    'source_kind': due.summary.sourceKind.wire,
    'source_id': due.summary.sourceId,
    'reminder_time': time,
    'expected_native_version': version.toString(),
    'expected_freshness': freshness,
  };
}

final class DebtNativeEvent {
  const DebtNativeEvent({
    required this.id,
    required this.oldTime,
    required this.newTime,
    required this.actor,
    required this.at,
    required this.version,
    required this.zone,
    required this.date,
    required this.atShop,
  });
  final String id, actor, zone, atShop;
  final String? oldTime, newTime, date;
  final DateTime at;
  final BigInt version;
}

final class DebtNativeDetail {
  const DebtNativeDetail({
    required this.row,
    required this.canWrite,
    required this.at,
    required this.history,
  });
  final DebtNativeRow row;
  final bool canWrite;
  final DateTime at;
  final List<DebtNativeEvent> history;
}

final class DebtNativePage {
  const DebtNativePage({
    required this.items,
    required this.shopId,
    required this.at,
    required this.freshness,
    required this.total,
    required this.offset,
    required this.cursor,
  });
  final List<DebtScheduledIntent> items;
  final String shopId, freshness;
  final DateTime at;
  final int total, offset;
  final String? cursor;
}

/// Narrow scheduling feed: no party, contact, amount, unit, or karat.
final class DebtScheduledIntent {
  const DebtScheduledIntent({
    required this.sourceKind,
    required this.sourceId,
    required this.freshness,
    required this.triggerAt,
    required this.timeValid,
  });
  final DebtSourceKind sourceKind;
  final String sourceId, freshness;
  final DateTime? triggerAt;
  final bool timeValid;
  String get key => '${sourceKind.wire}:$sourceId';
}

final class DebtNativeReceipt {
  const DebtNativeReceipt({
    required this.shopId,
    required this.key,
    required this.sourceKind,
    required this.sourceId,
    required this.payload,
    required this.time,
    required this.version,
    required this.actorId,
    required this.at,
    required this.freshness,
    required this.replayed,
  });
  final String shopId, key, sourceKind, sourceId, actorId, freshness;
  final Map<String, Object?> payload;
  final String? time;
  final BigInt version;
  final DateTime at;
  final bool replayed;
}

final class DebtNativeTransport {
  const DebtNativeTransport({this.receipt, this.error, this.absent = false});
  final DebtNativeReceipt? receipt;
  final String? error;
  final bool absent;
}

abstract interface class DebtNativeGateway {
  Object? nativeSession(String userId);
  Future<DebtNativeDetail> readNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  });
  Future<DebtNativePage> readNativeQueue({
    required String userId,
    required String shopId,
    required String? cursor,
  });
  Future<DebtNativeReview> reviewNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
    required String? time,
  });
  Future<DebtNativeTransport> sendNative({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  });
  Future<DebtNativeTransport> nativeStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  });
}

final class DebtNativeReview {
  const DebtNativeReview(this.detail, this.time, this.triggerAt);
  final DebtNativeDetail detail;
  final String? time;
  final DateTime? triggerAt;
}

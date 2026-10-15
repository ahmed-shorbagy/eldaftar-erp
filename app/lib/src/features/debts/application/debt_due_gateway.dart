import '../../daily_ledger/application/pending_financial_command.dart';
import '../domain/debt_calendar_date.dart';
import '../domain/debt_rules.dart';
import 'debt_gateway.dart';

final class DebtDueRow {
  const DebtDueRow({
    required this.summary,
    required this.shopId,
    required this.date,
    required this.version,
    required this.state,
    required this.timeZone,
    required this.localDate,
    required this.freshness,
    this.updatedAt,
    this.actorId,
  });
  final DebtSummary summary;
  final String shopId, timeZone, freshness;
  final DebtCalendarDate? date;
  final DebtCalendarDate localDate;
  final BigInt version;
  final String? state, actorId;
  final DateTime? updatedAt;
}

final class DebtDueEvent {
  const DebtDueEvent({
    required this.id,
    required this.oldDate,
    required this.newDate,
    required this.version,
    required this.actorId,
    required this.actorName,
    required this.at,
    required this.atShop,
  });
  final String id, actorId, actorName, atShop;
  final DebtCalendarDate? oldDate, newDate;
  final BigInt version;
  final DateTime at;
}

final class DebtDueDetail {
  const DebtDueDetail({
    required this.row,
    required this.canSchedule,
    required this.snapshotAt,
    required this.snapshotAtShop,
    required this.history,
  });
  final DebtDueRow row;
  final bool canSchedule;
  final DateTime snapshotAt;
  final String snapshotAtShop;
  final List<DebtDueEvent> history;
  Map<String, Object?> payload(DebtCalendarDate? date) => {
    'version': 1,
    'kind': 'debt_due',
    'source_kind': row.summary.sourceKind.wire,
    'source_id': row.summary.sourceId,
    'due_date': date?.wire,
    'expected_due_version': row.version.toString(),
    'expected_freshness': row.freshness,
  };
}

final class DebtReminderPage {
  const DebtReminderPage({
    required this.items,
    required this.shopId,
    required this.timeZone,
    required this.localDate,
    required this.snapshotAt,
    required this.snapshotAtShop,
    required this.freshness,
    required this.total,
    required this.offset,
    required this.nextCursor,
  });
  final List<DebtDueRow> items;
  final String shopId, timeZone, snapshotAtShop, freshness;
  final DebtCalendarDate localDate;
  final DateTime snapshotAt;
  final int total, offset;
  final String? nextCursor;
}

final class DebtDueReceipt {
  const DebtDueReceipt({
    required this.shopId,
    required this.key,
    required this.sourceKind,
    required this.sourceId,
    required this.payload,
    required this.date,
    required this.version,
    required this.actorId,
    required this.at,
    required this.freshness,
    required this.replayed,
  });
  final String shopId, key, sourceKind, sourceId, actorId, freshness;
  final Map<String, Object?> payload;
  final DebtCalendarDate? date;
  final BigInt version;
  final DateTime at;
  final bool replayed;
}

final class DebtDueTransport {
  const DebtDueTransport({this.receipt, this.error, this.absent = false});
  final DebtDueReceipt? receipt;
  final String? error;
  final bool absent;
}

abstract interface class DebtDueGateway {
  Object? dueSession(String userId);
  Future<DebtDueDetail> readDue({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  });
  Future<DebtReminderPage> readReminders({
    required String userId,
    required String shopId,
    required String query,
    required String filter,
    required String? cursor,
  });
  Future<DebtDueTransport> sendDue({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  });
  Future<DebtDueTransport> dueStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  });
}

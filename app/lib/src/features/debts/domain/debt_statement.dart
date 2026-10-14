import 'debt_rules.dart';
import '../../daily_ledger/domain/postgres_integer.dart';

enum DebtStatementEventType {
  declared,
  posted,
  settled,
  linkedSettlement,
  cancelled,
  linkedReturn,
  archived,
}

final class DebtStatementEvent {
  const DebtStatementEvent({
    required this.id,
    required this.at,
    required this.atShop,
    required this.type,
    required this.label,
    required this.actorId,
    required this.actorName,
    required this.actorNameCurrent,
    required this.operationId,
    required this.amount,
    required this.cancelled,
    required this.cash,
    required this.gold,
    required this.reason,
    required this.movesLedger,
  });
  final String id, atShop, label, actorId, actorName;
  final DateTime at;
  final DebtStatementEventType type;
  final bool actorNameCurrent, movesLedger;
  final String? operationId, reason;
  final BigInt amount, cancelled, cash, gold;
}

/// Complete confirmed bookkeeping evidence, independent of Flutter and storage.
final class DebtStatement {
  DebtStatement({
    required this.shopId,
    required this.shopName,
    required this.shopPhone,
    required this.timeZone,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceSequence,
    required this.direction,
    required this.unit,
    required this.karat,
    required this.partyName,
    required this.contactPhone,
    required this.reason,
    required this.reference,
    required this.original,
    required this.settled,
    required this.cancelled,
    required this.remaining,
    required this.status,
    required this.snapshotAt,
    required this.snapshotAtShop,
    required this.freshness,
    required List<DebtStatementEvent> history,
  }) : history = List.unmodifiable(history) {
    validate();
  }
  final String shopId, shopName, timeZone, sourceId, partyName, reason, status;
  final String snapshotAtShop, freshness;
  final String? shopPhone, sourceSequence, contactPhone, reference;
  final DebtSourceKind sourceKind;
  final DebtDirection direction;
  final DebtUnit unit;
  final int? karat;
  final BigInt original, settled, cancelled, remaining;
  final DateTime snapshotAt;
  final List<DebtStatementEvent> history;

  void validate() {
    void reject() => throw const FormatException('debt_statement');
    if (shopName.isEmpty ||
        partyName.isEmpty ||
        reason.isEmpty ||
        timeZone.isEmpty ||
        !snapshotAt.isUtc ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(freshness) ||
        !const {'open', 'settled', 'cancelled', 'archived'}.contains(status) ||
        (unit == DebtUnit.gold) != (karat != null) ||
        (karat != null && !const {14, 18, 21, 22, 24}.contains(karat)) ||
        (sourceKind.isSource && direction != DebtDirection.shopOwes) ||
        (sourceKind == DebtSourceKind.purchaseCashPayable &&
            unit != DebtUnit.money) ||
        (sourceKind == DebtSourceKind.goldObligation &&
            unit != DebtUnit.gold)) {
      reject();
    }
    for (final n in [original, settled, cancelled, remaining]) {
      if (n < BigInt.zero || !PostgresInteger.fits(n)) reject();
    }
    if (original <= BigInt.zero ||
        original != settled + cancelled + remaining) {
      reject();
    }
    var origin = BigInt.zero,
        payments = BigInt.zero,
        cancellations = BigInt.zero;
    if ((status == 'archived') !=
            history.any((e) => e.type == DebtStatementEventType.archived) ||
        history.where((e) => e.type == DebtStatementEventType.archived).length >
            1 ||
        (sourceSequence != null &&
            (BigInt.tryParse(sourceSequence!) ?? BigInt.zero) <= BigInt.zero)) {
      reject();
    }
    var originCount = 0;
    DateTime? previous;
    final ids = <String>{}, operations = <String>{};
    for (final e in history) {
      if (!ids.add(e.id) ||
          !e.at.isUtc ||
          e.at.isAfter(snapshotAt) ||
          (previous != null && e.at.isBefore(previous)) ||
          e.actorId.isEmpty ||
          e.actorName.isEmpty ||
          e.label.isEmpty ||
          e.amount < BigInt.zero ||
          e.cancelled < BigInt.zero ||
          [
            e.amount,
            e.cancelled,
            e.cash,
            e.gold,
          ].any((n) => !PostgresInteger.fits(n))) {
        reject();
      }
      previous = e.at;
      if ((e.type == DebtStatementEventType.declared ||
              e.type == DebtStatementEventType.archived ||
              e.type == DebtStatementEventType.cancelled) &&
          (e.cash != BigInt.zero ||
              e.gold != BigInt.zero ||
              e.movesLedger ||
              e.operationId != null)) {
        reject();
      }
      if (!sourceKind.isSource &&
          e.type == DebtStatementEventType.settled &&
          e.movesLedger != (e.operationId != null)) {
        reject();
      }
      if (unit == DebtUnit.money && e.gold != BigInt.zero) {
        reject();
      }
      if (e.operationId != null && !operations.add(e.operationId!)) reject();
      if (e.type == DebtStatementEventType.declared ||
          e.type == DebtStatementEventType.posted) {
        origin += e.amount;
        originCount++;
      }
      if (e.type == DebtStatementEventType.settled ||
          e.type == DebtStatementEventType.linkedSettlement) {
        if (e.amount == BigInt.zero || e.cancelled != BigInt.zero) reject();
        payments += e.amount;
      }
      if (e.cancelled > BigInt.zero &&
          e.type != DebtStatementEventType.cancelled &&
          e.type != DebtStatementEventType.linkedReturn) {
        reject();
      }
      cancellations += e.cancelled;
    }
    if (originCount != 1 ||
        origin != original ||
        payments != settled ||
        cancellations != cancelled) {
      reject();
    }
    if (sourceKind.isSource &&
        (history.first.type != DebtStatementEventType.posted ||
            history.first.operationId != sourceId ||
            sourceSequence == null)) {
      reject();
    }
    if (!sourceKind.isSource &&
        history.first.type != DebtStatementEventType.declared) {
      reject();
    }
  }
}

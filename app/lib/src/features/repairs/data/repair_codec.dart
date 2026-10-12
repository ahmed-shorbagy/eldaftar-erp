import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/repair_gateway.dart';

Map<String, Object?> _map(Object? raw) {
  if (raw is! Map) throw const FormatException('repair');
  return Map<String, Object?>.from(raw);
}

String _text(Object? raw) {
  if (raw is! String) throw const FormatException('repair');
  return raw;
}

String _uuid(Object? raw) {
  final value = _text(raw);
  if (!isUuid(value)) throw const FormatException('repair');
  return value;
}

BigInt _money(Object? raw, {bool allowZero = true}) {
  if (raw is! String || !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(raw)) {
    throw const FormatException('repair');
  }
  final value = BigInt.parse(raw);
  if (!PostgresInteger.fits(value) || (!allowZero && value == BigInt.zero)) {
    throw const FormatException('repair');
  }
  return value;
}

BigInt? _optionalMoney(Object? raw) {
  if (raw == null) return null;
  return _money(raw);
}

int _karat(Object? raw) {
  if (raw is! int || !const {14, 18, 21, 22, 24}.contains(raw)) {
    throw const FormatException('repair');
  }
  return raw;
}

bool _bool(Object? raw) {
  if (raw is! bool) throw const FormatException('repair');
  return raw;
}

RepairRpcCommitted parseRepairCommand(Object? raw) {
  final json = _map(raw);
  if (json['ok'] != true || json['replayed'] is! bool) {
    throw const FormatException('repair');
  }
  return RepairRpcCommitted(
    repairId: _uuid(json['repair_id']),
    replayed: json['replayed'] as bool,
    result: json,
  );
}

RepairRemoteStatus parseRepairCommandStatus(Object? raw) {
  final json = _map(raw);
  final status = json['status'];
  if (status == 'absent') return const RepairRemoteAbsent();
  if (status != 'completed') throw const FormatException('repair');
  return RepairRemoteCompleted(
    repairId: _uuid(json['repair_id']),
    kind: _text(json['command_kind']),
  );
}

RepairContext parseRepairContext(Object? raw) {
  final json = _map(raw);
  final day = _map(json['day']);
  final methods = json['cash_methods'];
  if (methods is! List) throw const FormatException('repair');
  final state = _text(day['state']);
  return RepairContext(
    timeZone: _text(json['time_zone']),
    day: RepairDayContext(
      state: state,
      dayId: state == 'uninitialized' ? null : _uuid(day['business_day_id']),
      businessDate: day['business_date'] as String?,
      dayVersion: state == 'uninitialized'
          ? null
          : _money(day['day_version'], allowZero: false),
    ),
    cashMethods: [
      for (final item in methods)
        RepairCashMethod(
          method: _text(_map(item)['method']),
          balancePiastres: _money(_map(item)['balance_piastres']),
        ),
    ],
  );
}

RepairPage parseRepairPage(Object? raw) {
  final json = _map(raw);
  final items = json['items'];
  if (items is! List) throw const FormatException('repair');
  final cursor = json['next_cursor'];
  return RepairPage(
    items: [for (final item in items) _summary(_map(item))],
    nextCursor: cursor == null ? null : _uuid(cursor),
  );
}

RepairDetail parseRepairDetail(Object? raw) {
  final json = _map(raw);
  final events = json['events'];
  final custody = json['custody_events'];
  if (events is! List || custody is! List) {
    throw const FormatException('repair');
  }
  final operation = json['financial_operation_id'];
  return RepairDetail(
    summary: _summary(json),
    intakeNotes: _text(json['intake_notes']),
    financialOperationId: operation == null ? null : _uuid(operation),
    cancellationReason: json['cancellation_reason'] as String?,
    archivedFromStatus: json['archived_from_status'] as String?,
    intakeActorUserId: _uuid(json['intake_actor_user_id']),
    timeZone: _text(json['time_zone']),
    events: [
      for (final item in events)
        RepairEventView(
          id: _uuid(_map(item)['id']),
          eventType: _text(_map(item)['event_type']),
          actorUserId: _uuid(_map(item)['actor_user_id']),
          actorDisplayName: _text(_map(item)['actor_display_name']),
          createdAt: _text(_map(item)['created_at']),
          createdAtShop: _text(_map(item)['created_at_shop']),
        ),
    ],
    custodyEvents: [
      for (final item in custody)
        RepairCustodyView(
          id: _uuid(_map(item)['id']),
          direction: _text(_map(item)['direction']),
          measuredMilligrams: _money(
            _map(item)['measured_milligrams'],
            allowZero: false,
          ),
          karat: _karat(_map(item)['karat']),
          createdAtShop: _text(_map(item)['created_at_shop']),
        ),
    ],
  );
}

RepairSummary _summary(Map<String, Object?> json) => RepairSummary(
  id: _uuid(json['repair_id']),
  status: _text(json['status']),
  recordVersion: _money(json['record_version'], allowZero: false),
  customerName: _text(json['customer_name']),
  customerPhone: _text(json['customer_phone']),
  itemDescription: _text(json['item_description']),
  measuredMilligrams: _money(json['measured_milligrams'], allowZero: false),
  karat: _karat(json['karat']),
  issue: _text(json['issue']),
  custodyHeld: _bool(json['custody_held']),
  estimatedFeePiastres: _optionalMoney(json['estimated_fee_piastres']),
  finalFeePiastres: _optionalMoney(json['final_fee_piastres']),
  collectedPiastres: _money(json['collected_piastres']),
  outstandingPiastres: _money(json['outstanding_piastres']),
  intakeAt: _text(json['intake_at']),
  intakeAtShop: _text(json['intake_at_shop']),
);

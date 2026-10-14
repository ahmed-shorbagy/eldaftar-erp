import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../domain/debt_rules.dart';
import '../domain/debt_statement.dart';

DebtStatement parseDebtStatement(Object? raw) {
  if (raw is! Map ||
      raw['version'] != 1 ||
      raw['history_complete'] != true ||
      raw['history'] is! List ||
      raw['history_count'] != (raw['history'] as List).length) {
    throw const FormatException('debt_statement');
  }
  final j = Map<String, Object?>.from(raw);
  return DebtStatement(
    shopId: _uuid(j['shop_id']),
    shopName: _text(j['shop_name']),
    shopPhone: _optional(j['shop_phone']),
    timeZone: _text(j['time_zone']),
    sourceKind: DebtSourceKind.byWire(_text(j['source_kind'])) ?? _fail(),
    sourceId: _uuid(j['source_id']),
    sourceSequence: j['source_sequence'] == null
        ? null
        : _number(j['source_sequence'], false).toString(),
    direction: DebtDirection.byWire(_text(j['direction'])) ?? _fail(),
    unit: DebtUnit.byWire(_text(j['unit'])) ?? _fail(),
    karat: j['karat'] as int?,
    partyName: _text(j['party_name']),
    contactPhone: _optional(j['contact_phone']),
    reason: _text(j['reason']),
    reference: _optional(j['external_reference']),
    original: _number(j['original_amount'], false),
    settled: _number(j['settled_amount'], false),
    cancelled: _number(j['cancelled_amount'], false),
    remaining: _number(j['remaining_amount'], false),
    status: _text(j['display_status']),
    snapshotAt: _utc(j['snapshot_at']),
    snapshotAtShop: _wall(j['snapshot_at_shop']),
    freshness: _text(j['freshness']),
    history: [for (final raw in j['history'] as List) _event(raw)],
  );
}

DebtStatementEvent _event(Object? raw) {
  if (raw is! Map ||
      raw['actor_name_current'] is! bool ||
      !const {'move', 'none'}.contains(raw['ledger_effect'])) {
    _fail();
  }
  final type = switch (raw['event_type']) {
    'declared' => DebtStatementEventType.declared,
    'posted' => DebtStatementEventType.posted,
    'settled' => DebtStatementEventType.settled,
    'linked_settlement' => DebtStatementEventType.linkedSettlement,
    'cancelled' => DebtStatementEventType.cancelled,
    'linked_return' => DebtStatementEventType.linkedReturn,
    'archived' => DebtStatementEventType.archived,
    _ => _fail(),
  };
  return DebtStatementEvent(
    id: _uuid(raw['id']),
    at: _utc(raw['at']),
    atShop: _wall(raw['at_shop']),
    type: type,
    label: _text(raw['label_ar']),
    actorId: _uuid(raw['actor_user_id']),
    actorName: _text(raw['actor_display_name']),
    actorNameCurrent: raw['actor_name_current'] as bool,
    operationId: raw['operation_id'] == null
        ? null
        : _uuid(raw['operation_id']),
    amount: _number(raw['amount'], false),
    cancelled: _number(raw['cancelled_amount'], false),
    cash: _number(raw['cash_piastres'], true),
    gold: _number(raw['gold_milligrams'], true),
    reason: _optional(raw['reason']),
    movesLedger: raw['ledger_effect'] == 'move',
  );
}

Never _fail() => throw const FormatException('debt_statement');
String _text(Object? x) {
  if (x is! String ||
      x.trim().isEmpty ||
      x.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
    _fail();
  }
  return x;
}

String? _optional(Object? x) => x == null ? null : _text(x);
String _uuid(Object? x) {
  final s = _text(x);
  if (!isUuid(s)) _fail();
  return s;
}

BigInt _number(Object? x, bool signed) {
  final s = _text(x);
  if (!RegExp(
    signed ? r'^-?(0|[1-9][0-9]{0,18})$' : r'^(0|[1-9][0-9]{0,18})$',
  ).hasMatch(s)) {
    _fail();
  }
  final n = BigInt.parse(s);
  if (!PostgresInteger.fits(n)) _fail();
  return n;
}

DateTime _utc(Object? x) {
  final s = _text(x);
  final d = DateTime.tryParse(s);
  if (!RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
      ).hasMatch(s) ||
      d == null ||
      !d.isUtc ||
      d.toIso8601String().substring(0, 19) != s.substring(0, 19)) {
    _fail();
  }
  return d;
}

String _wall(Object? x) {
  final s = _text(x);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(s) ||
      DateTime.tryParse(s)?.toIso8601String().substring(0, 19) != s) {
    _fail();
  }
  return s;
}

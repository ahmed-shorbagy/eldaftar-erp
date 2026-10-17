import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/debt_native_contract.dart';
import '../application/debt_native_gateway.dart';
import '../domain/debt_calendar_date.dart';
import '../domain/debt_rules.dart';
import 'debt_codec.dart';
import 'debt_due_codec.dart';

Never _fail() => throw const FormatException('debt_native');
String _text(Object? x) =>
    x is String && x.trim().isNotEmpty && !x.contains(RegExp(r'[\x00-\x1f]'))
    ? x
    : _fail();
String _uuid(Object? x) {
  final s = _text(x);
  return isUuid(s) ? s : _fail();
}

String _hash(Object? x) {
  final s = _text(x);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : _fail();
}

BigInt _number(Object? x) {
  final s = _text(x);
  if (!RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(s)) _fail();
  final n = BigInt.parse(s);
  return PostgresInteger.fits(n) ? n : _fail();
}

DateTime _utc(Object? x) {
  final s = _text(x), d = DateTime.tryParse(_text(x));
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

String? _time(Object? x) => x == null
    ? null
    : x is String && validReminderTime(x)
    ? x
    : _fail();
String _wall(Object? x) {
  final s = _text(x);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(s) ||
      DateTime.tryParse(s)?.toIso8601String().substring(0, 19) != s) {
    _fail();
  }
  return s;
}

DebtNativeRow parseDebtNativeRow(Object? raw) {
  final j = debtMap(raw), due = parseDebtDueRow(raw);
  final time = _time(j['reminder_time']),
      version = _number(j['native_version']);
  if (j['time_valid'] is! bool ||
      (version == BigInt.zero) != (j['native_actor_user_id'] == null) ||
      (version == BigInt.zero) != (j['native_updated_at'] == null) ||
      version == BigInt.zero && time != null) {
    _fail();
  }
  if (j['native_actor_user_id'] != null) _uuid(j['native_actor_user_id']);
  if (j['native_updated_at'] != null) _utc(j['native_updated_at']);
  final trigger = j['trigger_at'] == null ? null : _utc(j['trigger_at']);
  final valid = j['time_valid'] as bool;
  if ((trigger != null) != (time != null && due.date != null && valid) ||
      !valid && (time == null || due.date == null)) {
    _fail();
  }
  return DebtNativeRow(
    due: due,
    time: time,
    version: version,
    freshness: _hash(j['native_freshness']),
    triggerAt: trigger,
    timeValid: valid,
  );
}

DebtNativeDetail parseDebtNativeDetail(Object? raw) {
  final j = debtMap(raw), row = parseDebtNativeRow(raw);
  if (j['version'] != 1 ||
      j['can_write'] is! bool ||
      j['native_history'] is! List ||
      j['can_write'] == true &&
          (row.due.summary.displayStatus != 'open' ||
              row.due.summary.remaining <= BigInt.zero)) {
    _fail();
  }
  final history = <DebtNativeEvent>[];
  final ids = <String>{};
  for (final raw in j['native_history'] as List) {
    final e = debtMap(raw), id = _uuid(e['id']);
    final version = _number(e['native_version']), date = e['due_date'];
    if (version != BigInt.from(history.length + 1) ||
        !ids.add(id) ||
        date != null &&
            (date is! String || DebtCalendarDate.parse(date) == null) ||
        _time(e['old_time']) !=
            (history.isEmpty ? null : history.last.newTime)) {
      _fail();
    }
    _uuid(e['actor_user_id']);
    history.add(
      DebtNativeEvent(
        id: id,
        oldTime: _time(e['old_time']),
        newTime: _time(e['new_time']),
        actor: _text(e['actor_display_name']),
        atShop: _wall(e['at_shop']),
        at: _utc(e['at']),
        version: version,
        zone: _text(e['time_zone']),
        date: date as String?,
      ),
    );
  }
  if (BigInt.from(history.length) != row.version ||
      history.isNotEmpty &&
          (history.last.newTime != row.time ||
              history.last.at != _utc(j['native_updated_at']))) {
    _fail();
  }
  return DebtNativeDetail(
    row: row,
    canWrite: j['can_write'] as bool,
    at: _utc(j['snapshot_at']),
    history: history,
  );
}

DebtNativePage parseDebtNativePage(Object? raw) {
  final j = debtMap(raw);
  if (j['version'] != 1 ||
      j['items'] is! List ||
      j['total'] is! int ||
      j['offset'] is! int) {
    _fail();
  }
  final items = <DebtScheduledIntent>[];
  for (final raw in j['items'] as List) {
    final r = debtMap(raw),
        kind = DebtSourceKind.byWire(_text(debtMap(raw)['source_kind']));
    if (r.length != 5 ||
        !const [
          'source_kind',
          'source_id',
          'native_freshness',
          'trigger_at',
          'time_valid',
        ].every(r.containsKey) ||
        kind == null ||
        r['time_valid'] is! bool) {
      _fail();
    }
    final at = r['trigger_at'] == null ? null : _utc(r['trigger_at']);
    if ((r['time_valid'] == true) != (at != null)) _fail();
    items.add(
      DebtScheduledIntent(
        sourceKind: kind,
        sourceId: _uuid(r['source_id']),
        freshness: _hash(r['native_freshness']),
        triggerAt: at,
        timeValid: r['time_valid'] as bool,
      ),
    );
  }
  final total = j['total'] as int,
      offset = j['offset'] as int,
      shop = _uuid(j['shop_id']);
  if (total < 0 ||
      offset < 0 ||
      offset + items.length > total ||
      (j['next_cursor'] == null) != (offset + items.length == total) ||
      items.isEmpty && total != 0 ||
      items.map((e) => e.key).toSet().length != items.length) {
    _fail();
  }
  for (var i = 0; i < items.length; i++) {
    final r = items[i];
    if (i > 0 && items[i - 1].key.compareTo(r.key) >= 0) {
      _fail();
    }
  }
  return DebtNativePage(
    items: items,
    shopId: shop,
    at: _utc(j['snapshot_at']),
    freshness: _hash(j['freshness']),
    total: total,
    offset: offset,
    cursor: j['next_cursor'] == null ? null : _text(j['next_cursor']),
  );
}

DebtNativeReceipt parseDebtNativeReceipt(Object? raw) {
  final j = debtMap(raw);
  if (j['kind'] != 'debt_native') _fail();
  final legacy = parseDebtDueReceipt({
    ...j,
    'kind': 'debt_due',
    'due_version': j['native_version'],
    'due_date': null,
  });
  return DebtNativeReceipt(
    shopId: legacy.shopId,
    key: legacy.key,
    sourceKind: legacy.sourceKind,
    sourceId: legacy.sourceId,
    payload: legacy.payload,
    time: _time(j['reminder_time']),
    version: legacy.version,
    actorId: legacy.actorId,
    at: legacy.at,
    freshness: legacy.freshness,
    replayed: legacy.replayed,
  );
}

DebtNativeReview parseDebtNativeReview(Object? raw) {
  final j = debtMap(raw),
      detail = parseDebtNativeDetail(raw),
      time = _time(j['proposed_time']);
  final at = j['proposed_trigger_at'] == null
      ? null
      : _utc(j['proposed_trigger_at']);
  if ((time == null) != (at == null) ||
      time != null && detail.row.due.date == null) {
    _fail();
  }
  return DebtNativeReview(detail, time, at);
}

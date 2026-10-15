import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/debt_due_gateway.dart';
import '../domain/debt_calendar_date.dart';
import 'debt_codec.dart';

Never _fail() => throw const FormatException('debt_due');
String _text(Object? x) {
  if (x is! String || x.trim().isEmpty || x.contains(RegExp(r'[\x00-\x1f]'))) {
    _fail();
  }
  return x;
}

String _uuid(Object? x) {
  final s = _text(x);
  if (!isUuid(s)) _fail();
  return s;
}

String _hash(Object? x) {
  final s = _text(x);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(s)) _fail();
  return s;
}

DebtCalendarDate _date(Object? x) =>
    DebtCalendarDate.parse(_text(x)) ?? _fail();
DebtCalendarDate? _optionalDate(Object? x) => x == null ? null : _date(x);
BigInt _number(Object? x) {
  final s = _text(x);
  if (!RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(s)) _fail();
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

DebtDueRow parseDebtDueRow(Object? raw) {
  final j = debtMap(raw);
  final summary = parseDebtSummary(j);
  final date = _optionalDate(j['due_date']);
  final today = _date(j['local_date']);
  final active =
      summary.displayStatus == 'open' && summary.remaining > BigInt.zero;
  final expected = date == null
      ? null
      : !active
      ? 'inactive'
      : date.compareTo(today) < 0
      ? 'overdue'
      : date.compareTo(today) == 0
      ? 'today'
      : 'upcoming';
  final version = _number(j['due_version']);
  if (j['due_state'] != expected ||
      (version == BigInt.zero) != (j['updated_at'] == null) ||
      (version == BigInt.zero) != (j['actor_user_id'] == null) ||
      version == BigInt.zero && date != null) {
    _fail();
  }
  return DebtDueRow(
    summary: summary,
    shopId: _uuid(j['shop_id']),
    date: date,
    version: version,
    state: expected,
    timeZone: _text(j['time_zone']),
    localDate: today,
    freshness: _hash(j['freshness']),
    updatedAt: j['updated_at'] == null ? null : _utc(j['updated_at']),
    actorId: j['actor_user_id'] == null ? null : _uuid(j['actor_user_id']),
  );
}

DebtDueDetail parseDebtDueDetail(Object? raw) {
  final j = debtMap(raw);
  final row = parseDebtDueRow(j);
  if (j['version'] != 1 ||
      j['can_schedule'] is! bool ||
      j['metadata_history'] is! List ||
      j['can_schedule'] == true &&
          (row.summary.displayStatus != 'open' ||
              row.summary.remaining <= BigInt.zero)) {
    _fail();
  }
  final history = <DebtDueEvent>[];
  for (final raw in j['metadata_history'] as List) {
    final e = debtMap(raw);
    final v = _number(e['due_version']);
    if (v != BigInt.from(history.length + 1)) _fail();
    history.add(
      DebtDueEvent(
        id: _uuid(e['id']),
        oldDate: _optionalDate(e['old_date']),
        newDate: _optionalDate(e['new_date']),
        version: v,
        actorId: _uuid(e['actor_user_id']),
        actorName: _text(e['actor_display_name']),
        at: _utc(e['at']),
        atShop: _wall(e['at_shop']),
      ),
    );
  }
  if (BigInt.from(history.length) != row.version ||
      history.isNotEmpty &&
          (history.last.newDate?.wire != row.date?.wire ||
              history.last.actorId != row.actorId ||
              history.last.at != row.updatedAt)) {
    _fail();
  }
  for (var i = 0; i < history.length; i++) {
    if (history[i].oldDate?.wire !=
        (i == 0 ? null : history[i - 1].newDate?.wire)) {
      _fail();
    }
  }
  return DebtDueDetail(
    row: row,
    canSchedule: j['can_schedule'] as bool,
    snapshotAt: _utc(j['snapshot_at']),
    snapshotAtShop: _wall(j['snapshot_at_shop']),
    history: history,
  );
}

DebtReminderPage parseDebtReminderPage(Object? raw) {
  final j = debtMap(raw);
  if (j['version'] != 1 ||
      j['items'] is! List ||
      j['total'] is! int ||
      j['offset'] is! int) {
    _fail();
  }
  final items = [for (final r in j['items'] as List) parseDebtDueRow(r)];
  final total = j['total'] as int, offset = j['offset'] as int;
  final shop = _uuid(j['shop_id']), zone = _text(j['time_zone']);
  final today = _date(j['local_date']);
  final cursor = j['next_cursor'];
  if (total < 0 ||
      offset < 0 ||
      offset + items.length > total ||
      (cursor == null) != (offset + items.length == total) ||
      items.isEmpty && total != 0 ||
      items.map((e) => e.summary.debtKey).toSet().length != items.length) {
    _fail();
  }
  for (var i = 0; i < items.length; i++) {
    final r = items[i];
    if (r.shopId != shop ||
        r.timeZone != zone ||
        r.localDate.wire != today.wire ||
        !const {'today', 'overdue', 'upcoming'}.contains(r.state)) {
      _fail();
    }
    if (i > 0 &&
        '${items[i - 1].date!.wire}:${items[i - 1].summary.debtKey}'.compareTo(
              '${r.date!.wire}:${r.summary.debtKey}',
            ) >=
            0) {
      _fail();
    }
  }
  return DebtReminderPage(
    items: items,
    shopId: shop,
    timeZone: zone,
    localDate: today,
    snapshotAt: _utc(j['snapshot_at']),
    snapshotAtShop: _wall(j['snapshot_at_shop']),
    freshness: _hash(j['freshness']),
    total: total,
    offset: offset,
    nextCursor: cursor == null ? null : _text(cursor),
  );
}

DebtDueReceipt parseDebtDueReceipt(Object? raw) {
  final j = debtMap(raw);
  if (j['version'] != 1 ||
      j['kind'] != 'debt_due' ||
      j['replayed'] is! bool ||
      j['invoice_effect'] != false ||
      [
        'cash_piastres',
        'gold_milligrams',
        'stock_milligrams',
        'custody_milligrams',
      ].any((k) => j[k] != '0') ||
      !const {
        'standalone',
        'purchase_cash_payable',
        'gold_obligation',
      }.contains(j['source_kind'])) {
    _fail();
  }
  final version = _number(j['due_version']);
  if (version == BigInt.zero) _fail();
  return DebtDueReceipt(
    shopId: _uuid(j['shop_id']),
    key: _uuid(j['key']),
    sourceKind: _text(j['source_kind']),
    sourceId: _uuid(j['source_id']),
    payload: debtMap(j['payload']),
    date: _optionalDate(j['due_date']),
    version: version,
    actorId: _uuid(j['actor_user_id']),
    at: _utc(j['at']),
    freshness: _hash(j['freshness']),
    replayed: j['replayed'] as bool,
  );
}

import '../../daily_ledger/data/daily_ledger_codec.dart' show isCalendarDate;
import '../../daily_ledger/application/idempotency_key.dart' show isUuid;
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/closing_delegation_gateway.dart';

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('delegation');
  }
  return Map<String, Object?>.from(value);
}

String _id(Object? value) {
  if (value is! String || !isUuid(value)) {
    throw const FormatException('delegation_id');
  }
  return value;
}

String _text(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.runes.length > 200 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException('delegation_text');
  }
  return value;
}

String _date(Object? value) {
  if (value is! String || !isCalendarDate(value)) {
    throw const FormatException('delegation_date');
  }
  return value;
}

String _sequence(Object? value) {
  if (value is! String || PostgresInteger.parseCanonical(value) == null) {
    throw const FormatException('delegation_sequence');
  }
  return value;
}

DateTime _utc(Object? value) {
  if (value is! String) throw const FormatException('delegation_time');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('delegation_time');
  }
  return parsed;
}

List<Object?> _list(Object? value, int limit) {
  if (value is! List || value.length > limit) {
    throw const FormatException('delegation_list');
  }
  return value;
}

ClosingCountBucket _bucket(Object? value) {
  final row = _map(value), category = row['category'], karat = row['karat'];
  if (!const ['worked_jewelry', 'bullion', 'coin'].contains(category) ||
      karat is! int ||
      !const [14, 18, 21, 22, 24].contains(karat)) {
    throw const FormatException('count_bucket');
  }
  return ClosingCountBucket(category as String, karat);
}

Map<String, Object?> parsePhysicalObservations(Object? raw) {
  final value = _map(raw);
  if (value.length != 2 ||
      !value.containsKey('stock') ||
      !value.containsKey('scrap')) {
    throw const FormatException('physical_count');
  }
  for (final rawRow in _list(value['stock'], 200)) {
    final row = _map(rawRow);
    if (row.length != 5) throw const FormatException('physical_count');
    _bucket(row);
    _text(row['item_name']);
    for (final key in ['count', 'milligrams']) {
      final number = row[key];
      if (key == 'milligrams' && number == null) continue;
      if (number is! String ||
          PostgresInteger.parseCanonical(number, allowZero: true) == null) {
        throw const FormatException('physical_count');
      }
    }
  }
  for (final rawRow in _list(value['scrap'], 5)) {
    final row = _map(rawRow), weight = row['milligrams'];
    if (row.length != 2 ||
        row['karat'] is! int ||
        !const [14, 18, 21, 22, 24].contains(row['karat']) ||
        weight is! String ||
        PostgresInteger.parseCanonical(weight, allowZero: true) == null) {
      throw const FormatException('physical_scrap');
    }
  }
  return value;
}

ClosingStaffDirectory parseClosingStaffDirectory(
  Object? raw, {
  required String shopId,
}) {
  final value = _map(raw);
  if (value['shop_id'] != shopId) {
    throw const FormatException('delegation_shop');
  }
  final staff = <ClosingStaffMember>[];
  for (final rawRow in _list(value['staff'], 50)) {
    final row = _map(rawRow);
    if (row['active'] is! bool) throw const FormatException('staff_active');
    staff.add(
      ClosingStaffMember(
        _id(row['id']),
        _text(row['name']),
        _text(row['phone']),
        row['active'] as bool,
      ),
    );
  }
  final tasks = <DelegatedClosingTask>[];
  for (final rawRow in _list(value['tasks'], 50)) {
    final row = _map(rawRow), state = row['state'];
    if (!const [
      'assigned',
      'submitted',
      'revoked',
      'expired',
      'closed',
    ].contains(state)) {
      throw const FormatException('task_state');
    }
    final physical = row['observations'] == null
        ? null
        : parsePhysicalObservations(row['observations']);
    if ((state == 'submitted' || state == 'closed') != (physical != null)) {
      throw const FormatException('task_observations');
    }
    tasks.add(
      DelegatedClosingTask(
        id: _id(row['id']),
        staffId: _id(row['staff_id']),
        dayId: _id(row['business_day_id']),
        dayVersion: _sequence(row['day_version']),
        businessDate: _date(row['business_date']),
        state: state as String,
        observations: physical,
        submittedBy: row['submitted_by'] == null
            ? null
            : _id(row['submitted_by']),
      ),
    );
  }
  return ClosingStaffDirectory(
    shopId,
    List.unmodifiable(staff),
    List.unmodifiable(tasks),
  );
}

StaffCountAssignment parseStaffCountAssignment(Object? raw) {
  final value = _map(raw), state = value['state'];
  if (state == 'not_staff' || state == 'unassigned') {
    if (value.length != 1) throw const FormatException('assignment');
    return StaffCountAssignment(state: state as String);
  }
  if (state != 'assigned') throw const FormatException('assignment');
  final now = _utc(value['server_now']), expiry = _utc(value['expires_at']);
  if (!expiry.isAfter(now) ||
      expiry.difference(now) > const Duration(hours: 24)) {
    throw const FormatException('assignment_expiry');
  }
  final karats = _list(value['scrap_karats'], 5);
  if (karats.any(
        (karat) => karat is! int || !const [14, 18, 21, 22, 24].contains(karat),
      ) ||
      karats.toSet().length != karats.length) {
    throw const FormatException('assignment_scrap');
  }
  return StaffCountAssignment(
    state: 'assigned',
    id: _id(value['task_id']),
    shopName: _text(value['shop_name']),
    staffName: _text(value['staff_name']),
    businessDate: _date(value['business_date']),
    serverNow: now,
    expiresAt: expiry,
    stock: [for (final bucket in _list(value['stock'], 15)) _bucket(bucket)],
    scrapKarats: karats.cast<int>(),
  );
}

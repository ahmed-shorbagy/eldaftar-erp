import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/customer_contract.dart';
import '../application/customer_gateway.dart';
import '../domain/customer_rules.dart';
import '../domain/customer_statistics.dart';

Map<String, Object?> customerMap(Object? raw) {
  if (raw is! Map) throw const FormatException('customer');
  return Map<String, Object?>.from(raw);
}

String _str(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('customer');
  }
  return value;
}

String _uuid(Object? value) {
  final s = _str(value);
  if (!isUuid(s)) throw const FormatException('customer');
  return s;
}

String? _optional(Object? v) {
  if (v == null) return null;
  return _str(v);
}

String _utc(Object? v) {
  final s = _str(v);
  if (!s.endsWith('Z') || DateTime.tryParse(s) == null) {
    throw const FormatException('customer');
  }
  return s;
}

bool _bool(Object? v) {
  if (v is! bool) throw const FormatException('customer');
  return v;
}

BigInt _statisticsInteger(Object? value) {
  final s = _str(value);
  if (!RegExp(r'^(0|[1-9][0-9]{0,39})$').hasMatch(s)) {
    throw const FormatException('customer_statistics');
  }
  return BigInt.parse(s);
}

CustomerStatistics parseCustomerStatistics(Object? raw) {
  final m = customerMap(raw);
  if (m['version'] is! int ||
      m['version'] != 1 ||
      m['policy'] != 'net_explicit_links_v1' ||
      m['weights'] is! List ||
      (m['weights'] as List).length != 5) {
    throw const FormatException('customer_statistics');
  }
  final weights = <CustomerKaratWeight>[];
  for (final raw in m['weights'] as List) {
    final w = customerMap(raw);
    if (w['karat'] is! int || w['karat'] != customerKarats[weights.length]) {
      throw const FormatException('customer_statistics');
    }
    weights.add(
      CustomerKaratWeight(
        w['karat'] as int,
        _statisticsInteger(w['bought_milligrams']),
        _statisticsInteger(w['sold_milligrams']),
      ),
    );
  }
  final bought = _statisticsInteger(m['bought_count']);
  final sold = _statisticsInteger(m['sold_count']);
  CustomerLastOperation? last;
  if (m['last_operation'] != null) {
    final op = customerMap(m['last_operation']);
    final kind = _str(op['operation_kind']);
    if (!{
      'sale',
      'purchase',
      'sale_return',
      'purchase_return',
    }.contains(kind)) {
      throw const FormatException('customer_statistics');
    }
    final local = _str(op['operation_created_at_shop']);
    final sequence = _statisticsInteger(op['shop_sequence']);
    if (DateTime.tryParse(local) == null || sequence == BigInt.zero) {
      throw const FormatException('customer_statistics');
    }
    last = CustomerLastOperation(
      id: _uuid(op['operation_id']),
      kind: kind,
      sequence: sequence,
      createdAt: _utc(op['operation_created_at']),
      createdAtShop: local,
    );
  }
  if (((bought + sold == BigInt.zero) != (last == null)) ||
      (bought == BigInt.zero &&
          weights.any((w) => w.boughtMilligrams > BigInt.zero)) ||
      (sold == BigInt.zero &&
          weights.any((w) => w.soldMilligrams > BigInt.zero))) {
    throw const FormatException('customer_statistics');
  }
  return CustomerStatistics(
    weights: weights,
    boughtCount: bought,
    soldCount: sold,
    lastOperation: last,
  );
}

CustomerRecord parseCustomer(Object? raw, {bool requireStatistics = false}) {
  final m = customerMap(raw);
  final v = _str(m['record_version']);
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(v) ||
      BigInt.parse(v) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('customer');
  }
  final status = _str(m['status']);
  if (!{'active', 'archived'}.contains(status)) {
    throw const FormatException('customer');
  }
  final name = _str(m['display_name']);
  if (!validCustomerName(name) || m['locale'] != 'ar') {
    throw const FormatException('customer');
  }
  if (m['phones'] is! List) throw const FormatException('customer');
  final phones = (m['phones'] as List).map((r) {
    final p = customerMap(r);
    final raw = _str(p['raw']);
    final norm = _str(p['normalized']);
    if (normalizeCustomerPhone(raw) != norm) {
      throw const FormatException('customer');
    }
    return CustomerContact(raw, norm, _bool(p['is_primary']));
  }).toList();
  if (customerPhoneIssue(
        phones
            .map((p) => CustomerPhone(number: p.raw, primary: p.primary))
            .toList(),
      ) !=
      null) {
    throw const FormatException('customer');
  }
  final last = m['last_operation_at'] == null
      ? null
      : _utc(m['last_operation_at']);
  final local = _optional(m['last_operation_at_shop']);
  if ((last == null) != (local == null)) {
    throw const FormatException('customer');
  }
  final updatedLocal = _str(m['updated_at_shop']);
  if (DateTime.tryParse(updatedLocal) == null ||
      (local != null && DateTime.tryParse(local) == null)) {
    throw const FormatException('customer');
  }
  final statistics = m['statistics'] == null
      ? null
      : parseCustomerStatistics(m['statistics']);
  if (requireStatistics && statistics == null ||
      statistics != null &&
          (statistics.lastOperation?.createdAt != last ||
              statistics.lastOperation?.createdAtShop != local)) {
    throw const FormatException('customer_statistics');
  }
  return CustomerRecord(
    id: _uuid(m['customer_id']),
    name: name,
    version: BigInt.parse(v),
    status: status,
    vip: _bool(m['is_vip']),
    openRequest: _bool(m['has_open_request']),
    phones: phones,
    updatedAt: _utc(m['updated_at']),
    updatedAtShop: updatedLocal,
    lastAt: last,
    lastAtShop: local,
    latestNote: _optional(m['latest_note_preview']),
    timeZone: _str(m['time_zone']),
    statistics: statistics,
  );
}

CustomerPage parseCustomerPage(Object? raw, {bool requireStatistics = false}) {
  final m = customerMap(raw);
  if (m['items'] is! List) throw const FormatException('customer');
  return CustomerPage(
    (m['items'] as List)
        .map((r) => parseCustomer(r, requireStatistics: requireStatistics))
        .toList(),
    _optional(m['next_cursor']),
  );
}

CustomerSection parseCustomerSection(Object? raw, {String? type}) {
  final m = customerMap(raw);
  if (m['items'] is! List) throw const FormatException('customer');
  final rows = (m['items'] as List).map(customerMap).toList();
  for (final row in rows) {
    if (type == 'notes') {
      _uuid(row['note_id']);
      _str(row['body']);
      _utc(row['created_at']);
      _str(row['created_at_shop']);
      _uuid(row['actor_user_id']);
      _str(row['actor_display_name']);
    }
    if (type == 'history') {
      _uuid(row['event_id']);
      if (!{
        'created',
        'edited',
        'note_added',
        'status_changed',
        'archived',
        'restored',
        'linked',
        'unlinked',
      }.contains(row['event_type'])) {
        throw const FormatException('customer');
      }
      _utc(row['created_at']);
      _str(row['created_at_shop']);
      _str(row['actor_display_name']);
      customerMap(row['payload']);
    }
    if (type == 'links' || type == 'candidates') {
      _uuid(row['operation_id']);
      if (!{'sale', 'purchase'}.contains(row['operation_kind'])) {
        throw const FormatException('customer');
      }
      _str(row['label_ar']);
      _str(row['shop_sequence']);
      _utc(row['operation_created_at']);
      _str(row['operation_created_at_shop']);
      if (type == 'links' &&
          !{'active', 'unlinked'}.contains(row['link_status'])) {
        throw const FormatException('customer');
      }
    }
  }
  return CustomerSection(rows, _optional(m['next_cursor']));
}

CustomerDetail parseCustomerDetail(
  Object? raw, {
  bool requireStatistics = false,
}) {
  final m = customerMap(raw);
  return CustomerDetail(
    parseCustomer(m, requireStatistics: requireStatistics),
    parseCustomerSection(m['notes'], type: 'notes'),
    parseCustomerSection(m['history'], type: 'history'),
    parseCustomerSection(m['links'], type: 'links'),
  );
}

CustomerReceipt parseCustomerReceipt(
  Object? raw,
  PendingFinancialCommand command,
) {
  final m = customerMap(raw);
  if (m['ok'] != true ||
      m['replayed'] is! bool ||
      m['command_kind'] != command.kind ||
      !matchesCustomerEnvelope(command.key, command.kind, command.body)) {
    throw const FormatException('customer');
  }
  final c = parseCustomer(m);
  if (command.kind == 'customer_create' && c.version != BigInt.one) {
    throw const FormatException('customer');
  }
  final p = customerMap(command.body['p_payload']);
  if (p['customer_id'] != null && p['customer_id'] != c.id) {
    throw const FormatException('customer');
  }
  if (p['expected_version'] != null &&
      c.version != BigInt.parse(p['expected_version'] as String) + BigInt.one) {
    throw const FormatException('customer');
  }
  if (p['display_name'] != null && p['display_name'] != c.name) {
    throw const FormatException('customer');
  }
  if (p['phones'] is List) {
    final expected = (p['phones'] as List).map((r) => customerMap(r)).toList();
    if (expected.length != c.phones.length ||
        expected.any(
          (e) => !c.phones.any(
            (n) => n.raw == e['number'] && n.primary == e['is_primary'],
          ),
        )) {
      throw const FormatException('customer');
    }
  }
  if (p['is_vip'] != null &&
      (c.vip != p['is_vip'] || c.openRequest != p['has_open_request'])) {
    throw const FormatException('customer');
  }
  if (command.kind == 'customer_archive' && !c.archived ||
      command.kind == 'customer_restore' && c.archived) {
    throw const FormatException('customer');
  }
  final op = _optional(m['operation_id']);
  if (p['operation_id'] != null && p['operation_id'] != op) {
    throw const FormatException('customer');
  }
  final note = m['note_id'] == null ? null : _uuid(m['note_id']);
  final link = m['link_id'] == null ? null : _uuid(m['link_id']);
  if (command.kind == 'customer_note' &&
      (note == null ||
          c.latestNote !=
              String.fromCharCodes((p['body'] as String).runes.take(120)))) {
    throw const FormatException('customer');
  }
  if (p['operation_id'] != null && link == null) {
    throw const FormatException('customer');
  }
  return CustomerReceipt(
    command.kind,
    c,
    operationId: op,
    noteId: note,
    linkId: link,
  );
}

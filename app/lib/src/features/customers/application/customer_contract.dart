import '../../daily_ledger/application/idempotency_key.dart';
import '../domain/customer_rules.dart';
import '../domain/customer_saved_number.dart';

const customerRpcs = <String, String>{
  'customer_create': 'post_customer_create_v1',
  'customer_edit': 'post_customer_edit_v1',
  'customer_note': 'post_customer_note_v1',
  'customer_status': 'post_customer_status_v1',
  'customer_archive': 'post_customer_archive_v1',
  'customer_restore': 'post_customer_restore_v1',
  'customer_link': 'post_customer_link_v1',
  'customer_unlink': 'post_customer_unlink_v1',
  'customer_saved_number': 'post_customer_saved_number_v1',
};
bool matchesCustomerEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (!isUuid(key) ||
      !customerRpcs.containsKey(kind) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key ||
      body['p_payload'] is! Map) {
    return false;
  }
  final p = Map<String, Object?>.from(body['p_payload'] as Map);
  if (p['version'] != 1 || p['kind'] != kind) return false;
  final keys = <String>{'version', 'kind'};
  if (kind != 'customer_create') {
    keys.addAll(['customer_id', 'expected_version']);
    final v = p['expected_version'];
    if (p['customer_id'] is! String ||
        !isUuid(p['customer_id'] as String) ||
        v is! String ||
        !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(v) ||
        BigInt.parse(v) > BigInt.parse('9223372036854775807')) {
      return false;
    }
  }
  if (kind == 'customer_create' || kind == 'customer_edit') {
    keys.addAll(['display_name', 'phones']);
    if (p['display_name'] is! String ||
        !validCustomerName(p['display_name'] as String) ||
        p['phones'] is! List) {
      return false;
    }
    final phones = <CustomerPhone>[];
    for (final raw in p['phones'] as List) {
      if (raw is! Map ||
          raw.length != 2 ||
          raw['number'] is! String ||
          raw['is_primary'] is! bool) {
        return false;
      }
      phones.add(
        CustomerPhone(
          number: raw['number'] as String,
          primary: raw['is_primary'] as bool,
        ),
      );
    }
    if (customerPhoneIssue(phones) != null) return false;
  }
  if (kind == 'customer_create' || kind == 'customer_status') {
    keys.addAll(['is_vip', 'has_open_request']);
    if (p['is_vip'] is! bool || p['has_open_request'] is! bool) return false;
  }
  if (kind == 'customer_note') {
    keys.add('body');
    if (p['body'] is! String || !validCustomerNote(p['body'] as String)) {
      return false;
    }
  }
  if (kind == 'customer_saved_number') {
    keys.addAll(['number_id', 'normalized_number', 'state']);
    if (p['number_id'] is! String ||
        !isUuid(p['number_id'] as String) ||
        p['normalized_number'] is! String ||
        normalizeCustomerPhone(p['normalized_number'] as String) !=
            p['normalized_number'] ||
        !savedNumberStates.contains(p['state'])) {
      return false;
    }
  }
  if (kind == 'customer_link' || kind == 'customer_unlink') {
    keys.add('operation_id');
    if (p['operation_id'] is! String || !isUuid(p['operation_id'] as String)) {
      return false;
    }
  }
  return p.keys.toSet().length == keys.length && p.keys.every(keys.contains);
}

import 'dart:convert';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../domain/debt_calendar_date.dart';

const debtDueKind = 'debt_due';
bool matchesDebtDueEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != debtDueKind ||
      !isUuid(key) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key) {
    return false;
  }
  final raw = body['p_payload'];
  if (raw is! Map) return false;
  final p = Map<String, Object?>.from(raw);
  final version = p['expected_due_version'];
  return p.length == 7 &&
      p['kind'] == debtDueKind &&
      p['version'] == 1 &&
      const {
        'standalone',
        'purchase_cash_payable',
        'gold_obligation',
      }.contains(p['source_kind']) &&
      p['source_id'] is String &&
      isUuid(p['source_id'] as String) &&
      (p['due_date'] == null ||
          p['due_date'] is String &&
              DebtCalendarDate.parse(p['due_date'] as String) != null) &&
      version is String &&
      RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(version) &&
      PostgresInteger.fits(BigInt.parse(version)) &&
      p['expected_freshness'] is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(p['expected_freshness'] as String);
}

String canonicalDueJson(Object? value) {
  Object? sorted(Object? x) {
    if (x is Map) {
      final keys = x.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(x[k])};
    }
    if (x is List) return x.map(sorted).toList();
    return x;
  }

  return jsonEncode(sorted(value));
}

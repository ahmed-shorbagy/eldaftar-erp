import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';

const debtNativeKind = 'debt_native';
bool validReminderTime(String value) =>
    RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value);

bool matchesDebtNativeEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  if (kind != debtNativeKind ||
      !isUuid(key) ||
      body.length != 2 ||
      body['p_idempotency_key'] != key ||
      body['p_payload'] is! Map) {
    return false;
  }
  final p = body['p_payload'] as Map;
  final version = p['expected_native_version'];
  return p.length == 7 &&
      p['kind'] == debtNativeKind &&
      p['version'] == 1 &&
      const {
        'standalone',
        'purchase_cash_payable',
        'gold_obligation',
      }.contains(p['source_kind']) &&
      p['source_id'] is String &&
      isUuid(p['source_id'] as String) &&
      (p['reminder_time'] == null ||
          p['reminder_time'] is String &&
              validReminderTime(p['reminder_time'] as String)) &&
      version is String &&
      RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(version) &&
      PostgresInteger.fits(BigInt.parse(version)) &&
      p['expected_freshness'] is String &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(p['expected_freshness'] as String);
}

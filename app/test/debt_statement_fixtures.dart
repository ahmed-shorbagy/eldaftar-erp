import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';

const statementUser = 'f1111111-1111-4111-8111-111111111111';
const statementShop = 'f2222222-2222-4222-8222-222222222222';
const statementSourceId = 'f3333333-3333-4333-8333-333333333333';
String statementEventId(int i) =>
    'f4444444-4444-4444-8444-${i.toString().padLeft(12, '0')}';
Map<String, Object?> statementFixture({
  DebtSourceKind source = DebtSourceKind.standalone,
  String unit = 'money',
  int? karat,
  String direction = 'shop_owes',
  int payments = 1,
  bool cancel = false,
  bool archived = false,
}) {
  final history = <Map<String, Object?>>[];
  Map<String, Object?> row(
    int i,
    String type,
    String amount, {
    String cancelled = '0',
  }) => {
    'id': statementEventId(i),
    'at': '2026-10-14T${i == 0 ? '00' : '01'}:00:00.000000Z',
    'at_shop': '2026-10-14T${i == 0 ? '03' : '04'}:00:00',
    'event_type': type,
    'label_ar': i == 0
        ? 'تسجيل أصل الدين'
        : type == 'archived'
        ? 'أرشفة دين'
        : type == 'linked_return' || type == 'cancelled'
        ? 'إلغاء دين'
        : 'سداد دين',
    'actor_user_id': statementUser,
    'actor_display_name': 'مالك تجريبي',
    'actor_name_current': source.isSource,
    'operation_id': source.isSource
        ? (i == 0 ? statementSourceId : statementEventId(i))
        : null,
    'amount': amount,
    'cancelled_amount': cancelled,
    'cash_piastres': '0',
    'gold_milligrams': '0',
    'reason': 'بيانات اصطناعية للمراجعة فقط',
    'ledger_effect': source.isSource ? 'move' : 'none',
  };
  final original = BigInt.from(10005 + payments);
  history.add(
    row(0, source.isSource ? 'posted' : 'declared', original.toString()),
  );
  for (var i = 1; i <= payments; i++) {
    history.add(row(i, source.isSource ? 'linked_settlement' : 'settled', '1'));
  }
  final cancelled = cancel
      ? BigInt.from(source.isSource ? 100 : 10005)
      : BigInt.zero;
  if (cancel) {
    history.add(
      row(
        payments + 1,
        source.isSource ? 'linked_return' : 'cancelled',
        '0',
        cancelled: cancelled.toString(),
      ),
    );
  }
  if (archived) {
    final r = row(payments + 2, 'archived', '0');
    r['operation_id'] = null;
    r['ledger_effect'] = 'none';
    history.add(r);
  }
  return {
    'version': 1,
    'shop_id': statementShop,
    'shop_name': 'محل تجريبي للذهب',
    'shop_phone': null,
    'time_zone': 'Africa/Cairo',
    'source_kind': source.wire,
    'source_id': statementSourceId,
    'source_sequence': source.isSource ? '123' : null,
    'direction': direction,
    'unit': unit,
    'karat': karat,
    'party_name': 'عميل تجريبي أحمد ABC 123',
    'contact_phone': null,
    'reason': 'رصيد مسجل للتجربة',
    'external_reference': 'مرجع تجريبي ١٢٣',
    'original_amount': original.toString(),
    'settled_amount': payments.toString(),
    'cancelled_amount': cancelled.toString(),
    'remaining_amount': (original - BigInt.from(payments) - cancelled)
        .toString(),
    'display_status': archived
        ? 'archived'
        : cancel && !source.isSource
        ? 'cancelled'
        : 'open',
    'snapshot_at': '2026-10-14T23:00:00.000000Z',
    'snapshot_at_shop': '2026-10-15T02:00:00',
    'freshness': 'a' * 64,
    'history_complete': true,
    'history_count': history.length,
    'history': history,
  };
}

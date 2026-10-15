import 'dart:convert';
import 'package:eldafttar/src/features/debts/application/debt_due_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_due_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';

const dueUser = 'a1111111-1111-4111-8111-111111111111';
const dueShop = 'a2222222-2222-4222-8222-222222222222';
const dueSourceId = 'a3333333-3333-4333-8333-333333333333';
const dueKey = 'a4444444-4444-4444-8444-444444444444';
final dueHash = List.filled(64, 'a').join();
Map<String, Object?> dueFixture({
  String source = 'standalone',
  String direction = 'shop_owes',
  int? karat,
  String? date = '2026-10-14',
  String state = 'open',
  String remaining = '10005',
  int version = 1,
}) => {
  'version': 1,
  'shop_id': dueShop,
  'debt_key': '$source:$dueSourceId',
  'source_kind': source,
  'source_id': dueSourceId,
  'direction': direction,
  'unit': karat == null ? 'money' : 'gold',
  'karat': karat,
  'party_name': 'عميل اختبار عربي',
  'contact_phone': null,
  'reason': 'رصيد اختبار',
  'external_reference': null,
  'original_amount': '10005',
  'settled_amount': (10005 - int.parse(remaining)).toString(),
  'cancelled_amount': '0',
  'remaining_amount': remaining,
  'display_status': state,
  'record_version': source == 'standalone' ? '1' : null,
  'created_at': '2026-10-01T00:00:00Z',
  'created_at_shop': '2026-10-01T03:00:00',
  'time_zone': 'Africa/Cairo',
  'local_date': '2026-10-14',
  'due_date': date,
  'due_version': '$version',
  'due_state': date == null
      ? null
      : state != 'open' || remaining == '0'
      ? 'inactive'
      : date.compareTo('2026-10-14') < 0
      ? 'overdue'
      : date == '2026-10-14'
      ? 'today'
      : 'upcoming',
  'updated_at': version == 0 ? null : '2026-10-13T12:00:00Z',
  'actor_user_id': version == 0 ? null : dueUser,
  'freshness': dueHash,
  'can_schedule': state == 'open' && remaining != '0',
  'snapshot_at': '2026-10-14T12:00:00Z',
  'snapshot_at_shop': '2026-10-14T15:00:00',
  'metadata_history': version == 0
      ? <Object?>[]
      : [
          {
            'id': dueKey,
            'old_date': null,
            'new_date': date,
            'due_version': '$version',
            'actor_user_id': dueUser,
            'actor_display_name': 'المالك',
            'at': '2026-10-13T12:00:00Z',
            'at_shop': '2026-10-13T15:00:00',
          },
        ],
};
Map<String, Object?> dueReceipt(
  PendingFinancialCommand c, {
  String? shop,
  String? actor,
}) {
  final p = Map<String, Object?>.from(c.body['p_payload'] as Map);
  return {
    'version': 1,
    'shop_id': shop ?? dueShop,
    'key': c.key,
    'kind': 'debt_due',
    'source_kind': p['source_kind'],
    'source_id': p['source_id'],
    'payload': p,
    'due_date': p['due_date'],
    'due_version':
        (BigInt.parse(p['expected_due_version'] as String) + BigInt.one)
            .toString(),
    'actor_user_id': actor ?? dueUser,
    'at': '2026-10-14T12:00:00Z',
    'freshness': dueHash,
    'replayed': false,
    'cash_piastres': '0',
    'gold_milligrams': '0',
    'stock_milligrams': '0',
    'custody_milligrams': '0',
    'invoice_effect': false,
  };
}

Map<String, Object?> duePageFixture({
  List<Map<String, Object?>>? rows,
  int? total,
  int offset = 0,
  String? cursor,
}) => {
  'version': 1,
  'shop_id': dueShop,
  'time_zone': 'Africa/Cairo',
  'local_date': '2026-10-14',
  'snapshot_at': '2026-10-14T12:00:00Z',
  'snapshot_at_shop': '2026-10-14T15:00:00',
  'freshness': dueHash,
  'items': rows ?? [dueFixture()],
  'total': total ?? rows?.length ?? 1,
  'offset': offset,
  'next_cursor': cursor,
};

class FakeDue implements DebtDueGateway {
  Object? session = 'token';
  Map<String, Object?> data = dueFixture();
  Map<String, Object?> page = duePageFixture();
  String? error;
  bool unknown = false;
  int reads = 0;
  final readRequests = <String>[];
  final sent = <PendingFinancialCommand>[];
  Future<DebtDueDetail> Function()? readOverride;
  Future<DebtDueTransport> Function(PendingFinancialCommand)? sendOverride,
      statusOverride;
  Future<DebtReminderPage> Function(String?)? pageOverride;
  @override
  Object? dueSession(String _) => session;
  @override
  Future<DebtDueDetail> readDue({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    reads++;
    readRequests.add('$userId:$shopId:${sourceKind.wire}:$sourceId');
    return readOverride != null
        ? await readOverride!()
        : parseDebtDueDetail(data);
  }

  @override
  Future<DebtReminderPage> readReminders({
    required String userId,
    required String shopId,
    required String query,
    required String filter,
    required String? cursor,
  }) async {
    if (error == 'read') throw const DebtReadException();
    return pageOverride != null
        ? await pageOverride!(cursor)
        : parseDebtReminderPage(page);
  }

  @override
  Future<DebtDueTransport> sendDue({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) async {
    sent.add(command);
    if (sendOverride != null) return sendOverride!(command);
    if (error != null) return DebtDueTransport(error: error);
    if (unknown) return const DebtDueTransport();
    final receipt = dueReceipt(command);
    final version = int.parse(receipt['due_version'] as String),
        date = receipt['due_date'] as String?;
    final event = {
      'id': 'afffffff-ffff-4fff-8fff-${version.toString().padLeft(12, '0')}',
      'old_date': data['due_date'],
      'new_date': date,
      'due_version': '$version',
      'actor_user_id': dueUser,
      'actor_display_name': 'المالك',
      'at': receipt['at'],
      'at_shop': '2026-10-14T15:00:00',
    };
    data = {
      ...data,
      'due_date': date,
      'due_version': '$version',
      'due_state': date == null
          ? null
          : date.compareTo('2026-10-14') < 0
          ? 'overdue'
          : date == '2026-10-14'
          ? 'today'
          : 'upcoming',
      'updated_at': receipt['at'],
      'metadata_history': [...data['metadata_history'] as List, event],
    };
    return DebtDueTransport(receipt: parseDebtDueReceipt(receipt));
  }

  @override
  Future<DebtDueTransport> dueStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) async => statusOverride != null
      ? await statusOverride!(command)
      : const DebtDueTransport(absent: true);
  Map<String, Object?> payload() => parseDebtDueDetail(data).payload(null);
  Map<String, Object?> clone() =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(data)) as Map);
}

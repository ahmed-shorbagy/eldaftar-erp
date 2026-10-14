import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';

const customerId = 'ca111111-1111-4111-8111-111111111111';
const operationId = 'ca222222-2222-4222-8222-222222222222';
const commandKey = 'ca333333-3333-4333-8333-333333333333';
Map<String, Object?> customerJson({
  String name = 'عميل اختبار',
  String version = '1',
  String status = 'active',
  bool vip = false,
  bool open = false,
  List<Object?> phones = const [],
  String? note,
  String? last,
}) => {
  'customer_id': customerId,
  'display_name': name,
  'record_version': version,
  'status': status,
  'is_vip': vip,
  'has_open_request': open,
  'phones': phones,
  'saved_number_policy': 'owner_number_v1',
  'latest_note_preview': note,
  'created_at': '2026-10-13T08:00:00.000000Z',
  'created_at_shop': '2026-10-13T11:00:00',
  'updated_at': '2026-10-13T09:00:00.000000Z',
  'updated_at_shop': '2026-10-13T12:00:00',
  'last_operation_at': last == null ? null : '2026-10-12T21:30:00.000000Z',
  'last_operation_at_shop': last,
  'time_zone': 'Africa/Cairo',
  'locale': 'ar',
};
Map<String, Object?> createCustomerPayload() => {
  'version': 1,
  'kind': 'customer_create',
  'display_name': 'عميل جديد',
  'phones': <Object?>[],
  'is_vip': false,
  'has_open_request': false,
};
PendingFinancialCommand createCustomerCommand() => PendingFinancialCommand(
  key: commandKey,
  kind: 'customer_create',
  body: {'p_idempotency_key': commandKey, 'p_payload': createCustomerPayload()},
);
Map<String, Object?> candidateJson() => {
  'operation_id': operationId,
  'operation_kind': 'purchase',
  'label_ar': 'شراء',
  'shop_sequence': '7',
  'party_name': 'طرف العملية الأصلي',
  'party_phone': '01011111111',
  'operation_created_at': '2026-10-12T21:30:00.000000Z',
  'operation_created_at_shop': '2026-10-13T00:30:00',
  'business_date': '2026-10-12',
  'note': null,
};

class FakeCustomers implements CustomerGateway {
  Map<String, Object?> row = customerJson(
    vip: true,
    open: true,
    note: 'طلب اختبار محفوظ',
  );
  final notes = <Map<String, Object?>>[],
      events = <Map<String, Object?>>[],
      links = <Map<String, Object?>>[];
  final sent = <PendingFinancialCommand>[];
  int reads = 0;
  bool unknown = false, absent = false;
  String? rejected;
  String? readError;
  CustomerTransport? statusOverride;
  Future<void>? hold;
  CustomerReceipt? committed;
  @override
  Future<CustomerTransport> sendCustomer({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    sent.add(command);
    if (hold != null) await hold;
    if (rejected != null) return CustomerTransport(error: rejected);
    final p = customerMap(command.body['p_payload']);
    final kind = command.kind;
    row = {
      ...row,
      'record_version': kind == 'customer_create'
          ? '1'
          : '${BigInt.parse(row['record_version'] as String) + BigInt.one}',
    };
    if (p['display_name'] != null) row['display_name'] = p['display_name'];
    if (p['phones'] is List) {
      row['phones'] = (p['phones'] as List)
          .map(
            (n) => {
              'raw': (n as Map)['number'],
              'normalized': (n['number'] as String).startsWith('+')
                  ? n['number']
                  : '+20${(n['number'] as String).substring(1)}',
              'is_primary': n['is_primary'],
            },
          )
          .toList();
    }
    if (p['is_vip'] != null) {
      row['is_vip'] = p['is_vip'];
      row['has_open_request'] = p['has_open_request'];
    }
    if (kind == 'customer_archive') row['status'] = 'archived';
    if (kind == 'customer_restore') row['status'] = 'active';
    String? noteId, linkId;
    if (kind == 'customer_note') {
      noteId = operationId;
      row['latest_note_preview'] = p['body'];
      notes.insert(0, {
        'note_id': noteId,
        'body': p['body'],
        'created_at': '2026-10-13T09:00:00.000000Z',
        'created_at_shop': '2026-10-13T12:00:00',
        'actor_display_name': 'مالك الاختبار',
      });
    }
    if (kind == 'customer_link') {
      linkId = commandKey;
      row['last_operation_at'] = '2026-10-12T21:30:00.000000Z';
      row['last_operation_at_shop'] = '2026-10-13T00:30:00';
      links.add({
        ...candidateJson(),
        'link_id': linkId,
        'link_status': 'active',
        'linked_at_shop': '2026-10-13T12:00:00',
      });
    }
    if (kind == 'customer_unlink') {
      linkId = commandKey;
      links.first['link_status'] = 'unlinked';
      row['last_operation_at'] = null;
      row['last_operation_at_shop'] = null;
    }
    committed = CustomerReceipt(
      kind,
      parseCustomer(row),
      operationId: p['operation_id'] as String?,
      noteId: noteId,
      linkId: linkId,
    );
    return unknown
        ? const CustomerTransport()
        : CustomerTransport(receipt: committed);
  }

  @override
  Future<CustomerTransport> customerStatus({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async =>
      statusOverride ??
      (unknown
          ? const CustomerTransport()
          : absent
          ? const CustomerTransport(absent: true)
          : CustomerTransport(receipt: committed));
  @override
  Future<CustomerPage> customers({
    required String callerUserId,
    required String query,
    required String sort,
    required String filter,
    required String? cursor,
  }) async {
    reads++;
    if (readError != null) {
      throw CustomerReadException(readError);
    }
    return CustomerPage(
      query.isNotEmpty && !row['display_name'].toString().contains(query)
          ? []
          : [parseCustomer(row)],
      null,
    );
  }

  @override
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  }) async => CustomerDetail(
    parseCustomer(row),
    CustomerSection(notes, null),
    CustomerSection(events, null),
    CustomerSection(links, null),
  );
  @override
  Future<CustomerSection> customerCandidates({
    required String callerUserId,
    required String query,
    required String? cursor,
  }) async => CustomerSection([candidateJson()], null);
}

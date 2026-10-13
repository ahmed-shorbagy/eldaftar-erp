import '../../daily_ledger/application/pending_financial_command.dart';

class CustomerReadException implements Exception {
  const CustomerReadException([this.code]);
  final String? code;
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.version,
    required this.status,
    required this.vip,
    required this.openRequest,
    required this.phones,
    required this.updatedAt,
    required this.updatedAtShop,
    required this.lastAt,
    required this.lastAtShop,
    required this.latestNote,
    required this.timeZone,
  });
  final String id, name, status, updatedAt, updatedAtShop, timeZone;
  final BigInt version;
  final bool vip, openRequest;
  final List<CustomerContact> phones;
  final String? lastAt, lastAtShop, latestNote;
  bool get archived => status == 'archived';
}

class CustomerContact {
  const CustomerContact(this.raw, this.normalized, this.primary);
  final String raw, normalized;
  final bool primary;
}

class CustomerPage {
  const CustomerPage(this.items, this.cursor);
  final List<CustomerRecord> items;
  final String? cursor;
}

class CustomerSection {
  const CustomerSection(this.items, this.cursor);
  final List<Map<String, Object?>> items;
  final String? cursor;
}

class CustomerDetail {
  const CustomerDetail(this.customer, this.notes, this.history, this.links);
  final CustomerRecord customer;
  final CustomerSection notes, history, links;
}

class CustomerReceipt {
  const CustomerReceipt(
    this.kind,
    this.customer, {
    this.operationId,
    this.noteId,
    this.linkId,
  });
  final String kind;
  final CustomerRecord customer;
  final String? operationId, noteId, linkId;
}

class CustomerTransport {
  const CustomerTransport({this.receipt, this.error, this.absent = false});
  final CustomerReceipt? receipt;
  final String? error;
  final bool absent;
}

abstract class CustomerGateway {
  Future<CustomerTransport> sendCustomer({
    required String callerUserId,
    required PendingFinancialCommand command,
  });
  Future<CustomerTransport> customerStatus({
    required String callerUserId,
    required PendingFinancialCommand command,
  });
  Future<CustomerPage> customers({
    required String callerUserId,
    required String query,
    required String sort,
    required String filter,
    required String? cursor,
  });
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  });
  Future<CustomerSection> customerCandidates({
    required String callerUserId,
    required String query,
    required String? cursor,
  });
}

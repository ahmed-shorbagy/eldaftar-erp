import '../../daily_ledger/application/financial_gateway.dart';

final class ClosingStaffMember {
  const ClosingStaffMember(this.id, this.name, this.phone, this.active);
  final String id, name, phone;
  final bool active;
}

final class DelegatedClosingTask {
  const DelegatedClosingTask({
    required this.id,
    required this.staffId,
    required this.dayId,
    required this.dayVersion,
    required this.businessDate,
    required this.state,
    this.observations,
    this.submittedBy,
  });
  final String id, staffId, dayId, dayVersion, businessDate, state;
  final Map<String, Object?>? observations;
  final String? submittedBy;
}

final class ClosingStaffDirectory {
  const ClosingStaffDirectory(this.shopId, this.staff, this.tasks);
  final String shopId;
  final List<ClosingStaffMember> staff;
  final List<DelegatedClosingTask> tasks;
}

final class ClosingCountBucket {
  const ClosingCountBucket(this.category, this.karat);
  final String category;
  final int karat;
}

final class StaffCountAssignment {
  const StaffCountAssignment({
    required this.state,
    this.id,
    this.shopName,
    this.staffName,
    this.businessDate,
    this.serverNow,
    this.expiresAt,
    this.stock = const [],
    this.scrapKarats = const [],
  });
  final String state;
  final String? id, shopName, staffName, businessDate;
  final DateTime? serverNow, expiresAt;
  final List<ClosingCountBucket> stock;
  final List<int> scrapKarats;
  bool get assigned => state == 'assigned';
  Duration? get remaining => expiresAt?.difference(serverNow!);
}

sealed class DelegationResult {
  const DelegationResult();
}

final class DelegationCommitted extends DelegationResult {
  const DelegationCommitted();
}

final class DelegationRejected extends DelegationResult {
  const DelegationRejected(this.code);
  final String code;
}

final class DelegationUnknown extends DelegationResult {
  const DelegationUnknown();
}

enum DelegationStatus { confirmed, absent, prepared, unknown }

class DelegationReadException implements Exception {
  const DelegationReadException(this.code);
  final String code;
}

abstract interface class ClosingDelegationGateway {
  Future<ClosingStaffDirectory> closingStaff({
    required String userId,
    required String shopId,
  });
  Future<StaffCountAssignment> myClosingAssignment({required String userId});
  Future<DelegationResult> createClosingStaff({
    required String userId,
    required String key,
    required String name,
    required String phone,
    required String password,
  });
  Future<DelegationStatus> closingStaffCreationStatus({
    required String userId,
    required String key,
  });
  Future<DelegationResult> changeClosingAssignment({
    required String userId,
    required String key,
    required String action,
    required String target,
    String? dayId,
    String? dayVersion,
  });
  Future<DelegationStatus> closingDelegationStatus({
    required String userId,
    required String key,
  });
  Future<DelegationResult> submitClosingCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> observations,
  });
  Future<FinancialCommandResult> closeFromStaffCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> cash,
  });
}

/// Separate from financial pending commands: passwords are never persisted.
final class PendingDelegation {
  const PendingDelegation(this.key, this.kind, this.payload);
  final String key, kind;
  final Map<String, Object?> payload;
}

abstract interface class DelegationPendingStore {
  Future<PendingDelegation?> read(String userId, String scope);
  Future<void> save(String userId, String scope, PendingDelegation pending);
  Future<void> clear(String userId, String scope, String key);
}

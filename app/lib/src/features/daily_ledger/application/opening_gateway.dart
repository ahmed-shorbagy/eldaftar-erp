import 'daily_ledger_view.dart';

sealed class ConfirmResult {
  const ConfirmResult();
}

final class ConfirmCommitted extends ConfirmResult {
  const ConfirmCommitted({
    required this.operationId,
    required this.businessDayId,
    required this.businessDate,
    required this.replayed,
  });

  final String operationId;
  final String businessDayId;
  final String businessDate;
  final bool replayed;
}

final class ConfirmRejected extends ConfirmResult {
  const ConfirmRejected(this.code);
  final String code;
}

final class ConfirmUnknown extends ConfirmResult {
  const ConfirmUnknown();
}

sealed class StatusResult {
  const StatusResult();
}

final class StatusAbsent extends StatusResult {
  const StatusAbsent();
}

final class StatusCompleted extends StatusResult {
  const StatusCompleted(this.operationId);
  final String operationId;
}

final class StatusRejected extends StatusResult {
  const StatusRejected(this.code);
  final String code;
}

final class StatusUnknown extends StatusResult {
  const StatusUnknown();
}

class LedgerReadException implements Exception {
  const LedgerReadException([this.code]);
  final String? code;

  @override
  String toString() => 'LedgerReadException($code)';
}

abstract class OpeningGateway {
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  });

  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  });

  Future<DailyLedgerView> ledger({required String callerUserId});
}

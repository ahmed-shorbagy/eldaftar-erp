import '../domain/debt_statement.dart';
import '../domain/debt_rules.dart';

abstract interface class DebtStatementGateway {
  Object? statementSession(String callerUserId);
  Future<DebtStatement> readStatement({
    required String callerUserId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  });
}

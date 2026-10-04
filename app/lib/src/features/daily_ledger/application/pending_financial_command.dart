final class PendingFinancialCommand {
  const PendingFinancialCommand({
    required this.key,
    required this.kind,
    required this.body,
  });

  final String key;
  final String kind;
  final Map<String, Object?> body;
}

/// One in-flight financial envelope per owner and shop.
abstract class FinancialCommandLocker {
  Future<PendingFinancialCommand?> read(String userId, String shopId);

  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  );

  Future<void> clear(String userId, String shopId, String key);
}

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

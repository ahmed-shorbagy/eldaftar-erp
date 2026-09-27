/// How a retained confirm attempt may be used after a restart.
enum PendingDisposition {
  /// The response is unknown. The payload and key stay frozen.
  unresolved,

  /// The server rejected the payload without consuming the key.
  validationRejected,

  /// The command was acknowledged. Do not post again; reread the ledger.
  acknowledged,
}

/// One retained confirm attempt. Only the key, payload, and disposition.
final class PendingOpening {
  const PendingOpening({
    required this.idempotencyKey,
    required this.payload,
    this.disposition = PendingDisposition.unresolved,
    this.operationId,
    this.rejectionCode,
  });

  final String idempotencyKey;
  final Map<String, Object?> payload;
  final PendingDisposition disposition;
  final String? operationId;
  final String? rejectionCode;
}

/// Shop-and-user scoped store. Sign-out must not delete an unresolved key.
abstract class PendingOpeningStore {
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  });

  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  });

  /// Drops a completed attempt so a later read is not tied to it.
  Future<void> retire({required String userId, required String shopId});
}

/// Device-local draft of the owner's physical close counts (U1).
///
/// A draft is only typed text, never a financial fact: it is keyed to the
/// user, shop, day and day version, so a changed day starts with blank counts.
abstract interface class CloseCountDrafts {
  Future<Map<String, String>?> read(DraftScope scope);
  Future<void> write(DraftScope scope, Map<String, String> fields);
  Future<void> clear(DraftScope scope);
}

final class DraftScope {
  const DraftScope({
    required this.userId,
    required this.shopId,
    required this.dayId,
    required this.dayVersion,
  });

  final String userId;
  final String shopId;
  final String dayId;
  final int dayVersion;

  String get storageKey =>
      'close-count-draft:$userId:$shopId:$dayId:$dayVersion';
}

/// In-memory drafts for tests and platforms without storage.
final class MemoryCloseCountDrafts implements CloseCountDrafts {
  final Map<String, Map<String, String>> stored = {};

  @override
  Future<Map<String, String>?> read(DraftScope scope) async =>
      stored[scope.storageKey];

  @override
  Future<void> write(DraftScope scope, Map<String, String> fields) async {
    if (fields.isEmpty) {
      stored.remove(scope.storageKey);
    } else {
      stored[scope.storageKey] = Map.of(fields);
    }
  }

  @override
  Future<void> clear(DraftScope scope) async => stored.remove(scope.storageKey);
}

import '../domain/daily_note_draft.dart';

final class StoredNoteDraft {
  const StoredNoteDraft({
    required this.userId,
    required this.shopId,
    required this.businessDayId,
    required this.idempotencyKey,
    required this.text,
    this.attachment,
  });

  final String userId;
  final String shopId;
  final String businessDayId;
  final String idempotencyKey;
  final String text;
  final NoteAttachmentRef? attachment;

  DailyNoteDraft toDraft() => DailyNoteDraft(
    idempotencyKey: idempotencyKey,
    shopId: shopId,
    businessDayId: businessDayId,
    text: text,
    attachment: attachment,
  );
}

abstract class NoteDraftStore {
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  });

  Future<void> save({required String userId, required DailyNoteDraft draft});

  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  });
}

abstract class NoteImageFileStore {
  Future<void> write({
    required String userId,
    required String shopId,
    required String clientObjectId,
    required List<int> bytes,
  });

  Future<List<int>?> read({
    required String userId,
    required String shopId,
    required String clientObjectId,
  });

  Future<void> delete({
    required String userId,
    required String shopId,
    required String clientObjectId,
  });
}

/// Adapters can keep confirmed cleanup atomic with replacement draft saves.
abstract interface class NoteDraftCleanupStore {
  Future<void> cleanupConfirmed({
    required String userId,
    required DailyNoteDraft draft,
    required NoteImageFileStore files,
  });
}

Future<void> cleanupConfirmedNote({
  required NoteDraftStore drafts,
  required NoteImageFileStore files,
  required String userId,
  required DailyNoteDraft draft,
}) async {
  try {
    if (drafts is NoteDraftCleanupStore) {
      await (drafts as NoteDraftCleanupStore).cleanupConfirmed(
        userId: userId,
        draft: draft,
        files: files,
      );
      return;
    }
    final current = await drafts.read(userId: userId, shopId: draft.shopId);
    final object = draft.attachment?.clientObjectId;
    if (object != null &&
        (current == null ||
            current.idempotencyKey == draft.idempotencyKey ||
            current.attachment?.clientObjectId != object)) {
      try {
        await files.delete(
          userId: userId,
          shopId: draft.shopId,
          clientObjectId: object,
        );
      } catch (_) {}
    }
    await drafts.clear(
      userId: userId,
      shopId: draft.shopId,
      idempotencyKey: draft.idempotencyKey,
    );
  } catch (_) {
    // Server confirmation remains authoritative when local cleanup fails.
  }
}

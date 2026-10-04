sealed class NoteCommandResult {
  const NoteCommandResult();
}

final class NoteCommitted extends NoteCommandResult {
  const NoteCommitted({
    required this.noteId,
    required this.shopSequence,
    required this.replayed,
  });

  final String noteId;
  final String shopSequence;
  final bool replayed;
}

final class NoteRejected extends NoteCommandResult {
  const NoteRejected(this.code);
  final String code;
}

final class NoteUnknown extends NoteCommandResult {
  const NoteUnknown();
}

sealed class NoteStatusResult {
  const NoteStatusResult();
}

final class NoteStatusAbsent extends NoteStatusResult {
  const NoteStatusAbsent();
}

final class NoteStatusCompleted extends NoteStatusResult {
  const NoteStatusCompleted(this.noteId);
  final String noteId;
}

final class NoteStatusRejected extends NoteStatusResult {
  const NoteStatusRejected(this.code);
  final String code;
}

final class NoteStatusUnknown extends NoteStatusResult {
  const NoteStatusUnknown();
}

enum NoteUploadDisposition { stored, alreadyPresent, rejected, unknown }

final class NoteUploadResult {
  const NoteUploadResult(this.disposition, {this.code});
  final NoteUploadDisposition disposition;
  final String? code;
}

final class DailyNoteAttachmentView {
  const DailyNoteAttachmentView({
    required this.bucket,
    required this.objectName,
    required this.mimeType,
    required this.byteSize,
  });

  final String bucket;
  final String objectName;
  final String mimeType;
  final String byteSize;
}

final class DailyNoteView {
  const DailyNoteView({
    required this.noteId,
    required this.shopSequence,
    required this.businessDayId,
    required this.text,
    required this.actorDisplayName,
    required this.createdAt,
    required this.occurredAtShop,
    this.attachment,
  });

  final String noteId;
  final String shopSequence;
  final String businessDayId;
  final String text;
  final String actorDisplayName;
  final String createdAt;
  final String occurredAtShop;
  final DailyNoteAttachmentView? attachment;
}

final class DailyNotePage {
  const DailyNotePage({
    required this.shopId,
    required this.dayId,
    required this.limit,
    required this.hasMore,
    required this.serverSequence,
    required this.snapshotSequence,
    required this.items,
    this.nextBeforeSequence,
  });

  final String shopId;
  final String? dayId;
  final int limit;
  final bool hasMore;
  final String serverSequence;
  final String snapshotSequence;
  final String? nextBeforeSequence;
  final List<DailyNoteView> items;
}

class NoteReadException implements Exception {
  const NoteReadException([this.code]);
  final String? code;
}

/// Server commands for notes. Upload success is not note confirmation.
abstract class NotesGateway {
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  });

  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  });

  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  });

  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  });

  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  });

  /// A read URL lasting at most five minutes. Callers must not persist it.
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  });
}

abstract class NoteImageSource {
  Future<SelectedNoteImage?> pickImage();
}

final class SelectedNoteImage {
  const SelectedNoteImage({
    required this.name,
    required this.bytes,
    this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String? mimeType;
}

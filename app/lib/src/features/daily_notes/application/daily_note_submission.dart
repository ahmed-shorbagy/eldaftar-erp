import '../domain/daily_note_draft.dart';
import 'note_draft_store.dart';
import 'notes_gateway.dart';

enum NoteSubmitPhase {
  localDraft,
  uploading,
  uploadFailed,
  confirming,
  confirmed,
  rejected,
}

final class NoteSubmitOutcome {
  const NoteSubmitOutcome({
    required this.phase,
    required this.draft,
    this.noteId,
    this.code,
    this.messageAr,
  });

  final NoteSubmitPhase phase;
  final DailyNoteDraft draft;
  final String? noteId;
  final String? code;
  final String? messageAr;

  bool get isConfirmed => phase == NoteSubmitPhase.confirmed;
}

/// Sends one note. A stored object is not confirmation until the note RPC
/// or a status lookup by the same key says the note exists.
class DailyNoteSubmission {
  const DailyNoteSubmission({
    required NotesGateway gateway,
    required NoteDraftStore drafts,
    required NoteImageFileStore files,
  }) : _gateway = gateway,
       _drafts = drafts,
       _files = files;

  final NotesGateway _gateway;
  final NoteDraftStore _drafts;
  final NoteImageFileStore _files;

  Future<NoteSubmitOutcome> submit({
    required String userId,
    required String sessionShopId,
    required DailyNoteDraft draft,
    List<int>? imageBytes,
  }) async {
    if (draft.shopId.isEmpty || draft.shopId != sessionShopId) {
      return NoteSubmitOutcome(
        phase: NoteSubmitPhase.rejected,
        draft: draft,
        code: 'invalid_input',
        messageAr: noteFailureCopy('invalid_input'),
      );
    }
    try {
      // Publish an attachment envelope only after its image is recoverable.
      final attachment = draft.attachment;
      if (attachment != null && imageBytes != null) {
        if (imageBytes.length.toString() != attachment.byteSize) {
          return _localPersistence(draft);
        }
        await _files.write(
          userId: userId,
          shopId: draft.shopId,
          clientObjectId: attachment.clientObjectId,
          bytes: imageBytes,
        );
      }
      await _drafts.save(userId: userId, draft: draft);
    } catch (_) {
      return _localPersistence(draft);
    }
    final existing = await _gateway.noteStatus(
      callerUserId: userId,
      idempotencyKey: draft.idempotencyKey,
    );
    if (existing is NoteStatusCompleted) {
      await _finish(userId, draft);
      return NoteSubmitOutcome(
        phase: NoteSubmitPhase.confirmed,
        draft: draft,
        noteId: existing.noteId,
      );
    }
    if (existing is NoteStatusRejected) {
      return _rejected(draft, existing.code);
    }
    if (existing is NoteStatusUnknown) {
      return NoteSubmitOutcome(
        phase: NoteSubmitPhase.confirming,
        draft: draft,
        messageAr: 'بانتظار تأكيد الخادم. المسودة محفوظة وسيُعاد نفس الطلب.',
      );
    }
    final attachment = draft.attachment;
    if (attachment != null) {
      List<int>? bytes = imageBytes;
      if (bytes == null) {
        try {
          bytes = await _files.read(
            userId: userId,
            shopId: draft.shopId,
            clientObjectId: attachment.clientObjectId,
          );
        } catch (_) {
          return _localPersistence(draft);
        }
      }
      if (bytes == null || bytes.length.toString() != attachment.byteSize) {
        return NoteSubmitOutcome(
          phase: NoteSubmitPhase.uploadFailed,
          draft: draft,
          code: 'attachment_missing',
          messageAr: 'ملف الصورة المحفوظ غير متاح. لم تُنشأ ملاحظة جديدة.',
        );
      }
      final uploaded = await _gateway.uploadNoteImage(
        callerUserId: userId,
        objectName: attachment.objectName(
          shopId: draft.shopId,
          businessDayId: draft.businessDayId,
        ),
        mimeType: attachment.mimeType,
        bytes: bytes,
      );
      if (uploaded.disposition == NoteUploadDisposition.unknown) {
        final retry = await _gateway.uploadNoteImage(
          callerUserId: userId,
          objectName: attachment.objectName(
            shopId: draft.shopId,
            businessDayId: draft.businessDayId,
          ),
          mimeType: attachment.mimeType,
          bytes: bytes,
        );
        if (retry.disposition != NoteUploadDisposition.stored &&
            retry.disposition != NoteUploadDisposition.alreadyPresent) {
          return NoteSubmitOutcome(
            phase: NoteSubmitPhase.uploading,
            draft: draft,
            messageAr: 'جارٍ رفع الصورة. لم تُحفظ الملاحظة بعد.',
          );
        }
      } else if (uploaded.disposition == NoteUploadDisposition.rejected) {
        return NoteSubmitOutcome(
          phase: NoteSubmitPhase.uploadFailed,
          draft: draft,
          code: uploaded.code ?? 'attachment_rejected',
          messageAr: 'تعذر رفع الصورة. المسودة محفوظة على هذا الجهاز.',
        );
      }
    }
    return _confirm(userId, draft);
  }

  Future<NoteSubmitOutcome> _confirm(
    String userId,
    DailyNoteDraft draft,
  ) async {
    final posted = await _gateway.postNote(
      callerUserId: userId,
      idempotencyKey: draft.idempotencyKey,
      payload: draft.canonicalPayload(),
    );
    if (posted is NoteCommitted) {
      await _finish(userId, draft);
      return NoteSubmitOutcome(
        phase: NoteSubmitPhase.confirmed,
        draft: draft,
        noteId: posted.noteId,
      );
    }
    if (posted is NoteRejected) {
      return _rejected(draft, posted.code);
    }
    final status = await _gateway.noteStatus(
      callerUserId: userId,
      idempotencyKey: draft.idempotencyKey,
    );
    if (status is NoteStatusCompleted) {
      await _finish(userId, draft);
      return NoteSubmitOutcome(
        phase: NoteSubmitPhase.confirmed,
        draft: draft,
        noteId: status.noteId,
      );
    }
    if (status is NoteStatusRejected) {
      return _rejected(draft, status.code);
    }
    return NoteSubmitOutcome(
      phase: NoteSubmitPhase.confirming,
      draft: draft,
      messageAr: 'بانتظار تأكيد الخادم. المسودة محفوظة وسيُعاد نفس الطلب.',
    );
  }

  NoteSubmitOutcome _rejected(DailyNoteDraft draft, String code) =>
      NoteSubmitOutcome(
        phase: NoteSubmitPhase.rejected,
        draft: draft,
        code: code,
        messageAr: noteFailureCopy(code),
      );

  Future<void> _finish(String userId, DailyNoteDraft draft) async {
    await cleanupConfirmedNote(
      drafts: _drafts,
      files: _files,
      userId: userId,
      draft: draft,
    );
  }

  NoteSubmitOutcome _localPersistence(DailyNoteDraft draft) =>
      NoteSubmitOutcome(
        phase: NoteSubmitPhase.localDraft,
        draft: draft,
        code: 'local_persistence',
        messageAr: noteFailureCopy('local_persistence'),
      );
}

String noteFailureCopy(String? code) => switch (code) {
  'unauthenticated' => 'يلزم تسجيل الدخول',
  'session_expired' => 'انتهت الجلسة',
  'forbidden' => 'غير مسموح',
  'shop_unavailable' => 'بيانات المحل غير متاحة',
  'shop_not_active' => 'الاشتراك غير نشط. المسودة محفوظة.',
  'invalid_input' => 'البيانات المدخلة غير صالحة',
  'overflow' => 'النص أطول من الحد المسموح',
  'payload_mismatch' => 'المفتاح لا يطابق الملاحظة المحفوظة',
  'note_empty' => 'أدخل نصاً أو أرفق صورة',
  'attachment_missing' => 'الصورة غير موجودة على الخادم. المسودة محفوظة.',
  'attachment_rejected' => 'الصورة غير مقبولة. المسودة محفوظة.',
  'stale_day' => 'اليوم المفتوح تغيّر. المسودة ما زالت هنا.',
  'day_closed' => 'اليوم مقفل. لا تُضاف ملاحظة إلا في اليوم المفتوح.',
  'local_persistence' =>
    'تعذر حفظ المسودة على هذا الجهاز. النص والصورة ما زالا هنا.',
  _ => 'تعذر حفظ الملاحظة. المسودة ما زالت على هذا الجهاز.',
};

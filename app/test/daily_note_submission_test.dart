import 'dart:io';

import 'package:eldafttar/src/features/daily_notes/application/daily_note_submission.dart';
import 'package:eldafttar/src/features/daily_notes/application/note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/data/note_image_file_store.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const user = 'owner-a';
const key = '11111111-1111-4111-8111-111111111111';
const shop = '22222222-2222-4222-8222-222222222222';
const otherShop = '55555555-5555-4555-8555-555555555555';
const day = '33333333-3333-4333-8333-333333333333';
const objectId = '44444444-4444-4444-8444-444444444444';

DailyNoteDraft textDraft() => composeDailyNote(
  idempotencyKey: key,
  shopId: shop,
  businessDayId: day,
  text: 'ملاحظة',
).draft!;

DailyNoteDraft imageDraft() => composeDailyNote(
  idempotencyKey: key,
  shopId: shop,
  businessDayId: day,
  text: '',
  clientObjectId: objectId,
  fileName: 'note.jpg',
  bytes: const [1, 2, 3, 4],
).draft!;

class MemoryDrafts implements NoteDraftStore {
  StoredNoteDraft? saved;
  int clears = 0;
  bool failClear = false;
  bool failSave = false;

  @override
  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  }) async {
    if (failClear) throw StateError('local');
    if (saved?.idempotencyKey == idempotencyKey) {
      saved = null;
      clears += 1;
    }
  }

  @override
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  }) async => saved;

  @override
  Future<void> save({
    required String userId,
    required DailyNoteDraft draft,
  }) async {
    if (failSave) throw StateError('local');
    saved = StoredNoteDraft(
      userId: userId,
      shopId: draft.shopId,
      businessDayId: draft.businessDayId,
      idempotencyKey: draft.idempotencyKey,
      text: draft.text,
      attachment: draft.attachment,
    );
  }
}

class ScriptNotes implements NotesGateway {
  NoteStatusResult status = const NoteStatusAbsent();
  NoteCommandResult command = const NoteCommitted(
    noteId: '66666666-6666-4666-8666-666666666666',
    shopSequence: '4',
    replayed: false,
  );
  List<NoteUploadDisposition> uploads = [NoteUploadDisposition.stored];
  int posts = 0;
  int statusCalls = 0;
  int uploadCalls = 0;

  @override
  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) => throw UnimplementedError();

  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) => throw UnimplementedError();

  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  }) => throw UnimplementedError();

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    statusCalls += 1;
    return status;
  }

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    posts += 1;
    return command;
  }

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final disposition = uploads[uploadCalls.clamp(0, uploads.length - 1)];
    uploadCalls += 1;
    return NoteUploadResult(disposition);
  }
}

void main() {
  late Directory root;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('eldafttar-note-');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test(
    'asks by key before creating and confirms only from the note RPC',
    () async {
      final drafts = MemoryDrafts();
      final gateway = ScriptNotes();
      final files = ApplicationNoteImageFileStore(directory: () async => root);
      final submission = DailyNoteSubmission(
        gateway: gateway,
        drafts: drafts,
        files: files,
      );
      final outcome = await submission.submit(
        userId: user,
        sessionShopId: shop,
        draft: textDraft(),
      );
      expect(gateway.statusCalls, 1);
      expect(gateway.posts, 1);
      expect(outcome.isConfirmed, isTrue);
      expect(outcome.phase, NoteSubmitPhase.confirmed);
      expect(drafts.saved, isNull);

      gateway.status = const NoteStatusCompleted(
        '66666666-6666-4666-8666-666666666666',
      );
      gateway.posts = 0;
      final replay = await submission.submit(
        userId: user,
        sessionShopId: shop,
        draft: textDraft(),
      );
      expect(replay.isConfirmed, isTrue);
      expect(gateway.posts, 0);
    },
  );

  test(
    'keeps the draft when status is unknown or the payload mismatches',
    () async {
      final drafts = MemoryDrafts();
      final gateway = ScriptNotes()..status = const NoteStatusUnknown();
      final submission = DailyNoteSubmission(
        gateway: gateway,
        drafts: drafts,
        files: ApplicationNoteImageFileStore(directory: () async => root),
      );
      final unknown = await submission.submit(
        userId: user,
        sessionShopId: shop,
        draft: textDraft(),
      );
      expect(unknown.phase, NoteSubmitPhase.confirming);
      expect(gateway.posts, 0);
      expect(drafts.saved?.idempotencyKey, key);

      gateway.status = const NoteStatusAbsent();
      gateway.command = const NoteRejected('stale_day');
      final stale = await submission.submit(
        userId: user,
        sessionShopId: shop,
        draft: textDraft(),
      );
      expect(stale.phase, NoteSubmitPhase.rejected);
      expect(stale.messageAr, noteFailureCopy('stale_day'));
      expect(drafts.saved?.text, 'ملاحظة');
    },
  );

  test(
    'reconciles a lost upload without treating storage success as the note',
    () async {
      final drafts = MemoryDrafts();
      final gateway = ScriptNotes()
        ..uploads = [
          NoteUploadDisposition.unknown,
          NoteUploadDisposition.alreadyPresent,
        ]
        ..command = const NoteUnknown();
      final submission = DailyNoteSubmission(
        gateway: gateway,
        drafts: drafts,
        files: ApplicationNoteImageFileStore(directory: () async => root),
      );
      final outcome = await submission.submit(
        userId: user,
        sessionShopId: shop,
        draft: imageDraft(),
        imageBytes: const [1, 2, 3, 4],
      );
      expect(gateway.uploadCalls, 2);
      expect(gateway.posts, 1);
      expect(outcome.isConfirmed, isFalse);
      expect(outcome.phase, NoteSubmitPhase.confirming);
      expect(drafts.saved?.attachment?.clientObjectId, objectId);
    },
  );

  test('does not upload a draft for another shop', () async {
    final gateway = ScriptNotes();
    final submission = DailyNoteSubmission(
      gateway: gateway,
      drafts: MemoryDrafts(),
      files: ApplicationNoteImageFileStore(directory: () async => root),
    );
    final outcome = await submission.submit(
      userId: user,
      sessionShopId: otherShop,
      draft: imageDraft(),
      imageBytes: const [1, 2, 3, 4],
    );
    expect(outcome.code, 'invalid_input');
    expect(gateway.uploadCalls, 0);
    expect(gateway.posts, 0);
  });

  test('local save failure does not post and keeps the draft bytes', () async {
    final drafts = MemoryDrafts()..failSave = true;
    final gateway = ScriptNotes();
    final submission = DailyNoteSubmission(
      gateway: gateway,
      drafts: drafts,
      files: ApplicationNoteImageFileStore(directory: () async => root),
    );
    final outcome = await submission.submit(
      userId: user,
      sessionShopId: shop,
      draft: imageDraft(),
      imageBytes: const [1, 2, 3, 4],
    );
    expect(outcome.code, 'local_persistence');
    expect(outcome.messageAr, noteFailureCopy('local_persistence'));
    expect(outcome.phase, NoteSubmitPhase.localDraft);
    expect(gateway.posts, 0);
    expect(gateway.uploadCalls, 0);
    expect(outcome.draft.attachment?.clientObjectId, objectId);
  });

  test('a committed note stays confirmed when local cleanup throws', () async {
    final drafts = MemoryDrafts()..failClear = true;
    final gateway = ScriptNotes();
    final submission = DailyNoteSubmission(
      gateway: gateway,
      drafts: drafts,
      files: _ThrowingFiles(),
    );
    final outcome = await submission.submit(
      userId: user,
      sessionShopId: shop,
      draft: imageDraft(),
      imageBytes: const [1, 2, 3, 4],
    );
    expect(outcome.isConfirmed, isTrue);
    expect(gateway.posts, 1);
    expect(drafts.saved?.idempotencyKey, key);
    expect(drafts.clears, 0);
  });
}

class _ThrowingFiles implements NoteImageFileStore {
  @override
  Future<void> delete({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async {
    throw StateError('local');
  }

  @override
  Future<List<int>?> read({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async => const [1, 2, 3, 4];

  @override
  Future<void> write({
    required String userId,
    required String shopId,
    required String clientObjectId,
    required List<int> bytes,
  }) async {}
}

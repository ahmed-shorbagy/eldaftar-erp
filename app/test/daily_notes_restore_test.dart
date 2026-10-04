import 'dart:async';

import 'package:eldafttar/src/features/daily_notes/application/note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_note_copy.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_notes_widget_test.dart' as fixtures;

const restoredAttachment = NoteAttachmentRef(
  clientObjectId: '88888888-8888-4888-8888-888888888888',
  mimeType: 'image/jpeg',
  extension: 'jpg',
  byteSize: '4',
);

StoredNoteDraft storedDraft({bool image = true}) => StoredNoteDraft(
  userId: fixtures.userId,
  shopId: fixtures.shopId,
  businessDayId: fixtures.dayId,
  idempotencyKey: fixtures.pendingKey,
  text: 'النص الأصلي',
  attachment: image ? restoredAttachment : null,
);

class RestoreDrafts extends fixtures.MemoryDrafts {
  Completer<StoredNoteDraft?>? readGate;
  bool failRead = false;
  int reads = 0;
  int saves = 0;
  final cleared = <(String, String, String)>[];

  @override
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  }) async {
    reads++;
    if (failRead) throw StateError('storage unavailable');
    if (readGate != null) return readGate!.future;
    if (saved?.userId != userId || saved?.shopId != shopId) return null;
    return saved;
  }

  @override
  Future<void> save({
    required String userId,
    required DailyNoteDraft draft,
  }) async {
    saves++;
    await super.save(userId: userId, draft: draft);
  }

  @override
  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  }) async {
    cleared.add((userId, shopId, idempotencyKey));
    await super.clear(
      userId: userId,
      shopId: shopId,
      idempotencyKey: idempotencyKey,
    );
  }
}

class RestoreNotes extends fixtures.NoteScript {
  Completer<NoteStatusResult>? statusGate;
  bool failStatus = false;
  final lookups = <(String, String)>[];
  final commands = <(String, String)>[];
  final uploads = <(String, String, List<int>)>[];

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    lookups.add((callerUserId, idempotencyKey));
    if (failStatus) throw StateError('network unavailable');
    return statusGate == null ? statusResult : statusGate!.future;
  }

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) {
    commands.add((callerUserId, idempotencyKey));
    return super.postNote(
      callerUserId: callerUserId,
      idempotencyKey: idempotencyKey,
      payload: payload,
    );
  }

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    uploads.add((callerUserId, objectName, List.of(bytes)));
    return const NoteUploadResult(NoteUploadDisposition.stored);
  }
}

class RestoreImages extends fixtures.ScriptImages {
  int picks = 0;
  @override
  Future<SelectedNoteImage?> pickImage() async {
    picks++;
    return super.pickImage();
  }
}

TextField noteField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('daily-note-text')));
FilledButton saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('daily-note-save')));
OutlinedButton attachButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byKey(const Key('daily-note-attach')));
OutlinedButton reconcileButton(WidgetTester tester) => tester
    .widget<OutlinedButton>(find.byKey(const Key('daily-note-reconcile')));

Widget restoreScreen({
  required RestoreDrafts drafts,
  required RestoreNotes notes,
  fixtures.MemoryFiles? files,
  RestoreImages? images,
  Key? key,
  String user = fixtures.userId,
  String shop = fixtures.shopId,
  String? day = fixtures.dayId,
}) => DailyNotesScreen(
  key: key,
  gateway: notes,
  userId: user,
  shopId: shop,
  businessDayId: day,
  drafts: drafts,
  files: files ?? fixtures.MemoryFiles(),
  images: images ?? RestoreImages(),
);

void expectLocked(WidgetTester tester, {required bool saveLocked}) {
  expect(noteField(tester).enabled, isFalse);
  expect(attachButton(tester).onPressed, isNull);
  if (saveLocked) expect(saveButton(tester).onPressed, isNull);
}

void main() {
  testWidgets(
    'locks editing, image selection and save throughout read and reconciliation',
    (tester) async {
      final read = Completer<StoredNoteDraft?>();
      final status = Completer<NoteStatusResult>();
      final drafts = RestoreDrafts()..readGate = read;
      final notes = RestoreNotes()..statusGate = status;
      final images = RestoreImages();
      await fixtures.pumpApp(
        tester,
        restoreScreen(drafts: drafts, notes: notes, images: images),
      );
      expectLocked(tester, saveLocked: true);
      expect(find.text(DailyNoteCopy.restoring), findsOneWidget);
      await tester.tap(find.byKey(const Key('daily-note-attach')));
      await tester.tap(find.byKey(const Key('daily-note-save')));
      read.complete(storedDraft());
      await tester.pump();
      expect(noteField(tester).controller!.text, 'النص الأصلي');
      expectLocked(tester, saveLocked: true);
      expect(reconcileButton(tester).onPressed, isNull);
      expect(notes.lookups, [(fixtures.userId, fixtures.pendingKey)]);
      expect(images.picks, 0);
      expect(notes.posts, 0);
      expect(drafts.saves, 0);
      status.complete(const NoteStatusAbsent());
      await tester.pump();
      expect(noteField(tester).enabled, isTrue);
      expect(saveButton(tester).onPressed, isNotNull);
      expect(attachButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'confirmed restart cleans the exact key and attachment without posting',
    (tester) async {
      final drafts = RestoreDrafts()..saved = storedDraft();
      final notes = RestoreNotes()
        ..statusResult = const NoteStatusCompleted(fixtures.noteId);
      final files = fixtures.MemoryFiles();
      await files.write(
        userId: fixtures.userId,
        shopId: fixtures.shopId,
        clientObjectId: restoredAttachment.clientObjectId,
        bytes: [1, 2, 3, 4],
      );
      await fixtures.pumpApp(
        tester,
        restoreScreen(drafts: drafts, notes: notes, files: files),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(DailyNoteCopy.confirmed), findsOneWidget);
      expect(noteField(tester).controller!.text, isEmpty);
      expect(drafts.saved, isNull);
      expect(drafts.cleared, [
        (fixtures.userId, fixtures.shopId, fixtures.pendingKey),
      ]);
      expect(files.files, isEmpty);
      expect(notes.posts, 0);
      expect(drafts.saves, 0);
    },
  );

  testWidgets('cleanup cannot clear a replacement draft with a different key', (
    tester,
  ) async {
    final status = Completer<NoteStatusResult>();
    final drafts = RestoreDrafts()..saved = storedDraft(image: false);
    final notes = RestoreNotes()..statusGate = status;
    await fixtures.pumpApp(tester, restoreScreen(drafts: drafts, notes: notes));
    await tester.pump();
    drafts.saved = const StoredNoteDraft(
      userId: fixtures.userId,
      shopId: fixtures.shopId,
      businessDayId: fixtures.dayId,
      idempotencyKey: '99999999-9999-4999-8999-999999999999',
      text: 'مسودة أخرى',
    );
    status.complete(const NoteStatusCompleted(fixtures.noteId));
    await tester.pump();
    expect(drafts.saved!.text, 'مسودة أخرى');
    expect(drafts.cleared.single.$3, fixtures.pendingKey);
    expect(notes.posts, 0);
  });

  for (final unavailable in [false, true]) {
    testWidgets(
      '${unavailable ? 'unavailable' : 'unknown'} status preserves all fields; retry posts original attachment and key',
      (tester) async {
        final stored = storedDraft();
        final drafts = RestoreDrafts()..saved = stored;
        final notes = RestoreNotes()
          ..statusResult = const NoteStatusUnknown()
          ..failStatus = unavailable;
        final files = fixtures.MemoryFiles();
        final images = RestoreImages();
        await files.write(
          userId: fixtures.userId,
          shopId: fixtures.shopId,
          clientObjectId: restoredAttachment.clientObjectId,
          bytes: [1, 2, 3, 4],
        );
        await fixtures.pumpApp(
          tester,
          restoreScreen(
            drafts: drafts,
            notes: notes,
            files: files,
            images: images,
          ),
        );
        await tester.pump();
        expectLocked(tester, saveLocked: false);
        expect(noteField(tester).controller!.text, stored.text);
        expect(drafts.saved, same(stored));
        expect(drafts.saves, 0);
        expect(notes.posts, 0);
        expect(find.text(DailyNoteCopy.frozen), findsOneWidget);
        // Even an old captured callback or controller change cannot recompose
        // an uncertain request into another payload.
        noteField(tester).controller!.text = 'تغيير غير مسموح';
        notes.failStatus = false;
        notes.statusResult = const NoteStatusAbsent();
        notes.command = const NoteCommitted(
          noteId: fixtures.noteId,
          shopSequence: '8',
          replayed: false,
        );
        await tester.tap(find.byKey(const Key('daily-note-save')));
        await tester.pump();
        await tester.pump();
        expect(notes.commands, [(stored.userId, stored.idempotencyKey)]);
        expect(notes.postedPayload, stored.toDraft().canonicalPayload());
        expect(notes.uploads.single.$1, stored.userId);
        expect(
          notes.uploads.single.$2,
          restoredAttachment.objectName(
            shopId: stored.shopId,
            businessDayId: stored.businessDayId,
          ),
        );
        expect(notes.uploads.single.$3, [1, 2, 3, 4]);
        expect(images.picks, 0);
        expect(find.text(DailyNoteCopy.confirmed), findsOneWidget);
      },
    );
  }

  testWidgets(
    'reconciliation retry freezes on unknown, unlocks only on absent and blocks duplicate callbacks',
    (tester) async {
      final drafts = RestoreDrafts()..saved = storedDraft();
      final notes = RestoreNotes()..statusResult = const NoteStatusUnknown();
      await fixtures.pumpApp(
        tester,
        restoreScreen(drafts: drafts, notes: notes),
      );
      await tester.pump();
      final retry = reconcileButton(tester).onPressed!;
      final save = saveButton(tester).onPressed!;
      notes.statusGate = Completer<NoteStatusResult>();
      retry();
      retry();
      save();
      await tester.pump();
      expect(notes.lookups, hasLength(2));
      expectLocked(tester, saveLocked: true);
      expect(reconcileButton(tester).onPressed, isNull);
      notes.statusGate!.complete(const NoteStatusUnknown());
      await tester.pump();
      expectLocked(tester, saveLocked: false);
      notes.statusGate = null;
      notes.statusResult = const NoteStatusAbsent();
      await tester.tap(find.byKey(const Key('daily-note-reconcile')));
      await tester.pump();
      expect(noteField(tester).enabled, isTrue);
      expect(notes.posts, 0);
      expect(drafts.saves, 0);
    },
  );

  testWidgets(
    'storage read failure prevents overwriting an unread draft and retries safely',
    (tester) async {
      final original = storedDraft();
      final drafts = RestoreDrafts()
        ..saved = original
        ..failRead = true;
      final notes = RestoreNotes()..statusResult = const NoteStatusUnknown();
      final images = RestoreImages();
      await fixtures.pumpApp(
        tester,
        restoreScreen(drafts: drafts, notes: notes, images: images),
      );
      await tester.pump();
      expectLocked(tester, saveLocked: true);
      expect(find.text(DailyNoteCopy.restoreFailed), findsOneWidget);
      expect(find.text(DailyNoteCopy.retryRestore), findsOneWidget);
      await tester.tap(find.byKey(const Key('daily-note-save')));
      await tester.tap(find.byKey(const Key('daily-note-attach')));
      expect(notes.lookups, isEmpty);
      expect(drafts.saved, same(original));
      expect(drafts.saves, 0);
      expect(images.picks, 0);
      drafts.failRead = false;
      await tester.tap(find.byKey(const Key('daily-note-reconcile')));
      await tester.pump();
      expect(noteField(tester).controller!.text, original.text);
      expectLocked(tester, saveLocked: false);
      expect(drafts.saved, same(original));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected status does not authorize editing or a new request', (
    tester,
  ) async {
    final drafts = RestoreDrafts()..saved = storedDraft();
    final notes = RestoreNotes()
      ..statusResult = const NoteStatusRejected('forbidden');
    await fixtures.pumpApp(tester, restoreScreen(drafts: drafts, notes: notes));
    await tester.pump();
    expectLocked(tester, saveLocked: false);
    expect(notes.posts, 0);
    expect(drafts.saves, 0);
  });

  for (final action in ['save', 'attachment']) {
    testWidgets(
      '$action locks synchronously before status lookup and ignores duplicate stale callbacks',
      (tester) async {
        final drafts = RestoreDrafts()..saved = storedDraft();
        final notes = RestoreNotes();
        final images = RestoreImages();
        await fixtures.pumpApp(
          tester,
          restoreScreen(drafts: drafts, notes: notes, images: images),
        );
        await tester.pump();
        notes.statusGate = Completer<NoteStatusResult>();
        final save = saveButton(tester).onPressed!;
        final pick = attachButton(tester).onPressed!;
        final selected = action == 'save' ? save : pick;
        selected();
        save();
        pick();
        await tester.pump();
        expect(notes.lookups, hasLength(2));
        expectLocked(tester, saveLocked: true);
        expect(images.picks, 0);
        notes.statusGate!.complete(const NoteStatusUnknown());
        await tester.pump();
        expectLocked(tester, saveLocked: false);
        expect(notes.posts, 0);
        expect(drafts.saves, 0);
      },
    );
  }

  for (final change in ['owner', 'shop', 'day']) {
    for (final phase in ['read', 'status']) {
      testWidgets('late restore $phase ignored after $change changes', (
        tester,
      ) async {
        final key = GlobalKey();
        final drafts = RestoreDrafts()..saved = storedDraft();
        final notes = RestoreNotes();
        final read = Completer<StoredNoteDraft?>();
        final status = Completer<NoteStatusResult>();
        if (phase == 'read') drafts.readGate = read;
        if (phase == 'status') notes.statusGate = status;
        await fixtures.pumpApp(
          tester,
          restoreScreen(key: key, drafts: drafts, notes: notes),
        );
        await tester.pump();
        drafts.readGate = null;
        notes.statusGate = null;
        // The new scope has its own blocked storage read. The previous
        // generation must not unlock it, replace its text or clean a draft.
        final currentRead = Completer<StoredNoteDraft?>();
        drafts.readGate = currentRead;
        // For a day switch an already loaded pending draft is reconciled,
        // so hold that lookup instead of expecting another storage read.
        final currentStatus = Completer<NoteStatusResult>();
        if (change == 'day' && phase == 'status') {
          notes.statusGate = currentStatus;
        }
        await fixtures.pumpApp(
          tester,
          restoreScreen(
            key: key,
            drafts: drafts,
            notes: notes,
            user: change == 'owner' ? 'user-2' : fixtures.userId,
            shop: change == 'shop'
                ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
                : fixtures.shopId,
            day: change == 'day'
                ? 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
                : fixtures.dayId,
          ),
        );
        await tester.pump();
        if (phase == 'read') read.complete(storedDraft());
        if (phase == 'status') {
          status.complete(const NoteStatusCompleted(fixtures.noteId));
        }
        await tester.pump();
        expectLocked(tester, saveLocked: true);
        expect(find.text(DailyNoteCopy.confirmed), findsNothing);
        expect(drafts.cleared, isEmpty);
        expect(drafts.saves, 0);
        expect(notes.posts, 0);
        if (change != 'day' || phase == 'read') {
          expect(noteField(tester).controller!.text, isEmpty);
        }
        if (change == 'day' && phase == 'status') {
          currentStatus.complete(const NoteStatusUnknown());
        } else {
          currentRead.complete(null);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldafttar/src/features/daily_notes/data/secure_note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/data/note_image_file_store.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:eldafttar/src/features/daily_notes/application/daily_note_submission.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'daily_note_submission_test.dart' as fixtures;

const user = 'owner-a';
const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const key = '11111111-1111-4111-8111-111111111111';
const newerKey = '77777777-7777-4777-8777-777777777777';
const objectId = '44444444-4444-4444-8444-444444444444';

DailyNoteDraft draft([String id = key]) => DailyNoteDraft(
  idempotencyKey: id,
  shopId: shop,
  businessDayId: day,
  text: 'مسودة',
);

class PausedStorage extends FlutterSecureStorage {
  bool failDelete = false;
  Completer<void>? deleteEntered;
  Completer<void>? releaseDelete;
  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (failDelete) throw StateError('cleanup unavailable');
    deleteEntered?.complete();
    if (releaseDelete != null) await releaseDelete!.future;
    await super.delete(key: key);
  }
}

class FaultStorage extends FlutterSecureStorage {
  bool failWrite = false;
  int keyWrites = 0;
  Completer<void>? writeEntered;
  Completer<void>? releaseWrite;
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (failWrite) throw StateError('secure storage unavailable');
    if (key.startsWith('daily_note_image_key')) keyWrites++;
    writeEntered?.complete();
    if (releaseWrite != null) await releaseWrite!.future;
    await super.write(key: key, value: value);
  }
}

class DelayedCompleted extends fixtures.ScriptNotes {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    entered.complete();
    await release.future;
    return const NoteStatusCompleted(objectId);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'completed reconciliation with failed cleanup never reposts on retry',
    () async {
      final root = await Directory.systemTemp.createTemp('note-confirmed-');
      addTearDown(() => root.delete(recursive: true));
      final storage = PausedStorage()..failDelete = true;
      final store = SecureNoteDraftStore(storage: storage);
      final gateway = fixtures.ScriptNotes()
        ..status = const NoteStatusCompleted(objectId);
      final submission = DailyNoteSubmission(
        gateway: gateway,
        drafts: store,
        files: ApplicationNoteImageFileStore(directory: () async => root),
      );
      for (var retry = 0; retry < 2; retry++) {
        final outcome = await submission.submit(
          userId: user,
          sessionShopId: shop,
          draft: draft(),
        );
        expect(outcome.isConfirmed, isTrue);
        expect(
          (await store.read(userId: user, shopId: shop))?.idempotencyKey,
          key,
        );
      }
      expect(gateway.posts, 0);
      expect(gateway.uploadCalls, 0);
    },
  );

  test(
    'unknown status preserves persisted owner shop day key payload and image',
    () async {
      final root = await Directory.systemTemp.createTemp('note-unknown-');
      addTearDown(() => root.delete(recursive: true));
      const store = SecureNoteDraftStore();
      final files = ApplicationNoteImageFileStore(directory: () async => root);
      final original = fixtures.imageDraft();
      final gateway = fixtures.ScriptNotes()
        ..status = const NoteStatusUnknown();
      final outcome =
          await DailyNoteSubmission(
            gateway: gateway,
            drafts: store,
            files: files,
          ).submit(
            userId: user,
            sessionShopId: shop,
            draft: original,
            imageBytes: [1, 2, 3, 4],
          );
      final restored = (await store.read(userId: user, shopId: shop))!;
      expect(outcome.phase, NoteSubmitPhase.confirming);
      expect(restored.userId, user);
      expect(restored.shopId, shop);
      expect(restored.businessDayId, day);
      expect(restored.idempotencyKey, key);
      expect(
        restored.toDraft().canonicalPayload(),
        original.canonicalPayload(),
      );
      expect(
        await files.read(userId: user, shopId: shop, clientObjectId: objectId),
        [1, 2, 3, 4],
      );
      expect(gateway.posts, 0);
      expect(gateway.uploadCalls, 0);
    },
  );

  test('paused key initialization writes one shared 256-bit key', () async {
    final root = await Directory.systemTemp.createTemp('note-key-race-');
    addTearDown(() => root.delete(recursive: true));
    final storage = FaultStorage()
      ..writeEntered = Completer<void>()
      ..releaseWrite = Completer<void>();
    final a = ApplicationNoteImageFileStore(
      directory: () async => root,
      storage: storage,
    );
    final b = ApplicationNoteImageFileStore(
      directory: () async => root,
      storage: storage,
    );
    final first = a.write(
      userId: user,
      shopId: shop,
      clientObjectId: key,
      bytes: [1],
    );
    await storage.writeEntered!.future;
    final second = b.write(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
      bytes: [2],
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    storage.releaseWrite!.complete();
    await Future.wait([first, second]);
    expect(storage.keyWrites, 1);
    expect(
      base64Decode(
        (await storage.read(key: 'daily_note_image_key_${user}_$shop'))!,
      ),
      hasLength(32),
    );
    expect(await a.read(userId: user, shopId: shop, clientObjectId: objectId), [
      2,
    ]);
    expect(await b.read(userId: user, shopId: shop, clientObjectId: key), [1]);
  });

  test(
    'overlapping image replacement read delete and save remain ordered',
    () async {
      final root = await Directory.systemTemp.createTemp('note-file-race-');
      addTearDown(() => root.delete(recursive: true));
      final normal = ApplicationNoteImageFileStore(directory: () async => root);
      await normal.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [1],
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final paused = ApplicationNoteImageFileStore(
        directory: () async => root,
        writeEncryptedFile: (file, bytes) async {
          await file.writeAsBytes(bytes.take(12).toList(), flush: true);
          entered.complete();
          await release.future;
          await file.writeAsBytes(bytes, flush: true);
        },
      );
      final write = paused.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [2],
      );
      await entered.future;
      final read = normal.read(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
      );
      final delete = normal.delete(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
      );
      final newer = normal.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [3],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      await write;
      expect(await read, [2]);
      await Future.wait([delete, newer]);
      expect(
        await normal.read(userId: user, shopId: shop, clientObjectId: objectId),
        [3],
      );
    },
  );

  test(
    'draft and image scopes isolate owner shop and object including AAD copies',
    () async {
      const otherShop = '55555555-5555-4555-8555-555555555555';
      const store = SecureNoteDraftStore();
      await store.save(userId: user, draft: draft());
      expect(await store.read(userId: 'owner-b', shopId: shop), isNull);
      expect(await store.read(userId: user, shopId: otherShop), isNull);
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'daily_note_draft_${user}_$shop');
      await storage.write(key: 'daily_note_draft_owner-b_$shop', value: raw);
      await expectLater(
        store.read(userId: 'owner-b', shopId: shop),
        throwsFormatException,
      );
      final root = await Directory.systemTemp.createTemp('note-scope-');
      addTearDown(() => root.delete(recursive: true));
      final files = ApplicationNoteImageFileStore(directory: () async => root);
      await files.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [1, 2],
      );
      final folder = '${root.path}${Platform.pathSeparator}daily-note-images';
      final source = File(
        '$folder${Platform.pathSeparator}$user-$shop-$objectId.bin',
      );
      final secret = await storage.read(
        key: 'daily_note_image_key_${user}_$shop',
      );
      for (final scope in [
        ('owner-b', shop, objectId),
        (user, otherShop, objectId),
        (user, shop, key),
      ]) {
        await storage.write(
          key: 'daily_note_image_key_${scope.$1}_${scope.$2}',
          value: secret,
        );
        await source.copy(
          '$folder${Platform.pathSeparator}${scope.$1}-${scope.$2}-${scope.$3}.bin',
        );
        await expectLater(
          files.read(
            userId: scope.$1,
            shopId: scope.$2,
            clientObjectId: scope.$3,
          ),
          throwsFormatException,
        );
        await files.delete(
          userId: scope.$1,
          shopId: scope.$2,
          clientObjectId: scope.$3,
        );
        expect(
          await files.read(
            userId: user,
            shopId: shop,
            clientObjectId: objectId,
          ),
          [1, 2],
        );
      }
    },
  );

  test(
    'failed replacement draft write preserves original canonical request',
    () async {
      final storage = FaultStorage();
      final store = SecureNoteDraftStore(storage: storage);
      await store.save(userId: user, draft: draft());
      storage.failWrite = true;
      await expectLater(
        store.save(userId: user, draft: draft(newerKey)),
        throwsStateError,
      );
      expect(
        (await store.read(
          userId: user,
          shopId: shop,
        ))!.toDraft().canonicalPayload(),
        draft().canonicalPayload(),
      );
      expect(
        (await store.read(userId: user, shopId: shop))!.idempotencyKey,
        key,
      );
    },
  );

  test('read and old clear wait for an overlapping replacement save', () async {
    final storage = FaultStorage();
    final store = SecureNoteDraftStore(storage: storage);
    await store.save(userId: user, draft: draft());
    storage.writeEntered = Completer<void>();
    storage.releaseWrite = Completer<void>();
    final save = store.save(userId: user, draft: draft(newerKey));
    await storage.writeEntered!.future;
    final read = const SecureNoteDraftStore().read(userId: user, shopId: shop);
    final clear = store.clear(userId: user, shopId: shop, idempotencyKey: key);
    storage.releaseWrite!.complete();
    await save;
    expect((await read)?.idempotencyKey, newerKey);
    await clear;
    expect(
      (await store.read(userId: user, shopId: shop))?.idempotencyKey,
      newerKey,
    );
  });

  test(
    'failed initial image persistence cannot replace an older recoverable draft',
    () async {
      final root = await Directory.systemTemp.createTemp('note-initial-');
      addTearDown(() => root.delete(recursive: true));
      const store = SecureNoteDraftStore();
      await store.save(userId: user, draft: draft(newerKey));
      final files = ApplicationNoteImageFileStore(
        directory: () async => root,
        writeEncryptedFile: (file, bytes) async {
          await file.writeAsBytes(bytes.take(12).toList(), flush: true);
          throw const FileSystemException('interrupted');
        },
      );
      final gateway = fixtures.ScriptNotes();
      final outcome =
          await DailyNoteSubmission(
            gateway: gateway,
            drafts: store,
            files: files,
          ).submit(
            userId: user,
            sessionShopId: shop,
            draft: fixtures.imageDraft(),
            imageBytes: [1, 2, 3, 4],
          );
      expect(outcome.code, 'local_persistence');
      expect(gateway.posts, 0);
      expect(gateway.uploadCalls, 0);
      expect(
        (await store.read(userId: user, shopId: shop))?.idempotencyKey,
        newerKey,
      );
      expect(
        await files.read(userId: user, shopId: shop, clientObjectId: objectId),
        isNull,
      );
    },
  );

  test(
    'delayed old clear cannot erase a concurrently saved newer key',
    () async {
      final storage = PausedStorage();
      final oldStore = SecureNoteDraftStore(storage: storage);
      final newStore = SecureNoteDraftStore(storage: storage);
      await oldStore.save(userId: user, draft: draft());
      storage.deleteEntered = Completer<void>();
      storage.releaseDelete = Completer<void>();
      final clear = oldStore.clear(
        userId: user,
        shopId: shop,
        idempotencyKey: key,
      );
      await storage.deleteEntered!.future;
      final save = newStore.save(userId: user, draft: draft(newerKey));
      // Let the concurrent save reach the adapter while deletion is paused.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      storage.releaseDelete!.complete();
      await Future.wait([clear, save]);
      expect(
        (await newStore.read(userId: user, shopId: shop))?.idempotencyKey,
        newerKey,
      );
    },
  );

  test(
    'rejects unknown envelope fields and noncanonical attachment sizes',
    () async {
      const storage = FlutterSecureStorage();
      const store = SecureNoteDraftStore();
      for (final extra in [
        {'unexpected': true},
        {
          'attachment': {
            'client_object_id': objectId,
            'mime_type': 'image/png',
            'extension': 'png',
            'byte_size': '01',
          },
        },
        {
          'attachment': {
            'client_object_id': objectId,
            'mime_type': 'image/png',
            'extension': 'png',
            'byte_size': '0',
          },
        },
        {
          'attachment': {
            'client_object_id': objectId,
            'mime_type': 'image/png',
            'extension': 'png',
            'byte_size': '5242881',
          },
        },
      ]) {
        await storage.write(
          key: 'daily_note_draft_${user}_$shop',
          value: jsonEncode({
            'user_id': user,
            'shop_id': shop,
            'business_day_id': day,
            'idempotency_key': key,
            'text': 'مسودة',
            ...extra,
          }),
        );
        await expectLater(
          store.read(userId: user, shopId: shop),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'concurrent image key initialization across instances remains decryptable',
    () async {
      final root = await Directory.systemTemp.createTemp('note-integrity-');
      addTearDown(() => root.delete(recursive: true));
      final a = ApplicationNoteImageFileStore(directory: () async => root);
      final b = ApplicationNoteImageFileStore(directory: () async => root);
      await Future.wait([
        a.write(userId: user, shopId: shop, clientObjectId: key, bytes: [1, 2]),
        b.write(
          userId: user,
          shopId: shop,
          clientObjectId: objectId,
          bytes: [3, 4],
        ),
      ]);
      expect(await b.read(userId: user, shopId: shop, clientObjectId: key), [
        1,
        2,
      ]);
      expect(
        await a.read(userId: user, shopId: shop, clientObjectId: objectId),
        [3, 4],
      );
    },
  );

  test(
    'interrupted encrypted replacement preserves the previous image',
    () async {
      final root = await Directory.systemTemp.createTemp('note-interrupted-');
      addTearDown(() => root.delete(recursive: true));
      final normal = ApplicationNoteImageFileStore(directory: () async => root);
      await normal.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [1, 2],
      );
      final interrupted = ApplicationNoteImageFileStore(
        directory: () async => root,
        writeEncryptedFile: (file, bytes) async {
          await file.writeAsBytes(bytes.take(12).toList(), flush: true);
          throw const FileSystemException('interrupted write');
        },
      );
      await expectLater(
        interrupted.write(
          userId: user,
          shopId: shop,
          clientObjectId: objectId,
          bytes: [3, 4],
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await normal.read(userId: user, shopId: shop, clientObjectId: objectId),
        [1, 2],
      );
    },
  );

  test(
    'delayed completed cleanup preserves an image reused by a newer draft',
    () async {
      final root = await Directory.systemTemp.createTemp('note-cleanup-');
      addTearDown(() => root.delete(recursive: true));
      const store = SecureNoteDraftStore();
      final files = ApplicationNoteImageFileStore(directory: () async => root);
      final old = fixtures.imageDraft();
      await files.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: [1, 2, 3, 4],
      );
      final gateway = DelayedCompleted();
      final pending = DailyNoteSubmission(
        gateway: gateway,
        drafts: store,
        files: files,
      ).submit(userId: user, sessionShopId: shop, draft: old);
      await gateway.entered.future;
      await store.save(
        userId: user,
        draft: DailyNoteDraft(
          idempotencyKey: newerKey,
          shopId: shop,
          businessDayId: day,
          text: 'أحدث',
          attachment: old.attachment,
        ),
      );
      gateway.release.complete();
      expect((await pending).isConfirmed, isTrue);
      expect(gateway.posts, 0);
      expect(
        (await store.read(userId: user, shopId: shop))?.idempotencyKey,
        newerKey,
      );
      expect(
        await files.read(userId: user, shopId: shop, clientObjectId: objectId),
        [1, 2, 3, 4],
      );
    },
  );
}

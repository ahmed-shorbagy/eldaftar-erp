import 'dart:convert';
import 'dart:io';

import 'package:eldafttar/src/features/daily_notes/data/note_image_file_store.dart';
import 'package:eldafttar/src/features/daily_notes/data/secure_note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const user = 'owner-a';
const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const key = '11111111-1111-4111-8111-111111111111';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'persists the request without a signed URL or the financial pending key',
    () async {
      const store = SecureNoteDraftStore();
      final draft = composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: 'مسودة',
      ).draft!;
      await store.save(userId: user, draft: draft);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
      final raw = await const FlutterSecureStorage().read(
        key: 'daily_note_draft_${user}_$shop',
      );
      expect(raw, isNotNull);
      expect(raw!.contains('pending_financial'), isFalse);
      expect(raw.contains('signed'), isFalse);
      final restored = await const SecureNoteDraftStore().read(
        userId: user,
        shopId: shop,
      );
      expect(restored?.idempotencyKey, key);
      expect(restored?.text, 'مسودة');
      await store.clear(userId: user, shopId: shop, idempotencyKey: 'other');
      expect(
        (await store.read(userId: user, shopId: shop))?.idempotencyKey,
        key,
      );
      await store.clear(userId: user, shopId: shop, idempotencyKey: key);
      expect(await store.read(userId: user, shopId: shop), isNull);
    },
  );

  test('refuses a signed URL, session, or password in the envelope', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'daily_note_draft_${user}_$shop',
      value: jsonEncode({
        'user_id': user,
        'shop_id': shop,
        'business_day_id': day,
        'idempotency_key': key,
        'text': 'https://storage.example/object?token=secret',
      }),
    );
    await expectLater(
      () => const SecureNoteDraftStore().read(userId: user, shopId: shop),
      throwsFormatException,
    );
    await storage.write(
      key: 'daily_note_draft_${user}_$shop',
      value: jsonEncode({
        'user_id': user,
        'shop_id': shop,
        'password': 'hidden',
        'text': 'مسودة',
      }),
    );
    await expectLater(
      () => const SecureNoteDraftStore().read(userId: user, shopId: shop),
      throwsFormatException,
    );
  });

  test('encrypts image bytes with a fresh nonce and owner key', () async {
    final root = await Directory.systemTemp.createTemp('eldafttar-image-');
    final files = ApplicationNoteImageFileStore(directory: () async => root);
    const objectId = '44444444-4444-4444-8444-444444444444';
    const otherObject = '66666666-6666-4666-8666-666666666666';
    const plain = [9, 8, 7];
    await files.write(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
      bytes: plain,
    );
    expect(
      await files.read(userId: user, shopId: shop, clientObjectId: objectId),
      plain,
    );
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}daily-note-images',
    );
    final stored = File(
      '${folder.path}${Platform.pathSeparator}$user-$shop-$objectId.bin',
    );
    final first = await stored.readAsBytes();
    expect(first.sublist(0, 4), [0x45, 0x4e, 0x49, 0x31]);
    expect(first, isNot(plain));
    expect(first.length, greaterThan(plain.length));
    await files.write(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
      bytes: plain,
    );
    final second = await stored.readAsBytes();
    expect(second, isNot(first));
    expect(
      await files.read(userId: user, shopId: shop, clientObjectId: objectId),
      plain,
    );
    final tampered = await stored.readAsBytes();
    tampered[tampered.length - 1] ^= 0xff;
    await stored.writeAsBytes(tampered, flush: true);
    await expectLater(
      () => files.read(userId: user, shopId: shop, clientObjectId: objectId),
      throwsFormatException,
    );
    await files.write(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
      bytes: plain,
    );
    await files.write(
      userId: 'owner-b',
      shopId: shop,
      clientObjectId: otherObject,
      bytes: const [1, 2],
    );
    final copied = File(
      '${folder.path}${Platform.pathSeparator}owner-b-$shop-$objectId.bin',
    );
    await copied.writeAsBytes(await stored.readAsBytes(), flush: true);
    await expectLater(
      () =>
          files.read(userId: 'owner-b', shopId: shop, clientObjectId: objectId),
      throwsFormatException,
    );
    expect(
      await files.read(
        userId: 'owner-b',
        shopId: shop,
        clientObjectId: otherObject,
      ),
      [1, 2],
    );
    await const FlutterSecureStorage().delete(
      key: 'daily_note_image_key_${user}_$shop',
    );
    await expectLater(
      () => files.read(userId: user, shopId: shop, clientObjectId: objectId),
      throwsFormatException,
    );
    await const FlutterSecureStorage().write(
      key: 'daily_note_image_key_${user}_$shop',
      value: base64Encode(const [1, 2, 3]),
    );
    await expectLater(
      () => files.read(userId: user, shopId: shop, clientObjectId: objectId),
      throwsFormatException,
    );
    final sibling = File('${folder.path}${Platform.pathSeparator}sibling.bin');
    await sibling.writeAsBytes(const [4], flush: true);
    await files.delete(userId: user, shopId: shop, clientObjectId: objectId);
    expect(
      await files.read(userId: user, shopId: shop, clientObjectId: objectId),
      isNull,
    );
    expect(sibling.existsSync(), isTrue);
    expect(
      await files.read(
        userId: 'owner-b',
        shopId: shop,
        clientObjectId: otherObject,
      ),
      [1, 2],
    );
    final ownerKey = await const FlutterSecureStorage().read(
      key: 'daily_note_image_key_owner-b_$shop',
    );
    expect(ownerKey, isNotNull);
    expect(ownerKey!, isNot(contains('http')));
    expect(ownerKey, isNot(contains('token=')));
    expect(ownerKey, isNot(contains('signed')));
    await expectLater(
      () => files.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: const [],
      ),
      throwsFormatException,
    );
    await expectLater(
      () => files.write(
        userId: user,
        shopId: shop,
        clientObjectId: objectId,
        bytes: List<int>.filled(noteImageMaxBytes + 1, 7),
      ),
      throwsFormatException,
    );
    expect(stored.existsSync(), isFalse);
    await const FlutterSecureStorage().delete(
      key: 'daily_note_image_key_${user}_$shop',
    );
    await expectLater(
      () => files.write(
        userId: '../escape',
        shopId: shop,
        clientObjectId: objectId,
        bytes: const [1],
      ),
      throwsFormatException,
    );
    await expectLater(
      () => files.write(
        userId: user,
        shopId: '../escape',
        clientObjectId: objectId,
        bytes: const [1],
      ),
      throwsFormatException,
    );
    await files.write(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
      bytes: List<int>.filled(noteImageMaxBytes, 3),
    );
    final full = await files.read(
      userId: user,
      shopId: shop,
      clientObjectId: objectId,
    );
    expect(full, hasLength(noteImageMaxBytes));
    expect(full!.every((byte) => byte == 3), isTrue);
    final onDisk = await stored.readAsBytes();
    expect(onDisk.sublist(0, 4), [0x45, 0x4e, 0x49, 0x31]);
    expect(onDisk.length, greaterThan(noteImageMaxBytes));
    await root.delete(recursive: true);
  });
}

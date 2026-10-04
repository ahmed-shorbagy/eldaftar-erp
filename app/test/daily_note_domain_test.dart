import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const key = '11111111-1111-4111-8111-111111111111';
const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const objectId = '44444444-4444-4444-8444-444444444444';

void main() {
  test('accepts text or a jpeg image and keeps canonical strings', () {
    final text = composeDailyNote(
      idempotencyKey: key.toUpperCase(),
      shopId: shop.toUpperCase(),
      businessDayId: day.toUpperCase(),
      text: '  ملاحظة اليوم  ',
    );
    expect(text.isAccepted, isTrue);
    expect(text.draft!.idempotencyKey, key);
    expect(text.draft!.shopId, shop);
    expect(text.draft!.text, 'ملاحظة اليوم');
    expect(text.draft!.canonicalPayload()['attachment'], isNull);
    final image = composeDailyNote(
      idempotencyKey: key,
      shopId: shop,
      businessDayId: day,
      text: '',
      clientObjectId: objectId.toUpperCase(),
      fileName: 'counter.JPEG',
      bytes: List<int>.filled(noteImageMaxBytes, 7),
    );
    final attachment = image.draft!.attachment!;
    expect(attachment.mimeType, 'image/jpeg');
    expect(attachment.extension, 'jpg');
    expect(attachment.byteSize, '$noteImageMaxBytes');
    expect(attachment.byteSize, isA<String>());
    expect(
      attachment.objectName(shopId: shop, businessDayId: day),
      '$shop/$day/$objectId.jpg',
    );
  });

  test('rejects empty, overflow, controls, and a disagreeing image', () {
    expect(
      composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: '   ',
      ).code,
      'note_empty',
    );
    expect(
      composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: 'م' * (noteTextMaxChars + 1),
      ).code,
      'overflow',
    );
    expect(
      composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: 'سطر\u0001',
      ).code,
      'invalid_input',
    );
    expect(
      composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: 'صورة',
        clientObjectId: objectId,
        mimeType: 'image/png',
        fileName: 'photo.jpg',
        bytes: const [1, 2, 3],
      ).code,
      'attachment_rejected',
    );
    expect(
      composeDailyNote(
        idempotencyKey: key,
        shopId: shop,
        businessDayId: day,
        text: '',
        clientObjectId: objectId,
        fileName: 'photo.jpg',
        bytes: List<int>.filled(noteImageMaxBytes + 1, 1),
      ).code,
      'attachment_rejected',
    );
    expect(boundedNoteQuery('خاتم'), isTrue);
    expect(boundedNoteQuery('م' * (noteSearchMaxChars + 1)), isFalse);
  });
}

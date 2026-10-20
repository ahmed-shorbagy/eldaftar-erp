import 'dart:typed_data';

import 'package:eldafttar/src/features/invoice_appearance/domain/logo_bytes.dart';
import 'package:eldafttar/src/features/shop_accounts/application/shop_image_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gallery formats are compressed after selection', () async {
    final photo = img.Image(width: 3000, height: 1800);
    img.fill(photo, color: img.ColorRgba8(40, 80, 120, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(photo, quality: 90));
    final prepared = await compressShopPhoto(jpeg);
    final facts = inspectLogoBytes(prepared);
    expect(facts.mime, 'image/jpeg');
    expect(facts.width, lessThanOrEqualTo(shopImageMaxDimension));
    expect(facts.height, lessThanOrEqualTo(shopImageMaxDimension));
    expect(prepared.length, lessThanOrEqualTo(shopImageRpcBytes));
    expect(facts.width / facts.height, closeTo(3000 / 1800, 0.02));

    final small = img.Image(width: 32, height: 24);
    img.fill(small, color: img.ColorRgba8(200, 160, 90, 255));
    final webp = Uint8List.fromList(img.encodeWebP(small));
    final fromWebp = inspectLogoBytes(await compressShopPhoto(webp));
    expect(fromWebp.mime, 'image/jpeg');
    expect(fromWebp.width, 32);
    expect(fromWebp.height, 24);

    final gif = Uint8List.fromList(img.encodeGif(small));
    expect(inspectLogoBytes(await compressShopPhoto(gif)).mime, 'image/jpeg');

    final oversized = Uint8List(logoMaxBytes + 4096);
    oversized.setRange(0, jpeg.length, jpeg);
    final fromOversized = await compressShopPhoto(oversized);
    expect(fromOversized.length, lessThanOrEqualTo(shopImageRpcBytes));
    expect(
      inspectLogoBytes(fromOversized).width,
      lessThanOrEqualTo(shopImageMaxDimension),
    );
  });

  test('phone orientation is baked before the stored jpeg', () async {
    final landscape = img.Image(width: 40, height: 16);
    img.fill(landscape, color: img.ColorRgba8(12, 80, 40, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(landscape, quality: 90));
    final exif = img.ExifData();
    exif.imageIfd.orientation = 6;
    final tagged = img.injectJpgExif(jpeg, exif);
    expect(tagged, isNotNull);
    final facts = inspectLogoBytes(await compressShopPhoto(tagged!));
    expect(facts.width, 16);
    expect(facts.height, 40);
  });

  test('camera exif is stripped so strict storage accepts the jpeg', () async {
    final photo = img.Image(width: 640, height: 480);
    img.fill(photo, color: img.ColorRgba8(90, 40, 20, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(photo, quality: 92));
    final exif = img.ExifData();
    exif.imageIfd.orientation = 1;
    exif.imageIfd['Make'] = 'TestCam';
    exif.imageIfd['Model'] = 'ShopPhone';
    exif.imageIfd['DateTime'] = '2026:10:20 12:00:00';
    final tagged = img.injectJpgExif(jpeg, exif);
    expect(tagged, isNotNull);
    // Without stripping, encodeJpg would re-emit APP1 and fail inspectLogoBytes.
    expect(() => inspectLogoBytes(tagged!), throwsA(isA<LogoByteRejection>()));
    final prepared = await compressShopPhoto(tagged!);
    expect(inspectLogoBytes(prepared).mime, 'image/jpeg');
    expect(prepared.length, lessThanOrEqualTo(logoMaxBytes));
  });

  test('a file that is not an image is still rejected', () async {
    expect(
      () => compressShopPhoto(Uint8List(0)),
      throwsA(
        isA<LogoByteRejection>().having(
          (error) => error.code,
          'code',
          'logo_rejected',
        ),
      ),
    );
    expect(
      () => compressShopPhoto(Uint8List.fromList('<html>'.codeUnits)),
      throwsA(
        isA<LogoByteRejection>().having(
          (error) => error.code,
          'code',
          'logo_rejected',
        ),
      ),
    );
  });
}

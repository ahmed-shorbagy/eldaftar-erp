import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../../invoice_appearance/domain/logo_bytes.dart';

/// Header photos are shown at ~48 logical pixels. Keep the stored JPEG well
/// under the server ceiling (2048 px / 2 MiB) so the base64 RPC body stays
/// reliable on Supabase — shop images live in Postgres, not Cloudflare R2.
const shopImageMaxDimension = 1024;
const shopImageRpcBytes = 400 * 1024;

/// Decodes a gallery or camera file the user already selected, then compresses
/// it to a clean baseline JPEG for `set_shop_image_v1`.
///
/// Selection itself is not filtered by size or container format. EXIF / ICC are
/// stripped because strict server validation rejects JPEG APP1.
Future<Uint8List> compressShopPhoto(Uint8List source) async {
  if (source.isEmpty) {
    throw const LogoByteRejection('logo_rejected');
  }
  final decoded = await _decodeSelected(source);
  if (decoded == null || decoded.width < 1 || decoded.height < 1) {
    throw const LogoByteRejection('logo_rejected');
  }
  final encoded = _encodeWithinLimit(_fit(decoded, shopImageMaxDimension));
  inspectLogoBytes(encoded);
  return encoded;
}

Future<img.Image?> _decodeSelected(Uint8List source) async {
  try {
    final engine = await _decodeWithEngine(source);
    if (engine != null) return engine;
  } catch (_) {}
  return _decodeWithPackage(source);
}

img.Image? _decodeWithPackage(Uint8List source) {
  try {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    final frame = decoded.numFrames > 1 ? decoded.frames.first : decoded;
    final oriented = img.bakeOrientation(frame);
    _stripMetadata(oriented);
    return oriented;
  } catch (_) {
    return null;
  }
}

Future<img.Image?> _decodeWithEngine(Uint8List source) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 || height < 1) return null;
      final fitted = _fittedSize(width, height, shopImageMaxDimension);
      final codec = await descriptor.instantiateCodec(
        targetWidth: fitted.$1,
        targetHeight: fitted.$2,
      );
      try {
        final frame = await codec.getNextFrame();
        final bitmap = frame.image;
        try {
          final rgba = await bitmap.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (rgba == null) return null;
          final image = img.Image.fromBytes(
            width: bitmap.width,
            height: bitmap.height,
            bytes: rgba.buffer,
            bytesOffset: rgba.offsetInBytes,
            numChannels: 4,
          );
          _stripMetadata(image);
          return image;
        } finally {
          bitmap.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

void _stripMetadata(img.Image image) {
  image.exif = img.ExifData();
  image.iccProfile = null;
}

img.Image _fit(img.Image source, int maxEdge) {
  if (source.width <= maxEdge && source.height <= maxEdge) {
    _stripMetadata(source);
    return source;
  }
  final fitted = _fittedSize(source.width, source.height, maxEdge);
  final resized = img.copyResize(
    source,
    width: fitted.$1,
    height: fitted.$2,
    interpolation: img.Interpolation.average,
  );
  _stripMetadata(resized);
  return resized;
}

(int, int) _fittedSize(int width, int height, int maxEdge) {
  final longest = math.max(width, height);
  if (longest <= maxEdge) return (width, height);
  final scale = maxEdge / longest;
  return (
    math.max(1, (width * scale).round()),
    math.max(1, (height * scale).round()),
  );
}

Uint8List _encodeWithinLimit(img.Image image) {
  var current = image;
  var quality = 85;
  var encoded = _jpeg(current, quality);
  while (encoded.length > shopImageRpcBytes) {
    if (quality > 48) {
      quality -= 10;
      encoded = _jpeg(current, quality);
      continue;
    }
    final longest = math.max(current.width, current.height);
    final nextEdge = (longest * 0.75).round();
    if (nextEdge < 256 || nextEdge >= longest) break;
    current = _fit(current, nextEdge);
    quality = 70;
    encoded = _jpeg(current, quality);
  }
  if (encoded.isEmpty || encoded.length > logoMaxBytes) {
    throw const LogoByteRejection('image_too_large');
  }
  return encoded;
}

Uint8List _jpeg(img.Image image, int quality) {
  _stripMetadata(image);
  return Uint8List.fromList(
    img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420),
  );
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

import '../domain/logo_bytes.dart';

/// Re-encoded logo bytes. Nothing here is saved until the server confirms it.
final class PreparedLogo {
  const PreparedLogo({
    required this.bytes,
    required this.facts,
    required this.sha256,
  });

  final Uint8List bytes;
  final LogoFacts facts;
  final String sha256;

  String objectName(String shopId) => '$shopId/$sha256.${facts.extension}';
}

/// Header limits run before decode. Phone camera photos are downscaled and
/// re-encoded without EXIF so the stored bytes always satisfy the server
/// contract (PNG/JPEG, ≤2 MiB, ≤2048 px).
Future<PreparedLogo> prepareLogo(Uint8List source) async {
  // Source may include EXIF/orientation; only reject non-images and oversize files.
  inspectLogoSource(source);
  var decoded = img.decodeImage(source);
  if (decoded == null || decoded.frames.length != 1) {
    throw const LogoByteRejection('logo_rejected');
  }
  // Bake EXIF orientation so width/height match the visible photo.
  decoded = img.bakeOrientation(decoded);
  if (decoded.width > logoMaxDimension || decoded.height > logoMaxDimension) {
    final scale = logoMaxDimension / math.max(decoded.width, decoded.height);
    final width = math.max(1, (decoded.width * scale).round());
    final height = math.max(1, (decoded.height * scale).round());
    decoded = img.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
  }
  // Prefer JPEG for photos after resize; keep PNG only when the source was PNG
  // and stayed small enough. Camera shots are almost always JPEG.
  final preferPng = _looksLikePng(source) &&
      decoded.width * decoded.height <= 512 * 512;
  var encoded = Uint8List.fromList(
    preferPng
        ? img.encodePng(decoded)
        : img.encodeJpg(decoded, quality: 88),
  );
  if (preferPng) {
    encoded = pngAllowedChunks(encoded);
  }
  if (encoded.length > logoMaxBytes) {
    encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: 75));
  }
  if (encoded.length > logoMaxBytes) {
    throw const LogoByteRejection('image_too_large');
  }
  final facts = inspectLogoBytes(encoded);
  final digest = await Sha256().hash(encoded);
  final sha = digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return PreparedLogo(bytes: encoded, facts: facts, sha256: sha);
}

bool _looksLikePng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

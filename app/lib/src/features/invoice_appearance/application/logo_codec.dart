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

/// Header limits run before decode. The bytes returned have no EXIF and only
/// the PNG chunks the server accepts.
Future<PreparedLogo> prepareLogo(Uint8List source) async {
  final sourceFacts = inspectLogoSource(source);
  final decoded = img.decodeImage(source);
  if (decoded == null || decoded.frames.length != 1) {
    throw const LogoByteRejection('logo_rejected');
  }
  if (decoded.width != sourceFacts.width ||
      decoded.height != sourceFacts.height ||
      decoded.width > logoMaxDimension ||
      decoded.height > logoMaxDimension) {
    throw const LogoByteRejection('logo_rejected');
  }
  final encoded = Uint8List.fromList(
    sourceFacts.mime == 'image/png'
        ? img.encodePng(decoded)
        : img.encodeJpg(decoded, quality: 90),
  );
  final stripped = sourceFacts.mime == 'image/png'
      ? pngAllowedChunks(encoded)
      : encoded;
  final facts = inspectLogoBytes(stripped);
  if (facts.mime != sourceFacts.mime) {
    throw const LogoByteRejection('logo_rejected');
  }
  final digest = await Sha256().hash(stripped);
  final sha = digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return PreparedLogo(bytes: stripped, facts: facts, sha256: sha);
}

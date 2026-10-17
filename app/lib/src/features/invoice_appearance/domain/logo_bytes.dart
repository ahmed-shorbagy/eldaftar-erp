import 'dart:typed_data';

const logoMaxBytes = 2097152;
const logoMaxDimension = 2048;

final class LogoFacts {
  const LogoFacts({
    required this.mime,
    required this.width,
    required this.height,
  });

  final String mime;
  final int width;
  final int height;

  String get extension => mime == 'image/png' ? 'png' : 'jpg';
}

final class LogoByteRejection implements Exception {
  const LogoByteRejection(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Strict structure used for bytes that will be stored. PNG may contain only
/// IHDR, PLTE, tRNS, IDAT, and IEND. JPEG must be baseline or progressive and
/// must not contain an APP1/EXIF segment.
LogoFacts inspectLogoBytes(Uint8List bytes) => _inspect(bytes, strict: true);

/// Source check before re-encoding. Metadata chunks may exist here; animation,
/// non-images, and oversize dimensions may not.
LogoFacts inspectLogoSource(Uint8List bytes) => _inspect(bytes, strict: false);

LogoFacts _inspect(Uint8List bytes, {required bool strict}) {
  if (bytes.isEmpty || bytes.length > logoMaxBytes) {
    throw const LogoByteRejection('image_too_large');
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return _png(bytes, strict: strict);
  }
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return _jpeg(bytes, strict: strict);
  }
  throw const LogoByteRejection('logo_rejected');
}

LogoFacts _png(Uint8List bytes, {required bool strict}) {
  if (bytes.length < 8 ||
      bytes[4] != 0x0D ||
      bytes[5] != 0x0A ||
      bytes[6] != 0x1A ||
      bytes[7] != 0x0A) {
    throw const LogoByteRejection('logo_rejected');
  }
  var offset = 8;
  var sawHeader = false;
  var sawData = false;
  var sawEnd = false;
  var sawPalette = false;
  var color = 0;
  var width = 0;
  var height = 0;
  while (offset < bytes.length) {
    if (sawEnd || offset + 12 > bytes.length) {
      throw const LogoByteRejection('logo_rejected');
    }
    final length = _be32(bytes, offset);
    if (length < 0 || offset + 12 + length > bytes.length) {
      throw const LogoByteRejection('logo_rejected');
    }
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    const allowed = {'IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND'};
    const animation = {'acTL', 'fcTL', 'fdAT'};
    if (animation.contains(type) || (strict && !allowed.contains(type))) {
      throw const LogoByteRejection('logo_rejected');
    }
    if (!sawHeader && type != 'IHDR') {
      throw const LogoByteRejection('logo_rejected');
    }
    if (type == 'IHDR') {
      if (sawHeader || length != 13) {
        throw const LogoByteRejection('logo_rejected');
      }
      width = _be32(bytes, offset + 8);
      height = _be32(bytes, offset + 12);
      final depth = bytes[offset + 16];
      color = bytes[offset + 17];
      final compression = bytes[offset + 18];
      final filter = bytes[offset + 19];
      final interlace = bytes[offset + 20];
      if (!_pngDepth(color, depth) ||
          compression != 0 ||
          filter != 0 ||
          (interlace != 0 && interlace != 1) ||
          width < 1 ||
          height < 1 ||
          width > logoMaxDimension ||
          height > logoMaxDimension) {
        throw const LogoByteRejection('logo_rejected');
      }
      sawHeader = true;
    } else if (type == 'PLTE') {
      if (sawPalette ||
          sawData ||
          (color != 2 && color != 3 && color != 6) ||
          length < 3 ||
          length > 768 ||
          length % 3 != 0) {
        throw const LogoByteRejection('logo_rejected');
      }
      sawPalette = true;
    } else if (type == 'tRNS') {
      final valid = switch (color) {
        0 => length == 2,
        2 => length == 6,
        3 => sawPalette && length >= 1 && length <= 256,
        _ => false,
      };
      if (!valid) throw const LogoByteRejection('logo_rejected');
    } else if (type == 'IDAT') {
      if (length == 0 || (color == 3 && !sawPalette)) {
        throw const LogoByteRejection('logo_rejected');
      }
      sawData = true;
    } else if (type == 'IEND') {
      if (length != 0 || !sawData) {
        throw const LogoByteRejection('logo_rejected');
      }
      sawEnd = true;
    }
    offset += 12 + length;
  }
  if (!sawEnd) throw const LogoByteRejection('logo_rejected');
  return LogoFacts(mime: 'image/png', width: width, height: height);
}

bool _pngDepth(int color, int depth) => switch (color) {
  0 => const {1, 2, 4, 8, 16}.contains(depth),
  2 => const {8, 16}.contains(depth),
  3 => const {1, 2, 4, 8}.contains(depth),
  4 => const {8, 16}.contains(depth),
  6 => const {8, 16}.contains(depth),
  _ => false,
};

LogoFacts _jpeg(Uint8List bytes, {required bool strict}) {
  var offset = 2;
  var frames = 0;
  var width = 0;
  var height = 0;
  var end = false;
  while (offset < bytes.length && !end) {
    if (bytes[offset] != 0xFF) {
      throw const LogoByteRejection('logo_rejected');
    }
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) {
      throw const LogoByteRejection('logo_rejected');
    }
    final marker = bytes[offset++];
    if (marker == 0xD8) throw const LogoByteRejection('logo_rejected');
    if (marker == 0xD9) {
      end = true;
      break;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (offset + 2 > bytes.length) {
      throw const LogoByteRejection('logo_rejected');
    }
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) {
      throw const LogoByteRejection('logo_rejected');
    }
    if (marker == 0xE1 && strict) {
      throw const LogoByteRejection('logo_rejected');
    }
    const baseline = 0xC0;
    const progressive = 0xC2;
    const otherFrames = {
      0xC1,
      0xC3,
      0xC5,
      0xC6,
      0xC7,
      0xC9,
      0xCA,
      0xCB,
      0xCD,
      0xCE,
      0xCF,
    };
    if (marker == baseline ||
        marker == progressive ||
        otherFrames.contains(marker)) {
      if (marker != baseline && marker != progressive) {
        throw const LogoByteRejection('logo_rejected');
      }
      if (frames > 0 || length < 8) {
        throw const LogoByteRejection('logo_rejected');
      }
      height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width < 1 ||
          height < 1 ||
          width > logoMaxDimension ||
          height > logoMaxDimension) {
        throw const LogoByteRejection('logo_rejected');
      }
      frames++;
    }
    if (marker == 0xDA) {
      offset += length;
      while (offset < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }
        var markerAt = offset;
        while (markerAt < bytes.length && bytes[markerAt] == 0xFF) {
          markerAt++;
        }
        if (markerAt >= bytes.length) {
          throw const LogoByteRejection('logo_rejected');
        }
        final entropy = bytes[markerAt];
        if (entropy == 0x00) {
          offset = markerAt + 1;
          continue;
        }
        if (entropy == 0xD9) {
          end = true;
          offset = bytes.length;
          break;
        }
        if (entropy >= 0xD0 && entropy <= 0xD7) {
          offset = markerAt + 1;
          continue;
        }
        throw const LogoByteRejection('logo_rejected');
      }
      break;
    }
    offset += length;
  }
  if (!end || frames != 1) throw const LogoByteRejection('logo_rejected');
  return LogoFacts(mime: 'image/jpeg', width: width, height: height);
}

int _be32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// Keeps only the PNG chunks the server accepts, preserving each chunk's data
/// and CRC. Used after re-encoding so metadata chunks cannot reach storage.
Uint8List pngAllowedChunks(Uint8List bytes) {
  inspectLogoSource(bytes);
  final out = BytesBuilder();
  out.add(bytes.sublist(0, 8));
  var offset = 8;
  while (offset < bytes.length) {
    final length = _be32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final chunkEnd = offset + 12 + length;
    if (const {'IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND'}.contains(type)) {
      out.add(bytes.sublist(offset, chunkEnd));
    }
    offset = chunkEnd;
    if (type == 'IEND') break;
  }
  final stripped = out.toBytes();
  inspectLogoBytes(stripped);
  return stripped;
}

import 'dart:typed_data';

/// Current shop image for the ledger header. Absent means BrandMark fallback.
class ShopImage {
  const ShopImage({
    required this.shopId,
    required this.sha256,
    required this.mime,
    required this.width,
    required this.height,
    required this.bytes,
  });

  final String shopId;
  final String sha256;
  final String mime;
  final int width;
  final int height;
  final Uint8List bytes;
}

enum ShopImageFailure {
  rejected,
  tooLarge,
  unauthorized,
  unavailable,
  unknownOutcome,
}

class ShopImageException implements Exception {
  const ShopImageException(this.failure);
  final ShopImageFailure failure;
  @override
  String toString() => 'ShopImageException($failure)';
}

abstract class ShopImageGateway {
  Future<ShopImage?> readCurrent();
  Future<ShopImage> setImage(Uint8List preparedBytes);
  Future<void> clearImage();
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shop_image.dart';

class SupabaseShopImageGateway implements ShopImageGateway {
  const SupabaseShopImageGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<ShopImage?> readCurrent() async {
    _requireSession();
    try {
      final response = await _client
          .rpc('get_shop_image_v1')
          .timeout(const Duration(seconds: 20));
      return _parseOptional(response);
    } on ShopImageException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopImageException(_mapError(error));
    } catch (_) {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
  }

  @override
  Future<ShopImage> setImage(Uint8List preparedBytes) async {
    _requireSession();
    try {
      final response = await _client
          .rpc(
            'set_shop_image_v1',
            params: {'p_bytes': base64Encode(preparedBytes)},
          )
          .timeout(const Duration(seconds: 30));
      final image = _parseRequired(response, fallbackBytes: preparedBytes);
      return image;
    } on ShopImageException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopImageException(_mapError(error));
    } catch (_) {
      throw const ShopImageException(ShopImageFailure.unknownOutcome);
    }
  }

  @override
  Future<void> clearImage() async {
    _requireSession();
    try {
      await _client
          .rpc('clear_shop_image_v1')
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (error) {
      throw ShopImageException(_mapError(error));
    } catch (_) {
      throw const ShopImageException(ShopImageFailure.unknownOutcome);
    }
  }

  void _requireSession() {
    final session = _client.auth.currentSession;
    final userId = _client.auth.currentUser?.id;
    if (session == null ||
        session.isExpired ||
        userId == null ||
        userId.isEmpty) {
      throw const ShopImageException(ShopImageFailure.unauthorized);
    }
  }

  static ShopImageFailure _mapError(PostgrestException error) {
    final code = error.code ?? '';
    final message = error.message;
    if (code == 'PGRST301' || message.contains('JWT')) {
      return ShopImageFailure.unauthorized;
    }
    if (message.contains('image_too_large')) {
      return ShopImageFailure.tooLarge;
    }
    if (message.contains('logo_rejected') ||
        message.contains('logo_mismatch')) {
      return ShopImageFailure.rejected;
    }
    if (message.contains('unauthenticated') ||
        message.contains('session_expired') ||
        message.contains('forbidden')) {
      return ShopImageFailure.unauthorized;
    }
    return ShopImageFailure.unavailable;
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _sha = RegExp(r'^[0-9a-f]{64}$');

  static ShopImage? _parseOptional(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    if (map['present'] != true) return null;
    return _parseRequired(map);
  }

  static ShopImage _parseRequired(Object? value, {Uint8List? fallbackBytes}) {
    if (value is! Map) {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
    final map = Map<String, dynamic>.from(value);
    final shopId = map['shop_id'];
    final sha = map['sha256'];
    final mime = map['mime'];
    final widthRaw = map['width'];
    final heightRaw = map['height'];
    final width = widthRaw is int
        ? widthRaw
        : widthRaw is num
        ? widthRaw.toInt()
        : null;
    final height = heightRaw is int
        ? heightRaw
        : heightRaw is num
        ? heightRaw.toInt()
        : null;
    final encoded = map['content_base64'];
    if (shopId is! String ||
        !_uuid.hasMatch(shopId) ||
        sha is! String ||
        !_sha.hasMatch(sha) ||
        mime is! String ||
        (mime != 'image/png' && mime != 'image/jpeg') ||
        width == null ||
        height == null ||
        width < 1 ||
        height < 1) {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
    Uint8List bytes;
    if (encoded is String && encoded.isNotEmpty) {
      try {
        bytes = base64Decode(encoded);
      } catch (_) {
        throw const ShopImageException(ShopImageFailure.unavailable);
      }
    } else if (fallbackBytes != null) {
      bytes = fallbackBytes;
    } else {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
    return ShopImage(
      shopId: shopId,
      sha256: sha,
      mime: mime,
      width: width,
      height: height,
      bytes: bytes,
    );
  }
}

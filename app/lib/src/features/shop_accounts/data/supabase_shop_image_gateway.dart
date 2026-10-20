import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../invoice_appearance/domain/logo_bytes.dart';
import '../../media/data/r2_media_client.dart';
import '../domain/shop_image.dart';

/// Shop images live in Cloudflare R2. Save uploads the prepared JPEG to an
/// owner-scoped, content-addressed R2 key through a presigned URL, has the
/// r2-media function verify the stored object, then records only the key and
/// verified metadata in Postgres (`record_shop_image_v1`). Reads presign a
/// short-lived GET. Legacy rows still holding inline bytes
/// (`storage = 'postgres'`) remain readable as a fallback.
class SupabaseShopImageGateway implements ShopImageGateway {
  const SupabaseShopImageGateway(this._client, this._media);

  static const _kind = R2MediaKind.shopImage;

  final SupabaseClient _client;
  final R2MediaClient _media;

  @override
  Future<ShopImage?> readCurrent() async {
    _requireSession();
    Map<String, dynamic> map;
    try {
      final response = await _client
          .rpc('get_shop_image_v1')
          .timeout(const Duration(seconds: 20));
      final parsed = _asMap(response);
      if (parsed == null || parsed['present'] != true) return null;
      map = parsed;
    } on ShopImageException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopImageException(_mapPostgrest(error));
    } catch (_) {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
    return _materialize(map);
  }

  @override
  Future<ShopImage> setImage(Uint8List preparedBytes) async {
    _requireSession();
    if (preparedBytes.isEmpty) {
      throw const ShopImageException(ShopImageFailure.rejected);
    }
    final LogoFacts facts;
    try {
      facts = inspectLogoBytes(preparedBytes);
    } on LogoByteRejection {
      throw const ShopImageException(ShopImageFailure.rejected);
    }
    final sha = await R2MediaClient.sha256Hex(preparedBytes);
    try {
      final upload = await _media.presignUpload(
        kind: _kind,
        sha256: sha,
        mime: facts.mime,
      );
      await _media.putBytes(upload, preparedBytes);
      await _media.confirm(kind: _kind, objectKey: upload.objectKey);
      final response = await _client
          .rpc(
            'record_shop_image_v1',
            params: {
              'p_object_key': upload.objectKey,
              'p_sha256': sha,
              'p_mime': facts.mime,
              'p_width': facts.width,
              'p_height': facts.height,
              'p_byte_size': preparedBytes.length,
            },
          )
          .timeout(const Duration(seconds: 30));
      final map = _asMap(response);
      if (map == null) {
        throw const ShopImageException(ShopImageFailure.unknownOutcome);
      }
      return ShopImage(
        shopId: (map['shop_id'] ?? '').toString(),
        sha256: sha,
        mime: facts.mime,
        width: facts.width,
        height: facts.height,
        bytes: preparedBytes,
      );
    } on ShopImageException {
      rethrow;
    } on R2MediaException catch (error) {
      throw ShopImageException(_mapMedia(error));
    } on PostgrestException catch (error) {
      throw ShopImageException(_mapPostgrest(error));
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
      throw ShopImageException(_mapPostgrest(error));
    } catch (_) {
      throw const ShopImageException(ShopImageFailure.unknownOutcome);
    }
  }

  Future<ShopImage> _materialize(Map<String, dynamic> map) async {
    final shopId = map['shop_id']?.toString();
    final sha = map['sha256']?.toString();
    final mime = map['mime']?.toString();
    final width = _asInt(map['width']);
    final height = _asInt(map['height']);
    if (shopId == null ||
        !_uuid.hasMatch(shopId) ||
        sha == null ||
        !_sha.hasMatch(sha) ||
        mime == null ||
        (mime != 'image/png' && mime != 'image/jpeg') ||
        width == null ||
        height == null ||
        width < 1 ||
        height < 1) {
      throw const ShopImageException(ShopImageFailure.unavailable);
    }
    final storage = map['storage']?.toString() ?? 'postgres';
    final Uint8List bytes;
    if (storage == 'r2') {
      final objectKey = map['object_key']?.toString();
      if (objectKey == null || objectKey.isEmpty) {
        throw const ShopImageException(ShopImageFailure.unavailable);
      }
      try {
        final url = await _media.presignRead(kind: _kind, objectKey: objectKey);
        bytes = await _media.getBytes(url);
      } on R2MediaException catch (error) {
        throw ShopImageException(_mapMedia(error));
      }
    } else {
      final encoded = map['content_base64'];
      if (encoded is! String || encoded.isEmpty) {
        throw const ShopImageException(ShopImageFailure.unavailable);
      }
      try {
        bytes = base64Decode(encoded);
      } catch (_) {
        throw const ShopImageException(ShopImageFailure.unavailable);
      }
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

  static ShopImageFailure _mapMedia(R2MediaException error) =>
      switch (error.code) {
        'unauthenticated' || 'forbidden' => ShopImageFailure.unauthorized,
        'invalid_input' ||
        'media_rejected' ||
        'media_mismatch' => ShopImageFailure.rejected,
        'transfer' || 'media_missing' => ShopImageFailure.unknownOutcome,
        _ => ShopImageFailure.unavailable,
      };

  static ShopImageFailure _mapPostgrest(PostgrestException error) {
    final blob =
        '${error.code ?? ''} ${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    if (error.code == 'PGRST301' || blob.contains('jwt')) {
      return ShopImageFailure.unauthorized;
    }
    if (blob.contains('image_too_large')) return ShopImageFailure.tooLarge;
    if (blob.contains('logo_rejected') || blob.contains('logo_mismatch')) {
      return ShopImageFailure.rejected;
    }
    if (blob.contains('unauthenticated') ||
        blob.contains('session_expired') ||
        blob.contains('forbidden')) {
      return ShopImageFailure.unauthorized;
    }
    return ShopImageFailure.unavailable;
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _sha = RegExp(r'^[0-9a-f]{64}$');

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

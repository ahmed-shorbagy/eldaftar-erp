import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Media kinds accepted by the `r2-media` Edge Function.
abstract final class R2MediaKind {
  static const shopImage = 'shop_image';
  static const invoiceLogo = 'invoice_logo';
  static const noteImage = 'note_image';
}

/// Thrown when the r2-media function or the R2 transfer fails. [code] mirrors
/// the function error codes (`unauthenticated`, `forbidden`, `invalid_input`,
/// `unavailable`, `media_missing`, `media_rejected`, `media_mismatch`,
/// `shop_not_active`) plus `transfer` for a failed direct PUT/GET.
class R2MediaException implements Exception {
  const R2MediaException(this.code);
  final String code;
  @override
  String toString() => 'R2MediaException($code)';
}

/// A presigned upload target returned by the function.
class R2Upload {
  const R2Upload({
    required this.objectKey,
    required this.url,
    required this.headers,
  });

  final String objectKey;
  final Uri url;
  final Map<String, String> headers;
}

/// Facts the function verified by reading the object back from R2.
class R2ConfirmedObject {
  const R2ConfirmedObject({
    required this.objectKey,
    required this.sha256,
    required this.byteSize,
    required this.replayed,
  });

  final String objectKey;
  final String sha256;
  final int byteSize;
  final bool replayed;
}

/// Brokers presigned Cloudflare R2 URLs through the authenticated `r2-media`
/// Edge Function, then performs the direct byte transfer. R2 credentials never
/// reach the client; only short-lived signed URLs do. Every upload must be
/// confirmed before a domain RPC can reference it.
class R2MediaClient {
  R2MediaClient({
    required http.Client client,
    required String supabaseUrl,
    required String publishableKey,
    required String Function() accessToken,
  }) : _client = client,
       _functionUrl = _resolveFunctionUrl(supabaseUrl),
       _publishableKey = publishableKey,
       _accessToken = accessToken;

  final http.Client _client;
  final Uri _functionUrl;
  final String _publishableKey;
  final String Function() _accessToken;

  static const _requestTimeout = Duration(seconds: 20);
  static const _transferTimeout = Duration(seconds: 45);

  static Uri _resolveFunctionUrl(String supabaseUrl) {
    final trimmed = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    return Uri.parse('$trimmed/functions/v1/r2-media');
  }

  /// Content-addressed kinds pass [sha256]; note images pass [objectName]
  /// (`<shop>/<day>/<object>.<ext>`).
  Future<R2Upload> presignUpload({
    required String kind,
    required String mime,
    String? sha256,
    String? objectName,
  }) async {
    final body = await _call({
      'kind': kind,
      'op': 'upload',
      'mime': mime,
      'sha256': ?sha256,
      'object_name': ?objectName,
    });
    final objectKey = body['object_key'];
    final url = body['url'];
    if (objectKey is! String || url is! String) {
      throw const R2MediaException('unavailable');
    }
    final headers = <String, String>{};
    final rawHeaders = body['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key is String && value is String) headers[key] = value;
      });
    }
    return R2Upload(
      objectKey: objectKey,
      url: Uri.parse(url),
      headers: headers,
    );
  }

  Future<R2ConfirmedObject> confirm({
    required String kind,
    required String objectKey,
  }) async {
    final body = await _call({
      'kind': kind,
      'op': 'confirm',
      'object_key': objectKey,
    });
    final key = body['object_key'];
    final sha = body['sha256'];
    final size = body['byte_size'];
    final replayed = body['replayed'];
    if (key != objectKey ||
        sha is! String ||
        size is! num ||
        replayed is! bool) {
      throw const R2MediaException('unavailable');
    }
    return R2ConfirmedObject(
      objectKey: objectKey,
      sha256: sha,
      byteSize: size.toInt(),
      replayed: replayed,
    );
  }

  Future<Uri> presignRead({
    required String kind,
    required String objectKey,
  }) async {
    final body = await _call({
      'kind': kind,
      'op': 'read',
      'object_key': objectKey,
    });
    final url = body['url'];
    if (url is! String) throw const R2MediaException('unavailable');
    return Uri.parse(url);
  }

  Future<void> putBytes(R2Upload upload, List<int> bytes) async {
    http.Response response;
    try {
      response = await _client
          .put(upload.url, headers: upload.headers, body: bytes)
          .timeout(_transferTimeout);
    } catch (_) {
      throw const R2MediaException('transfer');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const R2MediaException('transfer');
    }
  }

  Future<Uint8List> getBytes(Uri url) async {
    http.Response response;
    try {
      response = await _client.get(url).timeout(_transferTimeout);
    } catch (_) {
      throw const R2MediaException('transfer');
    }
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw const R2MediaException('transfer');
    }
    return response.bodyBytes;
  }

  static Future<String> sha256Hex(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Map<String, dynamic>> _call(Map<String, Object?> payload) async {
    final token = _accessToken();
    if (token.isEmpty) throw const R2MediaException('unauthenticated');
    http.Response response;
    try {
      response = await _client
          .post(
            _functionUrl,
            headers: {
              'content-type': 'application/json',
              'apikey': _publishableKey,
              'authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      throw const R2MediaException('unavailable');
    }
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{};
    }
    if (response.statusCode == 200) return body;
    final code = body['code'];
    throw R2MediaException(code is String ? code : 'unavailable');
  }
}

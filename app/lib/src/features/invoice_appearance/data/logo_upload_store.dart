import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logo upload state is outside the financial command locker.
enum LogoUploadPhase { uploadPending, confirmPending, failed, confirmed }

final class LogoUploadRecord {
  const LogoUploadRecord({
    required this.phase,
    required this.sha256,
    required this.mime,
    required this.objectName,
    this.assetId,
    this.message,
    this.fromRegistration = false,
  });

  final LogoUploadPhase phase;
  final String sha256;
  final String mime;
  final String objectName;
  final String? assetId;
  final String? message;
  final bool fromRegistration;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'sha256': sha256,
    'mime': mime,
    'objectName': objectName,
    'assetId': assetId,
    'message': message,
    'fromRegistration': fromRegistration,
  };

  static LogoUploadRecord? parse(Object? raw) {
    if (raw is! Map) return null;
    final phase = LogoUploadPhase.values.where(
      (item) => item.name == raw['phase'],
    );
    if (phase.isEmpty ||
        raw['sha256'] is! String ||
        raw['mime'] is! String ||
        raw['objectName'] is! String) {
      return null;
    }
    return LogoUploadRecord(
      phase: phase.first,
      sha256: raw['sha256'] as String,
      mime: raw['mime'] as String,
      objectName: raw['objectName'] as String,
      assetId: raw['assetId'] as String?,
      message: raw['message'] as String?,
      fromRegistration: raw['fromRegistration'] == true,
    );
  }
}

abstract class LogoUploadStore {
  Future<LogoUploadRecord?> read(String userId, String shopId);
  Future<Uint8List?> readBytes(String userId, String shopId);
  Future<void> save(
    String userId,
    String shopId,
    LogoUploadRecord record,
    Uint8List bytes,
  );
  Future<void> clear(String userId, String shopId);
}

final class FileLogoUploadStore implements LogoUploadStore {
  const FileLogoUploadStore();

  String _key(String userId, String shopId) =>
      'invoice_logo_upload_${userId}_$shopId';

  Future<File> _file(String userId, String shopId) async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory('${root.path}/eldaftar-logo-uploads');
    if (!folder.existsSync()) await folder.create(recursive: true);
    return File('${folder.path}/$userId-$shopId.bin');
  }

  @override
  Future<LogoUploadRecord?> read(String userId, String shopId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId, shopId));
    if (raw == null) return null;
    try {
      return LogoUploadRecord.parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> readBytes(String userId, String shopId) async {
    final file = await _file(userId, shopId);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> save(
    String userId,
    String shopId,
    LogoUploadRecord record,
    Uint8List bytes,
  ) async {
    final file = await _file(userId, shopId);
    await file.writeAsBytes(bytes, flush: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(userId, shopId),
      jsonEncode(record.toJson()),
    );
  }

  @override
  Future<void> clear(String userId, String shopId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(userId, shopId));
    final file = await _file(userId, shopId);
    if (file.existsSync()) await file.delete();
  }
}

final class MemoryLogoUploadStore implements LogoUploadStore {
  LogoUploadRecord? record;
  Uint8List? bytes;

  @override
  Future<void> clear(String userId, String shopId) async {
    record = null;
    bytes = null;
  }

  @override
  Future<LogoUploadRecord?> read(String userId, String shopId) async => record;

  @override
  Future<Uint8List?> readBytes(String userId, String shopId) async => bytes;

  @override
  Future<void> save(
    String userId,
    String shopId,
    LogoUploadRecord record,
    Uint8List bytes,
  ) async {
    this.record = record;
    this.bytes = bytes;
  }
}

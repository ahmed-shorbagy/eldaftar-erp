import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../application/note_draft_store.dart';
import '../domain/daily_note_draft.dart';
import 'note_persistence_queue.dart';

final _imageOperations = NotePersistenceQueue();

const _magic = [0x45, 0x4e, 0x49, 0x31];
final _algorithm = AesGcm.with256bits();
final _scopedId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
final _keyLoads = <String, Future<SecretKey>>{};

/// Private image bytes encrypted with AES-256-GCM.
/// The key lives in secure storage for one signed-in owner and shop.
final class ApplicationNoteImageFileStore implements NoteImageFileStore {
  ApplicationNoteImageFileStore({
    this.directory,
    this.writeEncryptedFile,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final Future<Directory> Function()? directory;

  /// File I/O injection for interrupted-write regression coverage.
  final Future<void> Function(File file, List<int> bytes)? writeEncryptedFile;
  final FlutterSecureStorage _storage;

  Future<Directory> _root() async {
    final base = directory == null
        ? await getApplicationSupportDirectory()
        : await directory!();
    final folder = Directory(
      '${base.path}${Platform.pathSeparator}daily-note-images',
    );
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  String _keyName(String userId, String shopId) =>
      'daily_note_image_key_${userId}_$shopId';

  String _operationScope(String userId, String shopId, String clientObjectId) {
    if (!_scopedId.hasMatch(userId) ||
        !isCanonicalNoteId(shopId) ||
        !isCanonicalNoteId(clientObjectId)) {
      throw const FormatException('note_image');
    }
    return '$userId/$shopId/$clientObjectId';
  }

  File _file(
    Directory root,
    String userId,
    String shopId,
    String clientObjectId,
  ) {
    _operationScope(userId, shopId, clientObjectId);
    final name = '$userId-$shopId-$clientObjectId.bin';
    if (name.contains('..') || name.contains(Platform.pathSeparator)) {
      throw const FormatException('note_image');
    }
    final file = File('${root.path}${Platform.pathSeparator}$name');
    final rootPath = root.absolute.path;
    final resolved = file.absolute.path;
    final prefix = rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
    if (!resolved.startsWith(prefix)) {
      throw const FormatException('note_image');
    }
    return file;
  }

  Future<SecretKey> _secretKey(String userId, String shopId) async {
    final name = _keyName(userId, shopId);
    final pending = _keyLoads.putIfAbsent(name, () => _createSecretKey(name));
    try {
      return await pending;
    } finally {
      if (identical(_keyLoads[name], pending)) _keyLoads.remove(name);
    }
  }

  Future<SecretKey> _createSecretKey(String name) async {
    final existing = await _storage.read(key: name);
    if (existing != null) {
      final decoded = _decodeKey(existing);
      return SecretKey(decoded);
    }
    final created = await _algorithm.newSecretKey();
    final bytes = await created.extractBytes();
    if (bytes.length != 32) throw const FormatException('note_image');
    await _storage.write(key: name, value: base64Encode(bytes));
    final stored = await _storage.read(key: name);
    if (stored == null) throw const FormatException('note_image');
    return SecretKey(_decodeKey(stored));
  }

  List<int> _decodeKey(String stored) {
    try {
      final decoded = base64Decode(stored);
      if (decoded.length != 32) throw const FormatException('note_image');
      return decoded;
    } on FormatException {
      throw const FormatException('note_image');
    }
  }

  @override
  Future<void> write({
    required String userId,
    required String shopId,
    required String clientObjectId,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > noteImageMaxBytes) {
      throw const FormatException('note_image');
    }
    // Enqueue before asynchronous directory I/O can reorder calls.
    return _imageOperations.run(
      _operationScope(userId, shopId, clientObjectId),
      () async {
        final file = _file(await _root(), userId, shopId, clientObjectId);
        final key = await _secretKey(userId, shopId);
        final box = await _algorithm.encrypt(
          bytes,
          secretKey: key,
          aad: utf8.encode('$userId/$shopId/$clientObjectId'),
        );
        if (box.nonce.length != 12 || box.mac.bytes.length != 16) {
          throw const FormatException('note_image');
        }
        final encrypted = <int>[
          ..._magic,
          ...box.nonce,
          ...box.mac.bytes,
          ...box.cipherText,
        ];
        // A failed or interrupted staging write never truncates the live image.
        final staged = File('${file.path}.pending');
        try {
          if (writeEncryptedFile != null) {
            await writeEncryptedFile!(staged, encrypted);
          } else {
            await staged.writeAsBytes(encrypted, flush: true);
          }
          await staged.rename(file.path);
        } finally {
          if (await staged.exists()) await staged.delete();
        }
      },
    );
  }

  @override
  Future<List<int>?> read({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async {
    return _imageOperations.run(
      _operationScope(userId, shopId, clientObjectId),
      () async {
        final file = _file(await _root(), userId, shopId, clientObjectId);
        if (!await file.exists()) return null;
        final length = await file.length();
        if (length <= 32 || length > noteImageMaxBytes + 32) {
          throw const FormatException('note_image');
        }
        final raw = await file.readAsBytes();
        if (raw.length <= 32 ||
            raw.length > noteImageMaxBytes + 32 ||
            raw[0] != _magic[0] ||
            raw[1] != _magic[1] ||
            raw[2] != _magic[2] ||
            raw[3] != _magic[3]) {
          throw const FormatException('note_image');
        }
        final stored = await _storage.read(key: _keyName(userId, shopId));
        if (stored == null) throw const FormatException('note_image');
        final nonce = raw.sublist(4, 16);
        final mac = raw.sublist(16, 32);
        final cipher = raw.sublist(32);
        try {
          final decoded = await _algorithm.decrypt(
            SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
            secretKey: SecretKey(_decodeKey(stored)),
            aad: utf8.encode('$userId/$shopId/$clientObjectId'),
          );
          if (decoded.isEmpty || decoded.length > noteImageMaxBytes) {
            throw const FormatException('note_image');
          }
          return decoded;
        } catch (_) {
          throw const FormatException('note_image');
        }
      },
    );
  }

  @override
  Future<void> delete({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async {
    return _imageOperations.run(
      _operationScope(userId, shopId, clientObjectId),
      () async {
        final file = _file(await _root(), userId, shopId, clientObjectId);
        if (await file.exists()) await file.delete();
      },
    );
  }
}

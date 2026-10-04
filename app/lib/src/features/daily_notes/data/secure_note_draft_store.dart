import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/note_draft_store.dart';
import '../domain/daily_note_draft.dart';
import 'note_persistence_queue.dart';

final _draftOperations = NotePersistenceQueue();
final _ownerId = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

/// One note draft per owner and shop. Signed URLs and sessions are refused.
final class SecureNoteDraftStore
    implements NoteDraftStore, NoteDraftCleanupStore {
  const SecureNoteDraftStore({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  String _storageKey(String userId, String shopId) {
    if (!_ownerId.hasMatch(userId) || !isCanonicalNoteId(shopId)) {
      throw const FormatException('note_draft');
    }
    return 'daily_note_draft_${userId}_$shopId';
  }

  @override
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  }) => _draftOperations.run(
    _storageKey(userId, shopId),
    () => _read(userId, shopId),
  );

  Future<StoredNoteDraft?> _read(String userId, String shopId) async {
    final raw = await storage.read(key: _storageKey(userId, shopId));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    _rejectSecrets(decoded);
    if (decoded is! Map) throw const FormatException('note_draft');
    final draftUser = decoded['user_id'];
    final draftShop = decoded['shop_id'];
    final day = decoded['business_day_id'];
    final key = decoded['idempotency_key'];
    final text = decoded['text'];
    const fields = {
      'user_id',
      'shop_id',
      'business_day_id',
      'idempotency_key',
      'text',
      'attachment',
    };
    if ((decoded.length != 6 && decoded.length != 5) ||
        decoded.keys.any((field) => !fields.contains(field))) {
      throw const FormatException('note_draft');
    }
    if (draftUser != userId ||
        draftShop != shopId ||
        day is! String ||
        key is! String ||
        text is! String ||
        !isCanonicalNoteId(draftShop) ||
        !isCanonicalNoteId(day) ||
        !isCanonicalNoteId(key)) {
      throw const FormatException('note_draft');
    }
    NoteAttachmentRef? attachment;
    if (decoded.containsKey('attachment')) {
      attachment = _attachment(decoded['attachment']);
    }
    _validateText(text, attachment);
    return StoredNoteDraft(
      userId: userId,
      shopId: shopId,
      businessDayId: day,
      idempotencyKey: key,
      text: text,
      attachment: attachment,
    );
  }

  @override
  Future<void> save({required String userId, required DailyNoteDraft draft}) =>
      _draftOperations.run(_storageKey(userId, draft.shopId), () async {
        if (!isCanonicalNoteId(draft.businessDayId) ||
            !isCanonicalNoteId(draft.idempotencyKey)) {
          throw const FormatException('note_draft');
        }
        _validateText(draft.text, draft.attachment);
        final envelope = <String, Object?>{
          'user_id': userId,
          'shop_id': draft.shopId,
          'business_day_id': draft.businessDayId,
          'idempotency_key': draft.idempotencyKey,
          'text': draft.text,
          'attachment': draft.attachment == null
              ? null
              : {
                  'client_object_id': draft.attachment!.clientObjectId,
                  'mime_type': draft.attachment!.mimeType,
                  'extension': draft.attachment!.extension,
                  'byte_size': draft.attachment!.byteSize,
                },
        };
        _rejectSecrets(envelope);
        _attachment(envelope['attachment']);
        if (!draft.hasContent || draft.shopId.isEmpty) {
          throw const FormatException('note_draft');
        }
        await storage.write(
          key: _storageKey(userId, draft.shopId),
          value: jsonEncode(envelope),
        );
      });

  @override
  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  }) => _draftOperations.run(_storageKey(userId, shopId), () async {
    final current = await _read(userId, shopId);
    if (current == null || current.idempotencyKey != idempotencyKey) return;
    await storage.delete(key: _storageKey(userId, shopId));
  });

  @override
  Future<void> cleanupConfirmed({
    required String userId,
    required DailyNoteDraft draft,
    required NoteImageFileStore files,
  }) => _draftOperations.run(_storageKey(userId, draft.shopId), () async {
    final current = await _read(userId, draft.shopId);
    final object = draft.attachment?.clientObjectId;
    if (object != null &&
        (current == null ||
            current.idempotencyKey == draft.idempotencyKey ||
            current.attachment?.clientObjectId != object)) {
      try {
        await files.delete(
          userId: userId,
          shopId: draft.shopId,
          clientObjectId: object,
        );
      } catch (_) {}
    }
    if (current?.idempotencyKey == draft.idempotencyKey) {
      await storage.delete(key: _storageKey(userId, draft.shopId));
    }
  });

  void _validateText(String text, NoteAttachmentRef? attachment) {
    if (text != text.trim() ||
        text.runes.length > noteTextMaxChars ||
        (text.isEmpty && attachment == null) ||
        text.runes.any(
          (rune) => rune < 0x20 && rune != 0x0A && rune != 0x09 && rune != 0x0D,
        )) {
      throw const FormatException('note_draft');
    }
  }

  NoteAttachmentRef? _attachment(Object? value) {
    if (value == null) return null;
    if (value is! Map) throw const FormatException('note_draft');
    const fields = {'client_object_id', 'mime_type', 'extension', 'byte_size'};
    if (value.length != fields.length ||
        value.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('note_draft');
    }
    final objectId = value['client_object_id'];
    final mime = value['mime_type'];
    final extension = value['extension'];
    final size = value['byte_size'];
    if (objectId is! String ||
        mime is! String ||
        extension is! String ||
        size is! String ||
        !isCanonicalNoteId(objectId) ||
        noteMimeExtensions[mime] != extension) {
      throw const FormatException('note_draft');
    }
    final parsedSize = int.tryParse(size);
    if (parsedSize == null ||
        parsedSize < 1 ||
        parsedSize > noteImageMaxBytes ||
        parsedSize.toString() != size) {
      throw const FormatException('note_draft');
    }
    return NoteAttachmentRef(
      clientObjectId: objectId,
      mimeType: mime,
      extension: extension,
      byteSize: size,
    );
  }
}

void _rejectSecrets(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll('_', '');
      if (key.contains('signedurl') ||
          key.contains('password') ||
          key.contains('session') ||
          key.contains('token') ||
          key.contains('secret') ||
          key.contains('apikey')) {
        throw const FormatException('note_draft_secret');
      }
      _rejectSecrets(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _rejectSecrets(item);
    }
  } else if (value is String) {
    final lower = value.toLowerCase();
    if (lower.contains('token=') || lower.contains('service_role')) {
      throw const FormatException('note_draft_secret');
    }
  }
}

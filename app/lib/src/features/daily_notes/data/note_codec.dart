import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/data/daily_ledger_codec.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/notes_gateway.dart';

NoteCommandResult parseNoteCommand(Object? json) {
  if (json is! Map) throw const FormatException('note');
  const fields = {
    'ok',
    'note_id',
    'operation_id',
    'business_day_id',
    'shop_sequence',
    'replayed',
  };
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('note');
  }
  final noteId = json['note_id'];
  final operationId = json['operation_id'];
  final dayId = json['business_day_id'];
  final sequence = json['shop_sequence'];
  final replayed = json['replayed'];
  if (json['ok'] != true ||
      noteId is! String ||
      operationId is! String ||
      dayId is! String ||
      sequence is! String ||
      replayed is! bool ||
      noteId != operationId ||
      !isUuid(noteId) ||
      !isUuid(dayId) ||
      PostgresInteger.parseCanonical(sequence) == null) {
    throw const FormatException('note');
  }
  return NoteCommitted(
    noteId: noteId,
    shopSequence: sequence,
    replayed: replayed,
  );
}

NoteStatusResult parseNoteStatus(Object? json) {
  if (json is! Map) throw const FormatException('note_status');
  if (json.length == 1 && json['status'] == 'absent') {
    return const NoteStatusAbsent();
  }
  const fields = {'status', 'note_id', 'operation_id'};
  final noteId = json['note_id'];
  final operationId = json['operation_id'];
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key)) ||
      json['status'] != 'completed' ||
      noteId is! String ||
      operationId is! String ||
      noteId != operationId ||
      !isUuid(noteId)) {
    throw const FormatException('note_status');
  }
  return NoteStatusCompleted(noteId);
}

DailyNotePage parseDailyNotePage(
  Object? json, {
  required String expectedShopId,
}) {
  if (json is! Map) throw const FormatException('notes');
  const fields = {
    'shop_id',
    'day_id',
    'limit',
    'has_more',
    'server_sequence',
    'snapshot_sequence',
    'next_before_sequence',
    'items',
  };
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('notes');
  }
  final shopId = json['shop_id'];
  final dayId = json['day_id'];
  final limit = json['limit'];
  final hasMore = json['has_more'];
  final server = json['server_sequence'];
  final snapshot = json['snapshot_sequence'];
  final before = json['next_before_sequence'];
  final items = json['items'];
  if (shopId is! String ||
      shopId != expectedShopId ||
      (dayId != null && (dayId is! String || !isUuid(dayId))) ||
      limit is! int ||
      limit < 1 ||
      limit > 50 ||
      hasMore is! bool ||
      server is! String ||
      snapshot is! String ||
      PostgresInteger.parseCanonical(server, allowZero: true) == null ||
      PostgresInteger.parseCanonical(snapshot, allowZero: true) == null ||
      (before != null &&
          (before is! String ||
              PostgresInteger.parseCanonical(before) == null)) ||
      (hasMore && before == null) ||
      (!hasMore && before != null) ||
      items is! List ||
      items.length > limit) {
    throw const FormatException('notes');
  }
  return DailyNotePage(
    shopId: shopId,
    dayId: dayId is String ? dayId : null,
    limit: limit,
    hasMore: hasMore,
    serverSequence: server,
    snapshotSequence: snapshot,
    nextBeforeSequence: before is String ? before : null,
    items: [
      for (final row in items) parseDailyNote(row, expectedShopId: shopId),
    ],
  );
}

DailyNoteView parseDailyNote(Object? json, {required String expectedShopId}) {
  if (json is! Map) throw const FormatException('note');
  const fields = {
    'note_id',
    'operation_id',
    'shop_sequence',
    'business_day_id',
    'text',
    'actor_display_name',
    'created_at',
    'occurred_at_shop',
    'attachment',
  };
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('note');
  }
  final noteId = json['note_id'];
  final operationId = json['operation_id'];
  final sequence = json['shop_sequence'];
  final dayId = json['business_day_id'];
  final text = json['text'];
  final actor = json['actor_display_name'];
  final createdAt = json['created_at'];
  final shopTime = json['occurred_at_shop'];
  if (noteId is! String ||
      operationId is! String ||
      sequence is! String ||
      dayId is! String ||
      text is! String ||
      actor is! String ||
      createdAt is! String ||
      shopTime is! String ||
      noteId != operationId ||
      !isUuid(noteId) ||
      !isUuid(dayId) ||
      PostgresInteger.parseCanonical(sequence) == null ||
      text.runes.length > 4000 ||
      actor.isEmpty ||
      actor.length > 200 ||
      !_utcNote(createdAt) ||
      !_wall(shopTime)) {
    throw const FormatException('note');
  }
  return DailyNoteView(
    noteId: noteId,
    shopSequence: sequence,
    businessDayId: dayId,
    text: text,
    actorDisplayName: actor,
    createdAt: createdAt,
    occurredAtShop: shopTime,
    attachment: _attachment(json['attachment'], expectedShopId, dayId),
  );
}

DailyNoteAttachmentView? _attachment(
  Object? value,
  String shopId,
  String dayId,
) {
  if (value == null) return null;
  if (value is! Map) throw const FormatException('attachment');
  const fields = {'bucket', 'object_name', 'mime_type', 'byte_size'};
  if (value.length != fields.length ||
      value.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('attachment');
  }
  final bucket = value['bucket'];
  final name = value['object_name'];
  final mime = value['mime_type'];
  final size = value['byte_size'];
  const extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };
  if (bucket != 'eldafttar-private-notes' ||
      name is! String ||
      mime is! String ||
      size is! String ||
      !extensions.containsKey(mime) ||
      PostgresInteger.parseCanonical(size) == null ||
      BigInt.parse(size) > BigInt.from(5242880)) {
    throw const FormatException('attachment');
  }
  final expectedPrefix = '$shopId/$dayId/';
  final extension = extensions[mime];
  if (!name.startsWith(expectedPrefix) || !name.endsWith('.$extension')) {
    throw const FormatException('attachment');
  }
  final objectId = name.substring(
    expectedPrefix.length,
    name.length - extension!.length - 1,
  );
  if (!isUuid(objectId) || name != '$expectedPrefix$objectId.$extension') {
    throw const FormatException('attachment');
  }
  return DailyNoteAttachmentView(
    bucket: bucket,
    objectName: name,
    mimeType: mime,
    byteSize: size,
  );
}

bool _utcNote(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]00:00)$',
  ).firstMatch(value);
  if (match == null) return false;
  return isCalendarDate(
    '${match.group(1)}-${match.group(2)}-${match.group(3)}',
  );
}

bool _wall(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(value);
  if (match == null) return false;
  return isCalendarDate(
    '${match.group(1)}-${match.group(2)}-${match.group(3)}',
  );
}

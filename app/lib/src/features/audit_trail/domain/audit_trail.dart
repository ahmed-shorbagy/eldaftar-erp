// Owner audit-trail read model. Independent of Flutter and Supabase.
// The server is the source of Arabic labels, actor names and shop-local time.

enum AuditTrailFamily { change, delete, deduction, post }

AuditTrailFamily? auditTrailFamilyFromApi(String? value) => switch (value) {
  'change' => AuditTrailFamily.change,
  'delete' => AuditTrailFamily.delete,
  'deduction' => AuditTrailFamily.deduction,
  'post' => AuditTrailFamily.post,
  _ => null,
};

String? auditTrailFamilyToApi(AuditTrailFamily? family) => switch (family) {
  AuditTrailFamily.change => 'change',
  AuditTrailFamily.delete => 'delete',
  AuditTrailFamily.deduction => 'deduction',
  AuditTrailFamily.post => 'post',
  null => null,
};

enum AuditTrailFailure { accessLost, staleCursor, unavailable }

class AuditTrailException implements Exception {
  const AuditTrailException(this.failure);

  final AuditTrailFailure failure;

  @override
  String toString() => 'AuditTrailException($failure)';
}

class AuditTrailEntry {
  const AuditTrailEntry({
    required this.id,
    required this.action,
    required this.actionLabel,
    required this.family,
    required this.actorUserId,
    required this.actorDisplayName,
    required this.createdAt,
    required this.createdAtShop,
    required this.operationId,
    required this.shopSequence,
    required this.businessDate,
    required this.summary,
  });

  final String id;
  final String action;
  final String actionLabel;
  final AuditTrailFamily family;
  final String actorUserId;

  /// Auth display name, or the shop owner name when the actor is the owner.
  /// Null when the server has no stored name. Never a fabricated person.
  final String? actorDisplayName;
  final DateTime createdAt;

  /// Shop-local wall clock `YYYY-MM-DD HH:MM:SS` from the server.
  final String createdAtShop;
  final String operationId;
  final String? shopSequence;
  final String? businessDate;
  final String summary;
}

class AuditTrailPage {
  const AuditTrailPage({
    required this.entries,
    required this.nextCursorAt,
    required this.nextCursorId,
    required this.timeZone,
    required this.snapshotAt,
  });

  final List<AuditTrailEntry> entries;
  final DateTime? nextCursorAt;
  final String? nextCursorId;
  final String timeZone;
  final DateTime snapshotAt;

  bool get hasMore => nextCursorAt != null && nextCursorId != null;
}

abstract class AuditTrailGateway {
  Future<AuditTrailPage> list({
    AuditTrailFamily? family,
    DateTime? beforeAt,
    String? beforeId,
    int limit = 20,
  });
}

AuditTrailPage decodeAuditTrailPage(Map<String, dynamic> raw) {
  final entriesRaw = raw['entries'];
  if (entriesRaw is! List) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  final nextAt = _timestamp(raw['next_cursor_at']);
  final nextId = _optionalString(raw['next_cursor_id']);
  if ((nextAt == null) != (nextId == null)) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  final timeZone = raw['time_zone'];
  final snapshotAt = _timestamp(raw['snapshot_at']);
  if (timeZone is! String || timeZone.isEmpty || snapshotAt == null) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  return AuditTrailPage(
    entries: [for (final entry in entriesRaw) _decodeEntry(entry)],
    nextCursorAt: nextAt,
    nextCursorId: nextId,
    timeZone: timeZone,
    snapshotAt: snapshotAt,
  );
}

AuditTrailEntry _decodeEntry(Object? raw) {
  if (raw is! Map) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  final map = Map<String, dynamic>.from(raw);
  final id = map['id'];
  final action = map['action'];
  final label = map['action_label'];
  final familyValue = map['action_family'];
  final actorId = map['actor_user_id'];
  final createdAt = _timestamp(map['created_at']);
  final createdAtShop = map['created_at_shop'];
  final operationId = map['operation_id'];
  final summary = map['summary'];
  final family = familyValue is String
      ? auditTrailFamilyFromApi(familyValue)
      : null;
  if (id is! String ||
      id.isEmpty ||
      action is! String ||
      action.isEmpty ||
      label is! String ||
      label.isEmpty ||
      family == null ||
      actorId is! String ||
      actorId.isEmpty ||
      createdAt == null ||
      createdAtShop is! String ||
      createdAtShop.isEmpty ||
      operationId is! String ||
      operationId.isEmpty ||
      summary is! String ||
      summary.isEmpty) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  final actorName = map['actor_display_name'];
  if (actorName != null && (actorName is! String || actorName.isEmpty)) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  return AuditTrailEntry(
    id: id,
    action: action,
    actionLabel: label,
    family: family,
    actorUserId: actorId,
    actorDisplayName: actorName as String?,
    createdAt: createdAt,
    createdAtShop: createdAtShop,
    operationId: operationId,
    shopSequence: _optionalSequence(map['shop_sequence']),
    businessDate: _optionalString(map['business_date']),
    summary: summary,
  );
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  return value;
}

String? _optionalSequence(Object? value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  if (value is int) return value.toString();
  throw const AuditTrailException(AuditTrailFailure.unavailable);
}

DateTime? _timestamp(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const AuditTrailException(AuditTrailFailure.unavailable);
  }
  return DateTime.tryParse(value)?.toUtc();
}

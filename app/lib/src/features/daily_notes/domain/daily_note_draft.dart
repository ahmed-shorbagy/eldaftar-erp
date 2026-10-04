/// Owner daily-note rules. No Flutter, Supabase, or storage imports.
library;

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const noteImageMaxBytes = 5242880;
const noteTextMaxChars = 4000;
const noteSearchMaxChars = 80;

const noteMimeExtensions = <String, String>{
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

final class NoteAttachmentRef {
  const NoteAttachmentRef({
    required this.clientObjectId,
    required this.mimeType,
    required this.extension,
    required this.byteSize,
  });

  final String clientObjectId;
  final String mimeType;
  final String extension;
  final String byteSize;

  String objectName({required String shopId, required String businessDayId}) =>
      '$shopId/$businessDayId/$clientObjectId.$extension';

  Map<String, String> toJson() => {
    'client_object_id': clientObjectId,
    'mime_type': mimeType,
    'byte_size': byteSize,
    'extension': extension,
  };
}

final class DailyNoteDraft {
  const DailyNoteDraft({
    required this.idempotencyKey,
    required this.shopId,
    required this.businessDayId,
    required this.text,
    this.attachment,
  });

  final String idempotencyKey;
  final String shopId;
  final String businessDayId;
  final String text;
  final NoteAttachmentRef? attachment;

  bool get hasContent => text.isNotEmpty || attachment != null;

  Map<String, Object?> canonicalPayload() => {
    'version': 1,
    'kind': 'daily_note',
    'business_day_id': businessDayId,
    'text': text,
    'attachment': attachment?.toJson(),
  };
}

final class NoteDraftDecision {
  const NoteDraftDecision._(this.draft, this.code);

  const NoteDraftDecision.accepted(DailyNoteDraft draft) : this._(draft, null);

  const NoteDraftDecision.rejected(String code) : this._(null, code);

  final DailyNoteDraft? draft;
  final String? code;
  bool get isAccepted => draft != null;
}

String? mimeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}

NoteDraftDecision composeDailyNote({
  required String idempotencyKey,
  required String shopId,
  required String businessDayId,
  required String text,
  String? clientObjectId,
  String? mimeType,
  String? fileName,
  List<int>? bytes,
}) {
  final key = idempotencyKey.toLowerCase();
  final shop = shopId.toLowerCase();
  final day = businessDayId.toLowerCase();
  final objectId = clientObjectId?.toLowerCase();
  if (!_uuid.hasMatch(key) || !_uuid.hasMatch(shop) || !_uuid.hasMatch(day)) {
    return const NoteDraftDecision.rejected('invalid_input');
  }
  final trimmed = text.trim();
  if (trimmed.runes.length > noteTextMaxChars) {
    return const NoteDraftDecision.rejected('overflow');
  }
  if (trimmed.runes.any(
    (rune) => rune < 0x20 && rune != 0x0A && rune != 0x09 && rune != 0x0D,
  )) {
    return const NoteDraftDecision.rejected('invalid_input');
  }
  NoteAttachmentRef? attachment;
  if (bytes != null) {
    final resolvedMime =
        mimeType ?? (fileName == null ? null : mimeFromFileName(fileName));
    final hinted = fileName == null ? null : mimeFromFileName(fileName);
    if (resolvedMime == null ||
        !noteMimeExtensions.containsKey(resolvedMime) ||
        (hinted != null && hinted != resolvedMime) ||
        objectId == null ||
        !_uuid.hasMatch(objectId)) {
      return const NoteDraftDecision.rejected('attachment_rejected');
    }
    if (bytes.isEmpty || bytes.length > noteImageMaxBytes) {
      return const NoteDraftDecision.rejected('attachment_rejected');
    }
    attachment = NoteAttachmentRef(
      clientObjectId: objectId,
      mimeType: resolvedMime,
      extension: noteMimeExtensions[resolvedMime]!,
      byteSize: bytes.length.toString(),
    );
  } else if (mimeType != null || fileName != null || clientObjectId != null) {
    return const NoteDraftDecision.rejected('attachment_rejected');
  }
  if (trimmed.isEmpty && attachment == null) {
    return const NoteDraftDecision.rejected('note_empty');
  }
  return NoteDraftDecision.accepted(
    DailyNoteDraft(
      idempotencyKey: key,
      shopId: shop,
      businessDayId: day,
      text: trimmed,
      attachment: attachment,
    ),
  );
}

bool isCanonicalNoteId(String value) => _uuid.hasMatch(value);

bool boundedNoteQuery(String query) =>
    query.trim().isNotEmpty && query.trim().runes.length <= noteSearchMaxChars;

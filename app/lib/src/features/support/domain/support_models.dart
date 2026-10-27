import 'dart:math';

import '../../auth/domain/owner_registration.dart';

/// Optional inquiry category. `null` means «أخرى/بدون تصنيف» on the wire is
/// the server null, not the `other` enum value.
enum SupportCategory { subscription, technical, financialQuestion, other }

SupportCategory? supportCategoryFromApi(String? value) => switch (value) {
  'subscription' => SupportCategory.subscription,
  'technical' => SupportCategory.technical,
  'financial_question' => SupportCategory.financialQuestion,
  'other' => SupportCategory.other,
  _ => null,
};

String? supportCategoryToApi(SupportCategory? value) => switch (value) {
  SupportCategory.subscription => 'subscription',
  SupportCategory.technical => 'technical',
  SupportCategory.financialQuestion => 'financial_question',
  SupportCategory.other => 'other',
  null => null,
};

/// `new` is reserved in Dart; the API value stays the server's `new`.
enum SupportInquiryStatus { fresh, inProgress, answered, closed }

SupportInquiryStatus? supportStatusFromApi(String value) => switch (value) {
  'new' => SupportInquiryStatus.fresh,
  'in_progress' => SupportInquiryStatus.inProgress,
  'answered' => SupportInquiryStatus.answered,
  'closed' => SupportInquiryStatus.closed,
  _ => null,
};

class SupportInquiry {
  const SupportInquiry({
    required this.id,
    required this.category,
    required this.bodyAr,
    required this.status,
    required this.replyAr,
    required this.createdAt,
    required this.updatedAt,
    required this.answeredAt,
    required this.closedAt,
  });

  final String id;
  final SupportCategory? category;
  final String bodyAr;
  final SupportInquiryStatus status;
  final String? replyAr;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? answeredAt;
  final DateTime? closedAt;
}

class SupportInquiryPage {
  const SupportInquiryPage({
    required this.inquiries,
    required this.nextCursorAt,
    required this.nextCursorId,
    required this.openCount,
    required this.openLimit,
    required this.timeZone,
    required this.snapshotAt,
  });

  final List<SupportInquiry> inquiries;

  /// Keyset position of the last returned row; null when there is no more.
  final DateTime? nextCursorAt;
  final String? nextCursorId;
  final int openCount;
  final int openLimit;
  final String timeZone;
  final DateTime snapshotAt;
}

class SupportSaveResult {
  const SupportSaveResult({required this.inquiry, required this.replayed});

  final SupportInquiry inquiry;

  /// True when the server had already saved this idempotency key.
  final bool replayed;
}

enum SupportFailure {
  unauthorized,
  invalidInput,
  inquiryLimit,
  payloadMismatch,
  notFound,
  staleCursor,
  unavailable,
}

class SupportException implements Exception {
  const SupportException(this.failure);
  final SupportFailure failure;
}

abstract class SupportGateway {
  Future<SupportSaveResult> createInquiry({
    required String key,
    required SupportCategory? category,
    required String bodyAr,
  });

  Future<SupportInquiryPage> listInquiries({
    DateTime? cursorAt,
    String? cursorId,
    int pageSize = 20,
  });
}

/// Mirrors the server rule exactly (ADR 0036): CR/Tab and every other
/// control character are rejected before trimming, newline is the only
/// accepted control character, trimming removes ASCII spaces, and the
/// trimmed length is 10–1000 Unicode characters. Returns the normalized
/// body, or null when the draft is invalid.
String? normalizeSupportBody(String draft) {
  for (final rune in draft.runes) {
    final isControl =
        (rune < 0x20 && rune != 0x0A) ||
        rune == 0x7F ||
        (rune >= 0x80 && rune <= 0x9F);
    if (isControl) return null;
  }
  final trimmed = _trimSpaces(draft);
  final length = trimmed.runes.length;
  if (length < 10 || length > 1000) return null;
  return trimmed;
}

/// The server btrims ASCII spaces only; trimming more here would diverge.
String _trimSpaces(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && value.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && value.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return value.substring(start, end);
}

/// True while the draft differs from what a stored key was created with, so
/// the pending idempotency key must be dropped before the next submit.
bool supportDraftChanged({
  required String storedDraftBody,
  required SupportCategory? storedDraftCategory,
  required String draftBody,
  required SupportCategory? draftCategory,
}) => storedDraftBody != draftBody || storedDraftCategory != draftCategory;

/// Fresh v4 key for the first submit of a draft.
String newSupportIdempotencyKey() => IdempotencyKey.generate(Random.secure());

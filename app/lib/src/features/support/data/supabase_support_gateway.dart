import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/support_models.dart';

class SupabaseSupportGateway implements SupportGateway {
  const SupabaseSupportGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<SupportSaveResult> createInquiry({
    required String key,
    required SupportCategory? category,
    required String bodyAr,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'create_support_inquiry_v1',
            params: {
              'p_idempotency_key': key,
              'p_category': supportCategoryToApi(category),
              'p_body_ar': bodyAr,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (raw is! Map) {
        throw const SupportException(SupportFailure.unavailable);
      }
      return SupportSaveResult(
        inquiry: _parseInquiry(Map<String, dynamic>.from(raw)),
        replayed: raw['result_status'] == 'replayed',
      );
    } on SupportException {
      rethrow;
    } on PostgrestException catch (error) {
      throw SupportException(_map(error));
    } catch (_) {
      throw const SupportException(SupportFailure.unavailable);
    }
  }

  @override
  Future<SupportInquiryPage> listInquiries({
    DateTime? cursorAt,
    String? cursorId,
    int pageSize = 20,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'list_my_support_inquiries_v1',
            params: {
              'p_cursor_at': cursorAt?.toIso8601String(),
              'p_cursor_id': cursorId,
              'p_page_size': pageSize,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (raw is! Map) {
        throw const SupportException(SupportFailure.unavailable);
      }
      return _parsePage(Map<String, dynamic>.from(raw));
    } on SupportException {
      rethrow;
    } on PostgrestException catch (error) {
      throw SupportException(_map(error));
    } catch (_) {
      throw const SupportException(SupportFailure.unavailable);
    }
  }

  static SupportInquiryPage _parsePage(Map<String, dynamic> raw) {
    final inquiriesRaw = raw['inquiries'];
    if (inquiriesRaw is! List) {
      throw const SupportException(SupportFailure.unavailable);
    }
    final nextCursorAt = _timestamp(raw['next_cursor_at']);
    final nextCursorId = raw['next_cursor_id'] as String?;
    if ((nextCursorAt == null) != (nextCursorId == null)) {
      throw const SupportException(SupportFailure.unavailable);
    }
    final openCount = raw['open_count'];
    final openLimit = raw['open_limit'];
    final timeZone = raw['time_zone'];
    final snapshotAt = _timestamp(raw['snapshot_at']);
    if (openCount is! int ||
        openLimit is! int ||
        timeZone is! String ||
        timeZone.isEmpty ||
        snapshotAt == null) {
      throw const SupportException(SupportFailure.unavailable);
    }
    return SupportInquiryPage(
      inquiries: inquiriesRaw.map(_parseListEntry).toList(growable: false),
      nextCursorAt: nextCursorAt,
      nextCursorId: nextCursorId,
      openCount: openCount,
      openLimit: openLimit,
      timeZone: timeZone,
      snapshotAt: snapshotAt,
    );
  }

  static SupportInquiry _parseListEntry(Object? entry) {
    if (entry is! Map) {
      throw const SupportException(SupportFailure.unavailable);
    }
    return _parseInquiry(Map<String, dynamic>.from(entry));
  }

  static SupportInquiry _parseInquiry(Map<String, dynamic> raw) {
    final id = raw['id'];
    final body = raw['body_ar'];
    final statusValue = raw['status'];
    final createdAt = _timestamp(raw['created_at']);
    final updatedAt = _timestamp(raw['updated_at']);
    if (id is! String ||
        id.isEmpty ||
        body is! String ||
        statusValue is! String ||
        createdAt == null ||
        updatedAt == null) {
      throw const SupportException(SupportFailure.unavailable);
    }
    final status = supportStatusFromApi(statusValue);
    if (status == null) {
      throw const SupportException(SupportFailure.unavailable);
    }
    final categoryValue = raw['category'];
    if (categoryValue != null && categoryValue is! String) {
      throw const SupportException(SupportFailure.unavailable);
    }
    final replyValue = raw['reply_ar'];
    if (replyValue != null && replyValue is! String) {
      throw const SupportException(SupportFailure.unavailable);
    }
    return SupportInquiry(
      id: id,
      category: supportCategoryFromApi(categoryValue as String?),
      bodyAr: body,
      status: status,
      replyAr: replyValue as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      answeredAt: _timestamp(raw['answered_at']),
      closedAt: _timestamp(raw['closed_at']),
    );
  }

  static DateTime? _timestamp(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const SupportException(SupportFailure.unavailable);
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static SupportFailure _map(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (message.contains('stale_cursor')) {
      return SupportFailure.staleCursor;
    }
    if (message.contains('invalid_input')) {
      return SupportFailure.invalidInput;
    }
    if (message.contains('inquiry_limit')) {
      return SupportFailure.inquiryLimit;
    }
    if (message.contains('payload_mismatch')) {
      return SupportFailure.payloadMismatch;
    }
    if (message.contains('not_found')) {
      return SupportFailure.notFound;
    }
    if (error.code == '42501' ||
        message.contains('unauthorized') ||
        message.contains('unauthenticated') ||
        message.contains('session_expired') ||
        message.contains('forbidden')) {
      return SupportFailure.unauthorized;
    }
    return SupportFailure.unavailable;
  }
}

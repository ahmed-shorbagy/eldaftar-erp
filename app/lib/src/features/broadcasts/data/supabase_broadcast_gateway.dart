import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/broadcast_models.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class SupabaseBroadcastGateway implements BroadcastGateway {
  const SupabaseBroadcastGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<BroadcastInbox> listMine() async {
    try {
      final raw = await _client
          .rpc('list_my_broadcasts_v1')
          .timeout(const Duration(seconds: 15));
      return parseBroadcastInbox(raw);
    } on BroadcastException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BroadcastException(mapBroadcastError(error.message));
    } catch (_) {
      throw const BroadcastException(BroadcastFailure.unavailable);
    }
  }

  @override
  Future<BroadcastReadResult> markRead(String broadcastId) async {
    try {
      final raw = await _client
          .rpc(
            'mark_broadcast_read_v1',
            params: {'p_broadcast_id': broadcastId},
          )
          .timeout(const Duration(seconds: 15));
      return parseReadResult(raw, broadcastId);
    } on BroadcastException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BroadcastException(mapBroadcastError(error.message));
    } catch (_) {
      throw const BroadcastException(BroadcastFailure.unavailable);
    }
  }
}

BroadcastFailure mapBroadcastError(String message) {
  final text = message.toLowerCase();
  if (text.contains('unauthorized') ||
      text.contains('permission denied') ||
      text.contains('42501')) {
    return BroadcastFailure.unauthorized;
  }
  if (text.contains('not_found')) return BroadcastFailure.notFound;
  return BroadcastFailure.unavailable;
}

Never _invalid() =>
    throw const BroadcastException(BroadcastFailure.unavailable);

String _text(Object? value) {
  if (value is! String || value.trim().isEmpty) _invalid();
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String) _invalid();
  final parsed = DateTime.tryParse(value);
  if (parsed == null) _invalid();
  return parsed.toUtc();
}

BroadcastInbox parseBroadcastInbox(Object? raw) {
  if (raw is! Map) _invalid();
  final map = Map<String, dynamic>.from(raw);
  final shopId = map['shop_id'];
  final unread = map['unread_count'];
  final rows = map['rows'];
  final zone = map['time_zone'];
  if (shopId is! String ||
      !_uuid.hasMatch(shopId) ||
      unread is! String ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(unread) ||
      rows is! List) {
    _invalid();
  }
  final items = rows.map(_parseItem).toList(growable: false);
  final ids = items.map((item) => item.id).toSet();
  if (ids.length != items.length) _invalid();
  final unreadCount = int.parse(unread);
  if (unreadCount < items.where((item) => item.isUnread).length) _invalid();
  return BroadcastInbox(
    shopId: shopId.toLowerCase(),
    timeZone: zone is String && zone.trim().isNotEmpty ? zone : 'Africa/Cairo',
    unreadCount: unreadCount,
    items: items,
  );
}

OwnerBroadcast _parseItem(Object? raw) {
  if (raw is! Map) _invalid();
  final map = Map<String, dynamic>.from(raw);
  final id = map['id'];
  if (id is! String || !_uuid.hasMatch(id)) _invalid();
  final link = map['link_url'];
  if (link != null && (link is! String || !link.startsWith('https://'))) {
    _invalid();
  }
  final readAt = map['read_at'];
  final startsAt = _instant(map['starts_at']);
  final endsAt = _instant(map['ends_at']);
  if (!endsAt.isAfter(startsAt)) _invalid();
  return OwnerBroadcast(
    id: id.toLowerCase(),
    titleAr: _text(map['title_ar']),
    bodyAr: _text(map['body_ar']),
    linkUrl: link as String?,
    startsAt: startsAt,
    endsAt: endsAt,
    readAt: readAt == null ? null : _instant(readAt),
  );
}

BroadcastReadResult parseReadResult(Object? raw, String expectedId) {
  if (raw is! Map) _invalid();
  final map = Map<String, dynamic>.from(raw);
  final status = map['status'];
  final id = map['broadcast_id'];
  if ((status != 'read' && status != 'already_read') ||
      id is! String ||
      id.toLowerCase() != expectedId.toLowerCase()) {
    _invalid();
  }
  return BroadcastReadResult(
    readAt: _instant(map['read_at']),
    alreadyRead: status == 'already_read',
  );
}

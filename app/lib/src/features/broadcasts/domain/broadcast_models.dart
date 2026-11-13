/// Owner inbox of platform-admin messages (ADR 0048, ADM-06).
library;

class OwnerBroadcast {
  const OwnerBroadcast({
    required this.id,
    required this.titleAr,
    required this.bodyAr,
    required this.startsAt,
    required this.endsAt,
    this.linkUrl,
    this.readAt,
  });

  final String id;
  final String titleAr;
  final String bodyAr;
  final String? linkUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  OwnerBroadcast markedRead(DateTime at) => OwnerBroadcast(
    id: id,
    titleAr: titleAr,
    bodyAr: bodyAr,
    linkUrl: linkUrl,
    startsAt: startsAt,
    endsAt: endsAt,
    readAt: readAt ?? at,
  );
}

class BroadcastInbox {
  const BroadcastInbox({
    required this.shopId,
    required this.timeZone,
    required this.unreadCount,
    required this.items,
  });

  final String shopId;
  final String timeZone;

  /// Unread among every visible message, which may exceed [items].
  final int unreadCount;
  final List<OwnerBroadcast> items;

  /// The newest unread message, shown as the workspace banner.
  OwnerBroadcast? get newestUnread {
    for (final item in items) {
      if (item.isUnread) return item;
    }
    return null;
  }

  BroadcastInbox withRead(String id, DateTime at) {
    var changed = false;
    final next = [
      for (final item in items)
        if (item.id == id && item.isUnread)
          () {
            changed = true;
            return item.markedRead(at);
          }()
        else
          item,
    ];
    if (!changed) return this;
    return BroadcastInbox(
      shopId: shopId,
      timeZone: timeZone,
      unreadCount: unreadCount > 0 ? unreadCount - 1 : 0,
      items: next,
    );
  }
}

class BroadcastReadResult {
  const BroadcastReadResult({required this.readAt, required this.alreadyRead});

  final DateTime readAt;
  final bool alreadyRead;
}

abstract class BroadcastGateway {
  Future<BroadcastInbox> listMine();
  Future<BroadcastReadResult> markRead(String broadcastId);
}

enum BroadcastFailure { unauthorized, notFound, unavailable }

class BroadcastException implements Exception {
  const BroadcastException(this.failure);
  final BroadcastFailure failure;

  @override
  String toString() => 'BroadcastException($failure)';
}

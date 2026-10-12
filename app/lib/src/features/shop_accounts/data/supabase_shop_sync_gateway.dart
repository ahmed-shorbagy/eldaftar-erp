import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shop_sync.dart';

class _Watch {
  _Watch({
    required this.shopId,
    required this.userId,
    required this.channel,
    required this.controller,
  });

  final String shopId;
  final String userId;
  final RealtimeChannel channel;
  final StreamController<ShopSyncSnapshot> controller;
}

class SupabaseShopSyncGateway implements ShopSyncGateway {
  SupabaseShopSyncGateway(this._client);

  final SupabaseClient _client;
  final _watches = <int, _Watch>{};
  var _nextWatch = 0;

  @override
  Stream<ShopSyncSnapshot> watch({
    required String shopId,
    required String userId,
  }) {
    final id = _nextWatch++;
    final controller = StreamController<ShopSyncSnapshot>.broadcast();
    final channel = _client.channel('shop-sync-$shopId-$userId-$id');
    final watch = _Watch(
      shopId: shopId,
      userId: userId,
      channel: channel,
      controller: controller,
    );
    _watches[id] = watch;
    controller.onCancel = () {
      unawaited(_closeWatch(id));
    };
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'shop_sync_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'shop_id',
        value: shopId,
      ),
      callback: (payload) {
        final current = _watches[id];
        if (current == null ||
            current.shopId != shopId ||
            current.userId != userId ||
            _client.auth.currentUser?.id != userId) {
          return;
        }
        final record = payload.newRecord.isEmpty
            ? payload.oldRecord
            : payload.newRecord;
        final snapshot = _parse(record);
        if (snapshot != null && snapshot.shopId == shopId) {
          controller.add(snapshot);
        }
      },
    );
    channel.subscribe((status, error) {
      final current = _watches[id];
      if (current == null ||
          current.shopId != shopId ||
          current.userId != userId ||
          _client.auth.currentUser?.id != userId) {
        return;
      }
      if (status == RealtimeSubscribeStatus.subscribed ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        unawaited(_emitRead(shopId, controller, id));
      }
    });
    return controller.stream;
  }

  @override
  Future<ShopSyncSnapshot?> read({required String shopId}) async {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) return null;
    final userId = session.user.id;
    final token = session.accessToken;
    try {
      final response = await _client
          .from('shop_sync_signals')
          .select()
          .eq('shop_id', shopId)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      final current = _client.auth.currentSession;
      if (current == null ||
          current.isExpired ||
          current.user.id != userId ||
          current.accessToken != token ||
          response == null) {
        return null;
      }
      return _parse(response);
    } catch (_) {
      return null;
    }
  }

  Future<void> _emitRead(
    String shopId,
    StreamController<ShopSyncSnapshot> controller,
    int id,
  ) async {
    final snapshot = await read(shopId: shopId);
    final current = _watches[id];
    if (current == null ||
        controller.isClosed ||
        snapshot == null ||
        current.shopId != shopId ||
        _client.auth.currentUser?.id != current.userId) {
      return;
    }
    controller.add(snapshot.asCatchUp());
  }

  ShopSyncSnapshot? _parse(Map<String, dynamic> row) {
    final shopId = row['shop_id'];
    final revision = _int(row['revision']);
    if (shopId is! String || shopId.isEmpty || revision == null) return null;
    return ShopSyncSnapshot(
      shopId: shopId,
      revision: revision,
      ledgerRevision: _int(row['ledger_revision']) ?? 0,
      inventoryRevision: _int(row['inventory_revision']) ?? 0,
      traderRevision: _int(row['trader_revision']) ?? 0,
      invoiceRevision: _int(row['invoice_revision']) ?? 0,
      dayRevision: _int(row['day_revision']) ?? 0,
      locationRevision: _int(row['location_revision']) ?? 0,
      subscriptionRevision: _int(row['subscription_revision']) ?? 0,
      repairRevision: _int(row['repair_revision']) ?? 0,
    );
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Future<void> _closeWatch(int id) async {
    final watch = _watches.remove(id);
    if (watch == null) return;
    await _client.removeChannel(watch.channel);
    if (!watch.controller.isClosed) {
      await watch.controller.close();
    }
  }

  @override
  Future<void> close() async {
    final ids = _watches.keys.toList();
    for (final id in ids) {
      await _closeWatch(id);
    }
  }
}

import 'dart:async';

import '../domain/shop_sync.dart';

/// Coalesces shop invalidation, drops stale responses, and serializes refresh.
class ShopSyncCoordinator {
  ShopSyncCoordinator({
    required this.gateway,
    required this.shopId,
    required this.userId,
    required this.onInvalidate,
    this.pollInterval = const Duration(seconds: 45),
    this.coalesceWindow = const Duration(milliseconds: 120),
  });

  final ShopSyncGateway gateway;
  final String shopId;
  final String userId;
  final Future<void> Function(Set<ShopSyncScope> scopes) onInvalidate;
  final Duration pollInterval;
  final Duration coalesceWindow;

  StreamSubscription<ShopSyncSnapshot>? _subscription;
  Timer? _poll;
  Timer? _coalesce;
  Timer? _retry;
  ShopSyncSnapshot? _latest;
  var _generation = 0;
  var _refreshing = false;
  var _pending = false;
  var _closed = false;
  final Set<ShopSyncScope> _queued = {};

  Future<void> start() async {
    if (_closed) return;
    _subscription = gateway
        .watch(shopId: shopId, userId: userId)
        .listen(_onEvent, onError: (_) => _scheduleCatchUp());
    _poll = Timer.periodic(pollInterval, (_) => _scheduleCatchUp());
    await _catchUp();
  }

  void resume() {
    if (_closed) return;
    _scheduleCatchUp();
  }

  void _onEvent(ShopSyncSnapshot snapshot) {
    if (_closed || snapshot.shopId != shopId) return;
    if (snapshot.forceRefresh) {
      if (_latest == null || snapshot.revision >= _latest!.revision) {
        _latest = snapshot;
      }
      _queued.addAll(ShopSyncScope.values);
    } else {
      if (_latest != null && snapshot.revision < _latest!.revision) return;
      final scopes = snapshot.changedFrom(_latest);
      _latest = snapshot;
      if (scopes.isEmpty) return;
      _queued.addAll(scopes);
    }
    _coalesce?.cancel();
    _coalesce = Timer(coalesceWindow, () => unawaited(_flush()));
  }

  void _scheduleCatchUp() {
    _queued.addAll(ShopSyncScope.values);
    _coalesce?.cancel();
    _coalesce = Timer(coalesceWindow, () => unawaited(_flush()));
  }

  Future<void> _catchUp() async {
    if (_closed) return;
    try {
      final snapshot = await gateway.read(shopId: shopId);
      if (_closed) return;
      if (snapshot != null && snapshot.shopId == shopId) {
        _onEvent(snapshot);
      } else {
        _queued.addAll(ShopSyncScope.values);
        await _flush();
      }
    } catch (_) {
      _queued.addAll(ShopSyncScope.values);
      await _flush();
    }
  }

  Future<void> _flush() async {
    if (_closed || _queued.isEmpty) return;
    if (_refreshing) {
      _pending = true;
      return;
    }
    final scopes = Set<ShopSyncScope>.from(_queued);
    _queued.clear();
    final generation = ++_generation;
    _refreshing = true;
    var failed = false;
    try {
      await onInvalidate(scopes);
      _retry?.cancel();
    } catch (_) {
      failed = true;
      _queued.addAll(scopes);
      _retry?.cancel();
      if (!_closed) {
        _retry = Timer(const Duration(seconds: 2), () => unawaited(_flush()));
      }
    } finally {
      if (generation == _generation) {
        _refreshing = false;
        if (failed) {
          _pending = false;
        } else if (_pending && !_closed) {
          _pending = false;
          await _flush();
        }
      }
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _generation++;
    _coalesce?.cancel();
    _poll?.cancel();
    _retry?.cancel();
    await _subscription?.cancel();
  }
}

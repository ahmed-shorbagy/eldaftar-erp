import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../domain/debt_rules.dart';
import 'debt_gateway.dart';
import 'debt_native_gateway.dart';
import 'debt_reminder_device.dart';

/// Serializes durable desired/applied reconciliation independently of metadata writes.
final class DebtReminderCoordinator {
  DebtReminderCoordinator({
    required this.gateway,
    required this.store,
    required this.port,
    required this.clock,
  });
  final DebtNativeGateway gateway;
  final DeviceReminderStore store;
  final DebtNotificationPort port;
  final ReminderClock clock;
  final _changes = StreamController<ReminderDeviceReport>.broadcast(sync: true);
  Stream<ReminderDeviceReport> get changes => _changes.stream;
  ReminderDeviceReport report = const ReminderDeviceReport(
    DeviceReminderState.disabled,
  );
  DeviceReminderManifest? manifest;
  Future<void> _tail = Future.value();
  String? _user, _shop;
  Object? _session;
  int _epoch = 0;
  bool _initialized = false;
  bool get enabled => manifest?.enabled ?? false;
  void _publish(ReminderDeviceReport value) {
    report = value;
    _changes.add(value);
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  bool _current(int epoch, String user, String shop, Object? session) =>
      _epoch == epoch &&
      _user == user &&
      _shop == shop &&
      session != null &&
      gateway.nativeSession(user) == session;

  Future<void> bind(String? user, String? shop) {
    final session = user == null ? null : gateway.nativeSession(user);
    if (user == _user && shop == _shop && session == _session && _initialized) {
      return reconcile();
    }
    _user = user;
    _shop = shop;
    _session = session;
    _epoch++;
    return _serial(() async {
      try {
        if (!_initialized) {
          manifest = await store.load();
          try {
            await port.initialize((token) {
              unawaited(_tap(token));
            });
          } catch (_) {
            _publish(
              const ReminderDeviceReport(DeviceReminderState.unsupported),
            );
            return;
          }
          _initialized = true;
        }
        var m = manifest!;
        if (m.userId != _user ||
            m.shopId != _shop ||
            _user == null ||
            _shop == null) {
          m = m.copy(enabled: false);
          await _save(m);
          await _cancelAll();
          await _save(
            DeviceReminderManifest(
              installation: m.installation,
              userId: _user,
              shopId: _shop,
            ),
          );
        }
      } catch (_) {
        _publish(
          const ReminderDeviceReport(
            DeviceReminderState.failed,
            error: 'device_storage',
          ),
        );
      }
    }).then((_) => reconcile());
  }

  Future<void> _save(DeviceReminderManifest m) async {
    await store.save(m);
    manifest = m;
  }

  Future<void> _tap(String token) => _serial(() async {
    final m = manifest;
    if (m != null &&
        m.userId == _user &&
        m.shopId == _shop &&
        [...m.requests, ...m.routes].any((r) => r.token == token)) {
      await _save(m.copy(tapToken: token));
      _publish(report);
    }
  });
  Future<void> dismissTap() => _serial(() async {
    if (manifest != null) await _save(manifest!.copy(clearTap: true));
  });
  Future<DebtNativeDetail?> readTap() async {
    final m = manifest,
        user = _user,
        shop = _shop,
        session = _session,
        epoch = _epoch;
    if (m == null ||
        user == null ||
        shop == null ||
        m.userId != user ||
        m.shopId != shop ||
        m.tapToken == null) {
      return null;
    }
    final found = {
      for (final r in [...m.routes, ...m.requests]) r.token: r,
    }.values.where((r) => r.token == m.tapToken);
    if (found.length != 1 || !_current(epoch, user, shop, session)) return null;
    final r = found.single;
    final d = await gateway.readNative(
      userId: user,
      shopId: shop,
      sourceKind: DebtSourceKind.byWire(r.sourceKind)!,
      sourceId: r.sourceId,
    );
    return _current(epoch, user, shop, session) &&
            d.row.due.shopId == shop &&
            d.row.due.summary.sourceId == r.sourceId &&
            d.row.due.summary.sourceKind.wire == r.sourceKind
        ? d
        : null;
  }

  Future<void> enable() => _serial(() async {
    final user = _user, shop = _shop, session = _session, epoch = _epoch;
    if (!_initialized ||
        user == null ||
        shop == null ||
        !_current(epoch, user, shop, session) ||
        manifest == null) {
      return;
    }
    _publish(const ReminderDeviceReport(DeviceReminderState.preparing));
    try {
      // The only permission-request call site follows an explicit enable action.
      final permission = await port.requestPermission();
      if (!_current(epoch, user, shop, session)) return;
      await _save(manifest!.copy(enabled: true));
      if (permission != ReminderPermission.allowed) {
        await _cancelAll();
        _publish(
          ReminderDeviceReport(
            permission == ReminderPermission.unsupported
                ? DeviceReminderState.unsupported
                : DeviceReminderState.permissionDenied,
          ),
        );
      }
    } catch (_) {
      _publish(const ReminderDeviceReport(DeviceReminderState.failed));
    }
  }).then((_) => reconcile());
  Future<void> disable() => _serial(() async {
    try {
      if (manifest == null) return;
      await _save(manifest!.copy(enabled: false));
      await _cancelAll();
      _publish(const ReminderDeviceReport(DeviceReminderState.disabled));
    } catch (_) {
      _publish(
        const ReminderDeviceReport(
          DeviceReminderState.failed,
          error: 'cancel_pending',
        ),
      );
    }
  });
  Future<void> _cancelAll() async {
    var m = manifest!;
    for (final r in List<DeviceReminderRequest>.of(m.requests)) {
      await port.cancel(r.id);
      if ((await port.pendingIds()).contains(r.id)) {
        throw StateError('cancel_pending');
      }
      m = m.copy(requests: m.requests.where((x) => x.id != r.id).toList());
      await _save(m);
    }
  }

  Future<ReminderSnapshot> _snapshot(
    String user,
    String shop,
    int epoch,
    Object? session,
  ) async {
    final rows = <DebtScheduledIntent>[],
        seen = <String>{},
        cursors = <String>{};
    String? cursor, hash;
    int? total;
    DateTime? at;
    do {
      final p = await gateway.readNativeQueue(
        userId: user,
        shopId: shop,
        cursor: cursor,
      );
      if (!_current(epoch, user, shop, session)) {
        throw const DebtReadException('discarded');
      }
      hash ??= p.freshness;
      total ??= p.total;
      at ??= p.at;
      if (p.shopId != shop ||
          p.freshness != hash ||
          p.offset != rows.length ||
          p.total != total ||
          p.items.any((r) => !seen.add(r.key))) {
        throw const DebtReadException('stale_native_cursor');
      }
      rows.addAll(p.items);
      cursor = p.cursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw const DebtReadException('stale_native_cursor');
      }
    } while (cursor != null);
    if (rows.length != total) {
      throw const DebtReadException('stale_native_cursor');
    }
    // Recheck the complete content identity after pagination before changing OS state.
    final check = await gateway.readNativeQueue(
      userId: user,
      shopId: shop,
      cursor: null,
    );
    if (!_current(epoch, user, shop, session) ||
        check.freshness != hash ||
        check.total != total) {
      throw const DebtReadException('stale_native_cursor');
    }
    return (rows: rows, at: check.at, receivedAt: clock.elapsed);
  }

  Future<void> reconcile() => _serial(() async {
    final user = _user, shop = _shop, session = _session, epoch = _epoch;
    if (!_initialized || manifest == null) return;
    if (!enabled) {
      try {
        await _cancelAll();
        _publish(
          ReminderDeviceReport(
            await port.permission() == ReminderPermission.unsupported
                ? DeviceReminderState.unsupported
                : DeviceReminderState.disabled,
          ),
        );
      } catch (_) {
        _publish(
          const ReminderDeviceReport(
            DeviceReminderState.failed,
            error: 'cancel_pending',
          ),
        );
      }
      return;
    }
    if (user == null || shop == null || !_current(epoch, user, shop, session)) {
      try {
        await _cancelAll();
        _publish(const ReminderDeviceReport(DeviceReminderState.stale));
      } catch (_) {
        _publish(
          const ReminderDeviceReport(
            DeviceReminderState.failed,
            error: 'cancel_pending',
          ),
        );
      }
      return;
    }
    _publish(const ReminderDeviceReport(DeviceReminderState.preparing));
    final started = clock.elapsed;
    try {
      final permission = await port.permission();
      if (!_current(epoch, user, shop, session)) return;
      if (permission != ReminderPermission.allowed) {
        await _cancelAll();
        _publish(
          ReminderDeviceReport(
            permission == ReminderPermission.unsupported
                ? DeviceReminderState.unsupported
                : DeviceReminderState.permissionDenied,
          ),
        );
        return;
      }
      final snapshot = await _snapshot(user, shop, epoch, session);
      final elapsed = clock.elapsed - started;
      if (elapsed > const Duration(minutes: 2)) {
        throw const DebtReadException('stale_native_cursor');
      }
      if (clock.nowUtc().difference(snapshot.at).abs() >
          const Duration(minutes: 5)) {
        await _cancelAll();
        _publish(
          ReminderDeviceReport(
            DeviceReminderState.clockMismatch,
            at: snapshot.at,
          ),
        );
        return;
      }
      final now = snapshot.at;
      final states = <String, DeviceReminderState>{},
          desired = <DeviceReminderRequest>[];
      final sorted = List<DebtScheduledIntent>.of(snapshot.rows)
        ..sort((a, b) {
          final order = (a.triggerAt ?? DateTime.utc(9999)).compareTo(
            b.triggerAt ?? DateTime.utc(9999),
          );
          return order != 0 ? order : a.key.compareTo(b.key);
        });
      final old = manifest!;
      for (final row in sorted) {
        final key = row.key, at = row.triggerAt;
        if (!row.timeValid || at == null) {
          states[key] = DeviceReminderState.invalidTime;
          continue;
        }
        if (!at.isAfter(now)) {
          states[key] = DeviceReminderState.missed;
          continue;
        }
        if (at.isAfter(now.add(const Duration(days: 30)))) {
          states[key] = DeviceReminderState.outsideHorizon;
          continue;
        }
        if (desired.length >= 32) {
          states[key] = DeviceReminderState.capacity;
          continue;
        }
        final digest = await Sha256().hash(
          utf8.encode('${old.installation}:$shop:$key'),
        );
        final bytes = digest.bytes;
        final id =
            0x40000000 |
            ((bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) &
                0x3fffffff);
        if (desired.any((r) => r.id == id)) {
          states[key] = DeviceReminderState.failed;
          continue;
        }
        final existing = old.requests.where(
          (r) =>
              r.id == id &&
              r.sourceId == row.sourceId &&
              r.sourceKind == row.sourceKind.wire,
        );
        desired.add(
          DeviceReminderRequest(
            id: id,
            token: existing.isEmpty
                ? newIdempotencyKey()
                : existing.single.token,
            sourceKind: row.sourceKind.wire,
            sourceId: row.sourceId,
            fingerprint: row.freshness,
            at: at,
          ),
        );
        states[key] = DeviceReminderState.pending;
      }
      // Persist new desired state together with obsolete applied requests before OS work.
      final obsolete = old.requests
          .where((r) => !desired.any((d) => d.id == r.id))
          .toList();
      final entries = [
        ...desired.map((d) {
          final matches = old.requests.where(
            (r) => r.id == d.id && r.fingerprint == d.fingerprint && r.applied,
          );
          return d.marked(matches.isNotEmpty);
        }),
        ...obsolete,
      ];
      if (!_current(epoch, user, shop, session)) return;
      final routes = {
        for (final r in [...old.routes, ...old.requests, ...desired])
          r.token: r,
      }.values.toList();
      await _save(
        old.copy(
          requests: entries,
          routes: routes
              .skip(routes.length > 64 ? routes.length - 64 : 0)
              .toList(),
        ),
      );
      for (final r in obsolete) {
        await port.cancel(r.id);
        if ((await port.pendingIds()).contains(r.id)) {
          throw StateError('cancel_pending');
        }
        await _save(
          manifest!.copy(
            requests: manifest!.requests.where((x) => x.id != r.id).toList(),
          ),
        );
      }
      var pending = await port.pendingIds();
      for (final d in desired) {
        if (!_current(epoch, user, shop, session)) {
          await _cancelAll();
          return;
        }
        final key = '${d.sourceKind}:${d.sourceId}';
        final age = clock.elapsed - started;
        if (age > const Duration(minutes: 2)) {
          throw const DebtReadException('stale_native_cursor');
        }
        if (!d.at.isAfter(now.add(clock.elapsed - snapshot.receivedAt))) {
          await port.cancel(d.id);
          states[key] = DeviceReminderState.missed;
          await _save(
            manifest!.copy(
              requests: manifest!.requests.where((r) => r.id != d.id).toList(),
            ),
          );
          continue;
        }
        final saved = manifest!.requests.singleWhere((r) => r.id == d.id);
        if (!saved.applied || !pending.contains(d.id)) {
          // Unknown replies/crashes may have registered already. Cancel first, then replace same ID.
          await port.cancel(d.id);
          if ((await port.pendingIds()).contains(d.id)) {
            throw StateError('cancel_pending');
          }
          if (!_current(epoch, user, shop, session)) {
            await _cancelAll();
            return;
          }
          await port.replace(d);
          pending = await port.pendingIds();
          if (!pending.contains(d.id)) throw StateError('registration_unknown');
          if (!_current(epoch, user, shop, session)) {
            await _cancelAll();
            return;
          }
          await _save(
            manifest!.copy(
              requests: manifest!.requests
                  .map((r) => r.id == d.id ? d.marked(true) : r)
                  .toList(),
            ),
          );
        }
        states[key] = DeviceReminderState.registered;
      }
      if (_current(epoch, user, shop, session)) {
        _publish(
          ReminderDeviceReport(
            DeviceReminderState.registered,
            rows: states,
            at: snapshot.at,
          ),
        );
      }
    } on DebtReadException catch (e) {
      if (const {
        'forbidden',
        'session_expired',
        'unauthenticated',
        'shop_unavailable',
      }.contains(e.code)) {
        try {
          await _cancelAll();
        } catch (_) {}
      }
      _publish(ReminderDeviceReport(DeviceReminderState.stale, error: e.code));
    } catch (_) {
      _publish(
        const ReminderDeviceReport(
          DeviceReminderState.failed,
          error: 'reconciliation_pending',
        ),
      );
    }
  });
}

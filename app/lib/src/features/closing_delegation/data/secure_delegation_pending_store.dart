import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../daily_ledger/application/idempotency_key.dart' show isUuid;
import '../application/closing_delegation_gateway.dart';

final class SecureDelegationPendingStore implements DelegationPendingStore {
  const SecureDelegationPendingStore({
    this.storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage storage;
  static final _tails = <String, Future<void>>{};
  Future<T> _serial<T>(String user, String scope, Future<T> Function() work) {
    final slot = _slot(user, scope);
    final next = (_tails[slot] ?? Future<void>.value()).then((_) => work());
    final tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _tails[slot] = tail;
    tail.then((_) {
      if (identical(_tails[slot], tail)) _tails.remove(slot);
    });
    return next;
  }

  String _slot(String user, String scope) =>
      'closing_delegation_v1_${Uri.encodeComponent(user)}_${Uri.encodeComponent(scope)}';
  bool _valid(PendingDelegation pending) {
    if (!isUuid(pending.key)) return false;
    final allowed = switch (pending.kind) {
      'create' => {'name', 'phone'},
      'assign' => {'target', 'day_id', 'day_version'},
      'disable' || 'revoke' => {'target'},
      'submit' => {'task_id', 'observations'},
      _ => <String>{},
    };
    return allowed.isNotEmpty &&
        pending.payload.length == allowed.length &&
        pending.payload.keys.toSet().containsAll(allowed);
  }

  @override
  Future<PendingDelegation?> read(String userId, String scope) =>
      _serial(userId, scope, () => _read(userId, scope));
  Future<PendingDelegation?> _read(String userId, String scope) async {
    final raw = await storage.read(key: _slot(userId, scope));
    if (raw == null) return null;
    final json = jsonDecode(raw);
    if (json is! Map ||
        json['version'] != 1 ||
        json['key'] is! String ||
        json['kind'] is! String ||
        json['payload'] is! Map) {
      throw const FormatException('delegation_pending');
    }
    final pending = PendingDelegation(
      json['key'] as String,
      json['kind'] as String,
      Map<String, Object?>.from(json['payload'] as Map),
    );
    if (!_valid(pending)) throw const FormatException('delegation_pending');
    return pending;
  }

  @override
  Future<void> save(String userId, String scope, PendingDelegation pending) =>
      _serial(userId, scope, () async {
        if (!_valid(pending)) throw const FormatException('delegation_pending');
        final current = await _read(userId, scope);
        if (current != null &&
            (current.key != pending.key ||
                current.kind != pending.kind ||
                jsonEncode(current.payload) != jsonEncode(pending.payload))) {
          throw StateError('delegation_pending_locked');
        }
        await storage.write(
          key: _slot(userId, scope),
          value: jsonEncode({
            'version': 1,
            'key': pending.key,
            'kind': pending.kind,
            'payload': pending.payload,
          }),
        );
      });
  @override
  Future<void> clear(String userId, String scope, String key) => _serial(
    userId,
    scope,
    () async {
      final current = await _read(userId, scope);
      if (current?.key == key) await storage.delete(key: _slot(userId, scope));
    },
  );
}

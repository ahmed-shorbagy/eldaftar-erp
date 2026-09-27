import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../application/idempotency_key.dart';
import '../application/pending_opening_store.dart';
import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';

const _validationCodes = <String>{
  'invalid_input',
  'negative_amount',
  'overflow',
  'unsupported_category_karat',
  'duplicate_bucket',
};

class SharedPreferencesPendingOpeningStore implements PendingOpeningStore {
  const SharedPreferencesPendingOpeningStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  }) async {
    final raw = _preferences.getString(_key(userId, shopId));
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw);
    if (json is! Map) throw const FormatException('pending');
    const allowed = {
      'idempotency_key',
      'payload',
      'disposition',
      'operation_id',
      'rejection_code',
    };
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('pending');
    }
    final key = json['idempotency_key'];
    final payload = json['payload'];
    if (key is! String || !isUuid(key) || payload is! Map) {
      throw const FormatException('pending');
    }
    final disposition =
        _disposition(json['disposition']) ?? PendingDisposition.unresolved;
    final operationId = json['operation_id'];
    final rejectionCode = json['rejection_code'];
    if (disposition == PendingDisposition.acknowledged) {
      if (operationId is! String || !isUuid(operationId)) {
        throw const FormatException('pending');
      }
    } else if (operationId != null) {
      throw const FormatException('pending');
    }
    if (rejectionCode != null &&
        (disposition != PendingDisposition.validationRejected ||
            rejectionCode is! String ||
            !_validationCodes.contains(rejectionCode))) {
      throw const FormatException('pending');
    }
    final boxed = _objectMap(payload);
    if (disposition != PendingDisposition.acknowledged) {
      final parsed = OpeningDraft.parseJson(boxed);
      if (parsed is! Accepted<OpeningDraft>) {
        throw const FormatException('pending');
      }
    }
    return PendingOpening(
      idempotencyKey: key,
      payload: boxed,
      disposition: disposition,
      operationId: operationId is String ? operationId : null,
      rejectionCode: rejectionCode is String ? rejectionCode : null,
    );
  }

  @override
  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {
    if (!isUuid(pending.idempotencyKey)) {
      throw const FormatException('pending');
    }
    final stored = jsonEncode({
      'idempotency_key': pending.idempotencyKey,
      'payload': pending.payload,
      'disposition': _dispositionWire(pending.disposition),
      if (pending.operationId != null) 'operation_id': pending.operationId,
      if (pending.rejectionCode != null)
        'rejection_code': pending.rejectionCode,
    });
    final wrote = await _preferences.setString(_key(userId, shopId), stored);
    if (!wrote) throw StateError('pending-store');
  }

  @override
  Future<void> retire({required String userId, required String shopId}) async {
    final removed = await _preferences.remove(_key(userId, shopId));
    if (!removed && _preferences.containsKey(_key(userId, shopId))) {
      throw StateError('pending-store');
    }
  }

  String _key(String userId, String shopId) =>
      'eldafttar.opening.v1.$userId.$shopId';

  PendingDisposition? _disposition(Object? value) => switch (value) {
    'unresolved' => PendingDisposition.unresolved,
    'validation_rejected' => PendingDisposition.validationRejected,
    'acknowledged' => PendingDisposition.acknowledged,
    null => null,
    _ => throw const FormatException('pending'),
  };

  String _dispositionWire(PendingDisposition disposition) =>
      switch (disposition) {
        PendingDisposition.unresolved => 'unresolved',
        PendingDisposition.validationRejected => 'validation_rejected',
        PendingDisposition.acknowledged => 'acknowledged',
      };

  Map<String, Object?> _objectMap(Map<dynamic, dynamic> value) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _boxed(entry.value),
    };
  }

  Object? _boxed(Object? value) {
    if (value is Map) return _objectMap(value);
    if (value is List) {
      return <Object?>[for (final item in value) _boxed(item)];
    }
    return value;
  }
}

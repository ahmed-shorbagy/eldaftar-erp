import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../inventory/application/inventory_contract.dart';
import '../application/idempotency_key.dart';
import '../application/pending_financial_command.dart';

/// Stores one in-flight financial command per owner and shop.
final class PendingFinancialCommands implements FinancialCommandLocker {
  const PendingFinancialCommands({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  String _storageKey(String userId, String shopId) =>
      'pending_financial_${userId}_$shopId';

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async {
    final key = _storageKey(userId, shopId);
    var raw = await storage.read(key: key);
    final preferences = await SharedPreferences.getInstance();
    var legacy = false;
    if (raw == null) {
      raw = preferences.getString(key);
      legacy = raw != null;
    } else if (preferences.containsKey(key) && !await preferences.remove(key)) {
      throw StateError('pending_financial_legacy_clear');
    }
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['key'] is! String ||
        !isUuid(decoded['key'] as String) ||
        decoded['kind'] is! String ||
        decoded['body'] is! Map) {
      throw const FormatException('pending_financial');
    }
    final kind = decoded['kind'] as String;
    if (!{
      'sale',
      'purchase',
      'expense',
      'close_day',
      'open_day',
      'purchase_settlement',
      'cash_transfer',
      'scrap_sale',
      'scrap_to_stock',
      'sale_return',
      'purchase_return',
      'ledger_correction',
      'linked_return',
      'exchange',
      ...inventoryRpcs.keys,
    }.contains(kind)) {
      throw const FormatException('pending_financial');
    }
    final body = Map<String, Object?>.from(decoded['body'] as Map);
    if (!_matchesEnvelope(decoded['key'] as String, kind, body)) {
      throw const FormatException('pending_financial');
    }
    final command = PendingFinancialCommand(
      key: decoded['key'] as String,
      kind: kind,
      body: body,
    );
    if (legacy) {
      await storage.write(key: key, value: raw);
      if (!await preferences.remove(key)) {
        throw StateError('pending_financial_legacy_clear');
      }
    }
    return command;
  }

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    if (!isUuid(command.key) ||
        !_matchesEnvelope(command.key, command.kind, command.body)) {
      throw const FormatException('pending_financial');
    }
    final existing = await read(userId, shopId);
    if (existing != null && existing.key != command.key) {
      throw StateError('pending_financial_exists');
    }
    if (existing != null &&
        (existing.kind != command.kind ||
            jsonEncode(existing.body) != jsonEncode(command.body))) {
      throw StateError('pending_financial_payload_mismatch');
    }
    await storage.write(
      key: _storageKey(userId, shopId),
      value: jsonEncode({
        'key': command.key,
        'kind': command.kind,
        'body': command.body,
      }),
    );
  }

  @override
  Future<void> clear(String userId, String shopId, String key) async {
    final existing = await read(userId, shopId);
    if (existing == null || existing.key != key) return;
    await storage.delete(key: _storageKey(userId, shopId));
  }

  bool _matchesEnvelope(String key, String kind, Map<String, Object?> body) {
    if (body['p_idempotency_key'] != key) return false;
    if (const {
      'ledger_correction',
      'linked_return',
      'exchange',
    }.contains(kind)) {
      final payload = body['p_payload'];
      return body.length == 2 &&
          payload is Map &&
          payload['version'] == 1 &&
          (kind == 'linked_return'
              ? const {
                  'sale_return',
                  'purchase_return',
                }.contains(payload['kind'])
              : payload['kind'] == kind) &&
          payload['expected_day_id'] is String &&
          isUuid(payload['expected_day_id'] as String) &&
          payload['expected_day_version'] is String &&
          RegExp(
            r'^[1-9][0-9]*$',
          ).hasMatch(payload['expected_day_version'] as String);
    }
    if (const {'sale', 'purchase', 'expense', 'scrap_sale'}.contains(kind)) {
      final payload = body['p_payload'];
      return payload is Map && payload['kind'] == kind;
    }
    if (kind == 'close_day') {
      return body['p_day_id'] is String &&
          body['p_expected_version'] is int &&
          body['p_counts'] is Map;
    }
    if (kind == 'purchase_settlement') {
      return body['p_purchase_operation_id'] is String &&
          body['p_tenders'] is List;
    }
    if (kind == 'cash_transfer') {
      final payload = body['p_payload'];
      return body.length == 2 &&
          payload is Map &&
          payload['kind'] == 'cash_transfer' &&
          payload['from_method'] is String &&
          payload['to_method'] is String &&
          payload['amount_piastres'] is String;
    }
    if (kind == 'scrap_to_stock') {
      final payload = body['p_payload'];
      return body.length == 2 &&
          payload is Map &&
          payload['kind'] == 'scrap_to_stock' &&
          payload['category'] is String &&
          payload['karat'] is int &&
          payload['milligrams'] is String &&
          payload['count'] is String;
    }
    if (kind == 'sale_return' || kind == 'purchase_return') {
      return body.length == 3 &&
          body['p_idempotency_key'] == key &&
          body['p_original_operation_id'] is String &&
          body['p_note'] is String;
    }
    if (inventoryRpcs.containsKey(kind)) {
      return matchesInventoryEnvelope(key, kind, body);
    }
    return kind == 'open_day' && body.length == 1;
  }
}

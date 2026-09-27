import 'dart:convert';

import 'package:http/http.dart' as http;

import '../application/daily_ledger_view.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import 'daily_ledger_codec.dart';

const _errorCodes = <String>{
  'invalid_input',
  'negative_amount',
  'overflow',
  'unsupported_category_karat',
  'duplicate_bucket',
  'opening_already_confirmed',
  'payload_mismatch',
  'shop_not_active',
  'shop_unavailable',
  'session_expired',
  'unauthenticated',
  'forbidden',
};

class HttpOpeningGateway implements OpeningGateway {
  HttpOpeningGateway({
    required http.Client client,
    required String supabaseUrl,
    required String publishableKey,
    required String Function() accessToken,
    required String? Function() currentUserId,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client,
       _supabaseUrl = supabaseUrl.endsWith('/')
           ? supabaseUrl.substring(0, supabaseUrl.length - 1)
           : supabaseUrl,
       _publishableKey = publishableKey,
       _accessToken = accessToken,
       _currentUserId = currentUserId;

  final http.Client _client;
  final String _supabaseUrl;
  final String _publishableKey;
  final String Function() _accessToken;
  final String? Function() _currentUserId;
  final Duration timeout;

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    final http.Response response;
    try {
      response = await _post(callerUserId, 'confirm_opening_balances', {
        'p_idempotency_key': idempotencyKey,
        'p_payload': payload,
      });
    } on _CallerRejected catch (error) {
      return ConfirmRejected(error.code);
    } catch (_) {
      return const ConfirmUnknown();
    }
    if (response.statusCode >= 500) return const ConfirmUnknown();
    if (response.statusCode >= 400) {
      final code = _errorCode(response.body);
      if (code == null) return const ConfirmUnknown();
      return ConfirmRejected(code);
    }
    try {
      final json = jsonDecode(response.body);
      if (json is! Map || json['ok'] != true) return const ConfirmUnknown();
      final operationId = json['operation_id'];
      final businessDayId = json['business_day_id'];
      final businessDate = json['business_date'];
      final replayed = json['replayed'];
      if (operationId is! String ||
          businessDayId is! String ||
          businessDate is! String ||
          replayed is! bool ||
          !isUuid(operationId) ||
          !isUuid(businessDayId) ||
          !isCalendarDate(businessDate)) {
        return const ConfirmUnknown();
      }
      return ConfirmCommitted(
        operationId: operationId,
        businessDayId: businessDayId,
        businessDate: businessDate,
        replayed: replayed,
      );
    } catch (_) {
      return const ConfirmUnknown();
    }
  }

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    final http.Response response;
    try {
      response = await _post(callerUserId, 'get_opening_status', {
        'p_idempotency_key': idempotencyKey,
      });
    } on _CallerRejected catch (error) {
      return StatusRejected(error.code);
    } catch (_) {
      return const StatusUnknown();
    }
    if (response.statusCode >= 500) return const StatusUnknown();
    if (response.statusCode >= 400) {
      final code = _errorCode(response.body);
      if (code == null) return const StatusUnknown();
      return StatusRejected(code);
    }
    try {
      final json = jsonDecode(response.body);
      if (json is! Map) return const StatusUnknown();
      if (json['status'] == 'absent') return const StatusAbsent();
      final operationId = json['operation_id'];
      if (json['status'] == 'completed' &&
          operationId is String &&
          isUuid(operationId)) {
        return StatusCompleted(operationId);
      }
      return const StatusUnknown();
    } catch (_) {
      return const StatusUnknown();
    }
  }

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    final http.Response response;
    try {
      response = await _post(callerUserId, 'get_daily_ledger', {});
    } on _CallerRejected catch (error) {
      throw LedgerReadException(error.code);
    } catch (_) {
      throw const LedgerReadException();
    }
    if (response.statusCode >= 500) throw const LedgerReadException();
    if (response.statusCode >= 400) {
      throw LedgerReadException(_errorCode(response.body));
    }
    try {
      return parseDailyLedger(jsonDecode(response.body));
    } on FormatException {
      throw const LedgerReadException();
    } catch (_) {
      throw const LedgerReadException();
    }
  }

  Future<http.Response> _post(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
  ) {
    final owner = _currentUserId();
    final token = _accessToken();
    if (owner == null || owner.isEmpty || token.isEmpty) {
      throw const _CallerRejected('unauthenticated');
    }
    if (owner != callerUserId) {
      throw const _CallerRejected('session_expired');
    }
    final request = http.Request(
      'POST',
      Uri.parse('$_supabaseUrl/rest/v1/rpc/$rpc'),
    );
    request.headers['apikey'] = _publishableKey;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    request.body = jsonEncode(body);
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  }

  String? _errorCode(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final message = json['message'];
      if (message is String && _errorCodes.contains(message)) return message;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _CallerRejected implements Exception {
  const _CallerRejected(this.code);
  final String code;
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/pending_financial_command.dart';
import '../application/opening_gateway.dart';
import '../domain/financial_draft.dart';
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
  'tender_mismatch',
  'line_price_mismatch',
  'insufficient_stock',
  'negative_owned_balance',
  'stock_pair_mismatch',
  'day_closed',
  'day_not_closed',
  'stale_day',
  'count_mismatch',
  'journal_imbalance',
  'already_settled',
  'settlement_exceeds_obligation',
};

class HttpOpeningGateway
    implements
        OpeningGateway,
        FinancialGateway,
        InvoiceDispatchGateway,
        PurchaseSettlementGateway,
        CashTransferGateway,
        ScrapToStockGateway,
        LinkedReturnGateway {
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
    http.Response response;
    try {
      response = await _post(callerUserId, 'get_daily_ledger_v2', {});
      if (_rpcMissing(response)) {
        response = await _post(callerUserId, 'get_daily_ledger', {});
      }
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

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) {
    final rpc = switch (command.kind) {
      'sale' ||
      'purchase' ||
      'expense' ||
      'scrap_sale' => 'post_daily_ledger_trade',
      'close_day' => 'close_daily_ledger_day',
      'open_day' => 'open_daily_ledger_day',
      'purchase_settlement' => 'settle_purchase_cash_payable',
      'cash_transfer' => 'post_daily_ledger_cash_transfer',
      'scrap_to_stock' => 'post_daily_ledger_scrap_to_stock',
      'sale_return' || 'purchase_return' => 'post_daily_ledger_return',
      _ => throw const FormatException('pending_financial'),
    };
    return _financialCommand(callerUserId, rpc, command.body);
  }

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) => _financialCommand(callerUserId, 'post_daily_ledger_trade', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': draft.toJson(),
  });

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async {
    try {
      final response = await _post(
        callerUserId,
        'get_daily_ledger_day_state',
        {},
      );
      if (response.statusCode >= 400) {
        throw LedgerReadException(_errorCode(response.body));
      }
      final value = jsonDecode(response.body);
      if (value is! Map || value['state'] is! String) {
        throw const LedgerReadException();
      }
      if (value['state'] == 'uninitialized') {
        return const FinancialDayState(state: 'uninitialized');
      }
      final id = value['business_day_id'];
      final date = value['business_date'];
      final version = value['day_version'];
      final counts = value['counts'];
      if ((value['state'] != 'open' && value['state'] != 'closed') ||
          id is! String ||
          date is! String ||
          version is! int ||
          counts is! Map ||
          !isUuid(id) ||
          !isCalendarDate(date) ||
          version < 1) {
        throw const LedgerReadException();
      }
      return FinancialDayState(
        state: value['state'] as String,
        dayId: id,
        businessDate: date,
        dayVersion: version,
        counts: Map<String, Object?>.from(counts),
      );
    } on _CallerRejected catch (error) {
      throw LedgerReadException(error.code);
    } on LedgerReadException {
      rethrow;
    } catch (_) {
      throw const LedgerReadException();
    }
  }

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) => _financialCommand(callerUserId, 'close_daily_ledger_day', {
    'p_idempotency_key': idempotencyKey,
    'p_day_id': expected.dayId,
    'p_expected_version': expected.dayVersion,
    'p_counts': counted,
  });

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) => _financialCommand(callerUserId, 'open_daily_ledger_day', {
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async {
    if (!isUuid(operationId)) throw const LedgerReadException('invalid_input');
    try {
      final response = await _post(callerUserId, 'get_daily_ledger_operation', {
        'p_operation_id': operationId,
      });
      if (response.statusCode >= 400) {
        throw LedgerReadException(_errorCode(response.body));
      }
      final value = jsonDecode(response.body);
      if (value is! Map || value['operation_id'] != operationId) {
        throw const LedgerReadException();
      }
      return Map<String, Object?>.from(value);
    } on _CallerRejected catch (error) {
      throw LedgerReadException(error.code);
    } on LedgerReadException {
      rethrow;
    } catch (_) {
      throw const LedgerReadException();
    }
  }

  @override
  Future<InvoiceDispatchState> dispatchState({
    required String callerUserId,
    required String operationId,
  }) async {
    if (!isUuid(operationId)) throw const LedgerReadException('invalid_input');
    final response = await _post(callerUserId, 'get_invoice_dispatch_state', {
      'p_operation_id': operationId,
    });
    if (response.statusCode >= 400) {
      throw LedgerReadException(_errorCode(response.body));
    }
    final value = jsonDecode(response.body);
    if (value is! Map || value['operation_id'] != operationId) {
      throw const LedgerReadException();
    }
    final status = value['status'];
    if (status == 'unconfirmed') {
      return const InvoiceDispatchState(ownerConfirmed: false);
    }
    if (status != 'owner_confirmed' || value['confirmed_at'] is! String) {
      throw const LedgerReadException();
    }
    final confirmedAt = DateTime.tryParse(value['confirmed_at'] as String);
    if (confirmedAt == null) throw const LedgerReadException();
    return InvoiceDispatchState(
      ownerConfirmed: true,
      confirmedAt: confirmedAt.toUtc(),
    );
  }

  @override
  Future<PendingInvoicePage> pendingInvoiceSends({
    required String callerUserId,
    int? beforeSequence,
  }) async {
    if (beforeSequence != null && beforeSequence < 1) {
      throw const LedgerReadException('invalid_input');
    }
    final response = await _post(callerUserId, 'get_pending_invoice_sends', {
      'p_before_sequence': beforeSequence,
    });
    if (response.statusCode >= 400) {
      throw LedgerReadException(_errorCode(response.body));
    }
    final value = jsonDecode(response.body);
    if (value is! Map ||
        value['items'] is! List ||
        (value['next_before_sequence'] != null &&
            value['next_before_sequence'] is! int)) {
      throw const LedgerReadException();
    }
    final items = <PendingInvoice>[];
    for (final raw in value['items'] as List) {
      if (raw is! Map ||
          raw['operation_id'] is! String ||
          !isUuid(raw['operation_id'] as String) ||
          (raw['kind'] != 'sale' && raw['kind'] != 'purchase') ||
          raw['shop_sequence'] is! String ||
          raw['occurred_at_cairo'] is! String ||
          raw['customer_name'] is! String) {
        throw const LedgerReadException();
      }
      items.add(
        PendingInvoice(
          operationId: raw['operation_id'] as String,
          kind: raw['kind'] as String,
          shopSequence: raw['shop_sequence'] as String,
          occurredAtCairo: raw['occurred_at_cairo'] as String,
          customerName: raw['customer_name'] as String,
        ),
      );
    }
    return PendingInvoicePage(items, value['next_before_sequence'] as int?);
  }

  @override
  Future<FinancialCommandResult> confirmWhatsappSend({
    required String callerUserId,
    required String operationId,
    required String idempotencyKey,
  }) => _financialCommand(callerUserId, 'confirm_invoice_whatsapp_send', {
    'p_operation_id': operationId,
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<FinancialCommandResult> settlePurchaseCash({
    required String callerUserId,
    required String idempotencyKey,
    required String purchaseOperationId,
    required List<Map<String, Object?>> tenders,
  }) => _financialCommand(callerUserId, 'settle_purchase_cash_payable', {
    'p_idempotency_key': idempotencyKey,
    'p_purchase_operation_id': purchaseOperationId,
    'p_tenders': tenders,
  });

  @override
  Future<FinancialCommandResult> transferCash({
    required String callerUserId,
    required String idempotencyKey,
    required String fromMethod,
    required String toMethod,
    required String amountPiastres,
    required String note,
  }) => _financialCommand(callerUserId, 'post_daily_ledger_cash_transfer', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': {
      'version': 1,
      'kind': 'cash_transfer',
      'from_method': fromMethod,
      'to_method': toMethod,
      'amount_piastres': amountPiastres,
      'note': note,
    },
  });

  @override
  Future<FinancialCommandResult> convertScrapToStock({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => _financialCommand(callerUserId, 'post_daily_ledger_scrap_to_stock', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': payload,
  });

  @override
  Future<FinancialCommandResult> returnOperation({
    required String callerUserId,
    required String idempotencyKey,
    required String originalOperationId,
    required String note,
  }) => _financialCommand(callerUserId, 'post_daily_ledger_return', {
    'p_idempotency_key': idempotencyKey,
    'p_original_operation_id': originalOperationId,
    'p_note': note,
  });

  Future<FinancialCommandResult> _financialCommand(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (response.statusCode >= 500) return const FinancialUnknown();
      if (response.statusCode >= 400) {
        return FinancialRejected(_errorCode(response.body) ?? 'unavailable');
      }
      final value = jsonDecode(response.body);
      if (value is! Map) return const FinancialUnknown();
      if (value['ok'] == false && value['reason'] == 'count_mismatch') {
        final counts = value['expected_counts'];
        final version = value['day_version'];
        if (counts is Map && version is int) {
          return FinancialCountMismatch(
            Map<String, Object?>.from(counts),
            version,
          );
        }
      }
      final operationId = value['operation_id'];
      final replayed = value['replayed'];
      if (value['ok'] == true &&
          operationId is String &&
          isUuid(operationId) &&
          replayed is bool) {
        return FinancialCommitted(operationId, replayed: replayed);
      }
      return const FinancialUnknown();
    } on _CallerRejected catch (error) {
      return FinancialRejected(error.code);
    } catch (_) {
      return const FinancialUnknown();
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
      if (json['code'] == 'PGRST202') return 'rpc_unavailable';
      final message = json['message'];
      if (message is String && _errorCodes.contains(message)) return message;
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _rpcMissing(http.Response response) =>
      response.statusCode == 404 &&
      _errorCode(response.body) == 'rpc_unavailable';
}

class _CallerRejected implements Exception {
  const _CallerRejected(this.code);
  final String code;
}

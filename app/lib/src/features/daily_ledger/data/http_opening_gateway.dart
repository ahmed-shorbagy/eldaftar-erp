import '../../debts/application/debt_native_gateway.dart';
import '../../debts/application/debt_native_contract.dart';
import '../../debts/data/debt_native_codec.dart';
import 'dart:convert';
import '../../closing_delegation/application/closing_delegation_gateway.dart';
import '../../closing_delegation/data/closing_delegation_codec.dart';
import '../../customers/application/customer_contract.dart';
import '../../customers/application/customer_gateway.dart';
import '../../customers/domain/customer_contact.dart';
import '../../customers/data/customer_codec.dart';

import 'package:http/http.dart' as http;

import '../../inventory/application/inventory_contract.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../../inventory/data/inventory_codec.dart';
import '../../debts/application/debt_contract.dart';
import '../../debts/application/debt_due_contract.dart';
import '../../debts/application/debt_due_gateway.dart';
import '../../debts/data/debt_due_codec.dart';
import '../../debts/application/debt_gateway.dart';
import '../../debts/data/debt_codec.dart';
import '../../debts/application/debt_statement_gateway.dart';
import '../../debts/data/debt_statement_codec.dart';
import '../../debts/domain/debt_statement.dart';
import '../../debts/domain/debt_rules.dart';
import '../../repairs/application/repair_contract.dart';
import '../../repairs/application/repair_gateway.dart';
import '../../repairs/data/repair_codec.dart';
import '../../invoice_appearance/application/invoice_appearance_contract.dart';
import '../../invoice_appearance/application/invoice_appearance_gateway.dart';
import '../../invoice_appearance/data/invoice_appearance_codec.dart';
import '../../invoice_message/application/message_gateway.dart';
import '../../invoice_message/data/message_codec.dart';
import '../../daily_notes/application/notes_gateway.dart';
import '../../daily_notes/data/note_codec.dart';
import '../../daily_notes/domain/daily_note_draft.dart';
import '../application/ledger_activity.dart';
import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/pending_financial_command.dart';
import '../application/opening_gateway.dart';
import '../domain/financial_draft.dart';
import 'daily_ledger_codec.dart';
import '../application/ledger_date_gateway.dart';
import '../application/ledger_trade_change.dart';
import 'ledger_date_codec.dart';
import 'ledger_trade_change_codec.dart';

const _errorCodes = <String>{
  'stale_native',
  'trade_not_editable',
  'trade_has_followups',
  'trade_inactive',
  'stale_trade_review',
  'operation_replaced',
  'stale_native_cursor',
  'invalid_time',
  'unresolved_wall_time',
  'due_date_required',
  'attachment_rejected',
  'note_too_long',
  'image_too_large',
  'method_archived',
  'stale_version',
  'last_method_active',
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
  'pricing_mismatch',
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
  'not_found',
  'already_allocated',
  'custody_requires_transfer',
  'insufficient_lot',
  'return_exceeds_original',
  'already_returned',
  'explicit_refund_required',
  'stale_repair',
  'repair_not_ready',
  'repair_not_active',
  'repair_not_terminal',
  'repair_test_failure',
  'custody_already_released',
  'audit_append_only',
  'stale_debt',
  'stale_due',
  'stale_due_cursor',
  'due_not_active',
  'invalid_date',
  'ledger_effect_required',
  'duplicate_reference',
  'duplicate_debt',
  'duplicate_archive',
  'partly_settled',
  'source_cancel_forbidden',
  'invalid_name',
  'invalid_phone',
  'duplicate_phone',
  'primary_required',
  'duplicate_primary',
  'phone_conflict',
  'stale_customer',
  'stale_number',
  'customer_archived',
  'duplicate_link',
  'not_linked',
  'cross_shop',
  'wrong_operation_kind',
  'operation_not_confirmed',
  'invalid_state',
  'invalid_cursor',
  'cancel_not_allowed',
  'archive_not_allowed',
  'settlement_not_allowed',
  'stale_appearance',
  'stale_message',
  'stale_presentation',
  'stale_operation',
  'logo_rejected',
  'logo_not_uploaded',
  'logo_mismatch',
  'asset_missing',
};

class HttpOpeningGateway
    implements
        OpeningGateway,
        LedgerDateGateway,
        LedgerTradeChangeGateway,
        FinancialGateway,
        ClosingDelegationGateway,
        ClosingObservationGateway,
        InvoiceDispatchGateway,
        PurchaseSettlementGateway,
        CashTransferGateway,
        ScrapToStockGateway,
        LinkedReturnGateway,
        LedgerCorrectionGateway,
        PartialReturnGateway,
        ExchangeGateway,
        InventoryGateway,
        NotesGateway,
        CalendarNotesGateway,
        LedgerFeedGateway,
        RepairGateway,
        DebtGateway,
        DebtStatementGateway,
        DebtDueGateway,
        DebtNativeGateway,
        CustomerGateway,
        CustomerContactSession,
        InvoiceAppearanceGateway,
        InvoiceMessageGateway {
  @override
  Object? contactSession(String callerUserId) {
    try {
      return _callerToken(callerUserId);
    } catch (_) {
      return null;
    }
  }

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

  Future<Object?> _delegationRead(
    String user,
    String rpc,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(user, rpc, body);
      if (response.statusCode >= 400) {
        throw DelegationReadException(
          _errorCode(response.body) ?? 'unavailable',
        );
      }
      return jsonDecode(response.body);
    } on _CallerRejected catch (error) {
      throw DelegationReadException(error.code);
    } on _OwnerChanged {
      throw const DelegationReadException('session_expired');
    } on DelegationReadException {
      rethrow;
    } catch (_) {
      throw const DelegationReadException('unavailable');
    }
  }

  Future<DelegationResult> _delegationCommand(
    String user,
    String rpc,
    Map<String, Object?> body, {
    bool edge = false,
  }) async {
    try {
      final http.Response response;
      if (edge) {
        final token = _callerToken(user);
        response = await _client
            .post(
              Uri.parse('$_supabaseUrl/functions/v1/$rpc'),
              headers: {
                'apikey': _publishableKey,
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
        _sameOwner(user, token);
      } else {
        response = await _post(user, rpc, body);
      }
      if (response.statusCode >= 500) return const DelegationUnknown();
      if (response.statusCode >= 400) {
        return DelegationRejected(_errorCode(response.body) ?? 'unavailable');
      }
      final result = jsonDecode(response.body);
      if (result is! Map ||
          result['ok'] != true ||
          result['replayed'] is! bool ||
          !((result['staff_id'] is String &&
                  isUuid(result['staff_id'] as String)) ||
              (result['task_id'] is String &&
                  isUuid(result['task_id'] as String)))) {
        return const DelegationUnknown();
      }
      return const DelegationCommitted();
    } on _CallerRejected catch (error) {
      return DelegationRejected(error.code);
    } catch (_) {
      return const DelegationUnknown();
    }
  }

  @override
  Future<ClosingStaffDirectory> closingStaff({
    required String userId,
    required String shopId,
  }) async => parseClosingStaffDirectory(
    await _delegationRead(userId, 'list_closing_staff_v1', {}),
    shopId: shopId,
  );
  @override
  Future<StaffCountAssignment> myClosingAssignment({
    required String userId,
  }) async => parseStaffCountAssignment(
    await _delegationRead(userId, 'get_my_closing_task_v1', {}),
  );
  @override
  Future<DelegationResult> createClosingStaff({
    required String userId,
    required String key,
    required String name,
    required String phone,
    required String password,
  }) => _delegationCommand(userId, 'closing-staff-create', {
    'idempotency_key': key,
    'name': name,
    'phone': phone,
    'password': password,
  }, edge: true);
  Future<DelegationStatus> _delegationStatus(
    String user,
    String key,
    String rpc,
  ) async {
    try {
      final response = await _delegationRead(user, rpc, {'p_key': key});
      if (response is! Map) return DelegationStatus.unknown;
      return switch (response['status']) {
        'confirmed' => DelegationStatus.confirmed,
        'absent' => DelegationStatus.absent,
        'prepared' => DelegationStatus.prepared,
        _ => DelegationStatus.unknown,
      };
    } catch (_) {
      return DelegationStatus.unknown;
    }
  }

  @override
  Future<DelegationStatus> closingStaffCreationStatus({
    required String userId,
    required String key,
  }) => _delegationStatus(userId, key, 'get_closing_staff_creation_status_v1');
  @override
  Future<DelegationStatus> closingDelegationStatus({
    required String userId,
    required String key,
  }) => _delegationStatus(userId, key, 'get_closing_delegation_status_v1');
  @override
  Future<DelegationResult> changeClosingAssignment({
    required String userId,
    required String key,
    required String action,
    required String target,
    String? dayId,
    String? dayVersion,
  }) => _delegationCommand(userId, 'mutate_closing_delegation_v1', {
    'p_key': key,
    'p_action': action,
    'p_target': target,
    'p_day_id': dayId,
    'p_day_version': dayVersion,
  });
  @override
  Future<DelegationResult> submitClosingCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> observations,
  }) => _delegationCommand(userId, 'submit_closing_count_v1', {
    'p_key': key,
    'p_task_id': taskId,
    'p_observations': observations,
  });
  @override
  Future<FinancialCommandResult> closeFromStaffCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> cash,
  }) => _financialCommand(userId, 'close_daily_ledger_from_staff_v1', {
    'p_key': key,
    'p_task_id': taskId,
    'p_cash': cash,
  });

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
      response = await _post(callerUserId, 'get_daily_ledger_home_v1', {});
      if (_rpcMissing(response)) {
        response = await _post(callerUserId, 'get_daily_ledger_v2', {});
      }
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
    if (const {
      'sale_return',
      'purchase_return',
      'linked_return',
      'exchange',
    }.contains(command.kind)) {
      return _reconcileRetiredReturn(callerUserId, command);
    }
    if (command.kind == tradeChangeKind) {
      return postTradeChange(userId: callerUserId, command: command);
    }
    if (matchesExplicitLotSale(command.key, command.kind, command.body)) {
      return _financialCommand(
        callerUserId,
        'post_daily_ledger_trade_v2',
        command.body,
      );
    }
    final rpc = switch (command.kind) {
      'sale' ||
      'purchase' ||
      'expense' ||
      'scrap_sale' => 'post_daily_ledger_trade',
      'close_day' =>
        command.body['p_counts'] is Map &&
                (command.body['p_counts'] as Map)['version'] == 2
            ? 'close_daily_ledger_day_v2'
            : 'close_daily_ledger_day',
      'staff_close' => 'close_daily_ledger_from_staff_v1',
      'open_day' => 'open_daily_ledger_day',
      'purchase_settlement' => 'settle_purchase_cash_payable',
      'cash_transfer' => 'post_daily_ledger_cash_transfer',
      'scrap_to_stock' => 'post_daily_ledger_scrap_to_stock',
      'sale_return' || 'purchase_return' => 'post_daily_ledger_return',
      'linked_return' => 'post_linked_return_v1',
      'ledger_correction' => 'post_ledger_correction_v1',
      'exchange' => 'post_exchange_v1',
      _ => null,
    };
    if (rpc != null) return _financialCommand(callerUserId, rpc, command.body);
    final inventory = inventoryRpcs[command.kind];
    if (inventory == null) throw const FormatException('pending_financial');
    return _inventoryCommand(callerUserId, inventory, command.body);
  }

  Future<FinancialCommandResult> _reconcileRetiredReturn(
    String userId,
    PendingFinancialCommand command,
  ) async {
    final saved = await status(
      callerUserId: userId,
      idempotencyKey: command.key,
    );
    return switch (saved) {
      StatusCompleted(:final operationId) => FinancialCommitted(
        operationId,
        replayed: true,
      ),
      StatusAbsent() => const FinancialRejected('retired_return'),
      _ => const FinancialUnknown(),
    };
  }

  Future<Object?> _ledgerFeatureRead(
    String userId,
    String rpc,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(userId, rpc, body);
      if (_rpcMissing(response)) {
        throw const LedgerReadException('not_available');
      }
      if (response.statusCode >= 400) {
        throw LedgerReadException(_errorCode(response.body));
      }
      return jsonDecode(response.body);
    } on _CallerRejected catch (e) {
      throw LedgerReadException(e.code);
    }
  }

  @override
  Future<LedgerDateSnapshot> readLedgerDate({
    required String userId,
    required String shopId,
    String? businessDate,
    String? beforeSequence,
  }) async {
    final snapshot = parseLedgerDate(
      await _ledgerFeatureRead(userId, 'get_ledger_date_v1', {
        'p_business_date': businessDate,
        'p_before_sequence': beforeSequence,
        'p_limit': 100,
      }),
      shopId,
    );
    if (snapshot.businessDate != (businessDate ?? snapshot.serverDate)) {
      throw const FormatException('requested_ledger_date');
    }
    return snapshot;
  }

  @override
  Future<LedgerTradeChangeReview> reviewTradeChange({
    required String userId,
    required String shopId,
    required String operationId,
    required String action,
    Map<String, Object?>? replacement,
  }) async => parseTradeChangeReview(
    await _ledgerFeatureRead(userId, 'review_ledger_trade_change_v1', {
      'p_operation_id': operationId,
      'p_action': action,
      'p_replacement': replacement,
    }),
    shopId: shopId,
    operationId: operationId,
    action: action,
  );

  @override
  Future<FinancialCommandResult> postTradeChange({
    required String userId,
    required PendingFinancialCommand command,
  }) {
    if (!matchesTradeChangeEnvelope(command.key, command.kind, command.body)) {
      return Future.value(const FinancialRejected('invalid_input'));
    }
    return _financialCommand(
      userId,
      'post_ledger_trade_change_v1',
      command.body,
    );
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
  Future<FinancialCommandResult> postCorrection({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => _financialCommand(callerUserId, 'post_ledger_correction_v1', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': payload,
  });
  @override
  Future<FinancialCommandResult> postPartialReturn({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => _financialCommand(callerUserId, 'post_linked_return_v1', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': payload,
  });
  @override
  Future<FinancialCommandResult> postExchange({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => _financialCommand(callerUserId, 'post_exchange_v1', {
    'p_idempotency_key': idempotencyKey,
    'p_payload': payload,
  });
  @override
  Future<Map<String, Object?>> remainder({
    required String callerUserId,
    required String operationId,
  }) async {
    final response = await _post(callerUserId, 'get_return_remainder_v1', {
      'p_operation_id': operationId,
    });
    if (response.statusCode >= 400) {
      throw LedgerReadException(_errorCode(response.body));
    }
    final value = jsonDecode(response.body);
    if (value is! Map) throw const FormatException('return_remainder');
    return Map<String, Object?>.from(value);
  }

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
    } on _OwnerChanged {
      throw const LedgerReadException('session_expired');
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
  }) => _financialCommand(
    callerUserId,
    counted['version'] == 2
        ? 'close_daily_ledger_day_v2'
        : 'close_daily_ledger_day',
    {
      'p_idempotency_key': idempotencyKey,
      'p_day_id': expected.dayId,
      'p_expected_version': expected.dayVersion,
      'p_counts': counted,
    },
  );

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
    } on _OwnerChanged {
      throw const LedgerReadException('session_expired');
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

  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) => _parsed(callerUserId, 'get_inventory_totals_v1', {
    'p_category': ?category,
    'p_karat': ?karat,
  }, parseInventoryTotals);

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) {
    _boundedQuery(query);
    return _parsed(callerUserId, 'list_inventory_lots_v1', {
      'p_category': ?category,
      'p_karat': ?karat,
      'p_stock_class': ?stockClass,
      if (query != null && query.isNotEmpty) 'p_query': query,
      'p_limit': 50,
      'p_cursor': ?cursor,
    }, parseLotPage);
  }

  @override
  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  }) {
    if (!isUuid(lotId)) throw const InventoryReadException('invalid_input');
    return _parsed(callerUserId, 'list_lot_movements_v1', {
      'p_lot_id': lotId,
      'p_limit': 50,
      'p_cursor': ?cursor,
    }, parseMovementPage);
  }

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) {
    _boundedQuery(query);
    return _parsed(callerUserId, 'search_traders_v1', {
      if (query != null && query.isNotEmpty) 'p_query': query,
      'p_limit': 50,
      'p_cursor': ?cursor,
    }, parseTraderPage);
  }

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) {
    if (!isUuid(traderId)) throw const InventoryReadException('invalid_input');
    return _parsed(callerUserId, 'get_trader_v1', {
      'p_trader_id': traderId,
    }, parseTraderDetail);
  }

  @override
  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  }) {
    if (!isUuid(traderId)) throw const InventoryReadException('invalid_input');
    return _parsed(callerUserId, 'list_trader_activity_v1', {
      'p_trader_id': traderId,
      'p_limit': 50,
      'p_cursor': ?cursor,
    }, parseTraderActivity);
  }

  void _boundedQuery(String? query) {
    if (query != null && query.length > 120) {
      throw const InventoryReadException('invalid_input');
    }
  }

  Future<T> _parsed<T>(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
    T Function(Object? raw) parse,
  ) async {
    try {
      final response = await _rpc(callerUserId, rpc, body);
      return parse(jsonDecode(response.body));
    } on InventoryReadException {
      rethrow;
    } catch (_) {
      throw const InventoryReadException();
    }
  }

  @override
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) {
    if (matchesExplicitLotSale(command.key, command.kind, command.body)) {
      return _financialCommand(
        callerUserId,
        'post_daily_ledger_trade_v2',
        command.body,
      );
    }
    final rpc = inventoryRpcs[command.kind];
    if (rpc == null ||
        !matchesInventoryEnvelope(command.key, command.kind, command.body)) {
      return Future.value(const FinancialRejected('invalid_input'));
    }
    return _inventoryCommand(callerUserId, rpc, command.body);
  }

  @override
  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  }) async {
    if (traderId != null && !isUuid(traderId)) {
      throw const InventoryReadException('invalid_input');
    }
    final response =
        await _readResponse(callerUserId, 'list_inventory_receipts_v1', {
          'p_owner_kind': ?ownerKind,
          'p_trader_id': ?traderId,
          'p_recognition_policy': ?recognition,
          'p_limit': 50,
          'p_cursor': ?cursor,
        });
    if (_rpcMissing(response)) return const ReceiptPage.missing();
    if (response.statusCode >= 400) {
      throw InventoryReadException(_errorCode(response.body));
    }
    try {
      return parseReceiptPage(jsonDecode(response.body));
    } on FormatException {
      throw const InventoryReadException();
    }
  }

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => _catalogPage(
    callerUserId: callerUserId,
    table: 'inventory_products',
    select: 'id,name,category_code,karat,created_at',
    idColumn: 'id',
    query: query,
    queryColumn: 'name',
    cursor: cursor,
    parse: parseProductRow,
  );

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => _catalogPage(
    callerUserId: callerUserId,
    table: 'bullion_denominations',
    select: 'id,label,nominal_milligrams::text,active,created_at',
    idColumn: 'id',
    query: query,
    queryColumn: 'label',
    cursor: cursor,
    parse: parseDenominationRow,
  );

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => _catalogPage(
    callerUserId: callerUserId,
    table: 'coin_types',
    select: 'id,label,nominal_milligrams::text,active,created_at',
    idColumn: 'id',
    query: query,
    queryColumn: 'label',
    cursor: cursor,
    parse: parseCoinRow,
  );

  @override
  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  }) => _catalogPage(
    callerUserId: callerUserId,
    table: 'gold_obligations',
    select:
        'operation_id,trader_id,karat,initial_milligrams::text,remaining_milligrams::text,created_at',
    idColumn: 'operation_id',
    cursor: cursor,
    parse: parseGoldObligationRow,
  );

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) async {
    if (!isUuid(traderId)) throw const InventoryReadException('invalid_input');
    if (unit != null && unit != 'egp_piastres' && unit != 'gold_mg') {
      throw const InventoryReadException('invalid_input');
    }
    try {
      final response = await _rpc(callerUserId, 'list_trader_obligations_v1', {
        'p_trader_id': traderId,
        'p_unit': ?unit,
        'p_limit': 50,
        'p_cursor': ?cursor,
      });
      return parseTraderObligations(jsonDecode(response.body));
    } on InventoryReadException {
      rethrow;
    } on FormatException {
      throw const InventoryReadException();
    } catch (_) {
      throw const InventoryReadException();
    }
  }

  @override
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    if (!isUuid(idempotencyKey)) return const StatusUnknown();
    final http.Response response;
    try {
      response = await _get(callerUserId, 'inventory_catalog_requests', {
        'select': 'result',
        'idempotency_key': 'eq.$idempotencyKey',
        'limit': '1',
      });
    } on _OwnerChanged {
      return const StatusUnknown();
    } on _CallerRejected {
      return const StatusUnknown();
    } catch (_) {
      return const StatusUnknown();
    }
    if (_missingRelation(response) || response.statusCode >= 400) {
      return const StatusUnknown();
    }
    try {
      final rows = jsonDecode(response.body);
      if (rows is! List) return const StatusUnknown();
      if (rows.isEmpty) return const StatusAbsent();
      final row = rows.single;
      if (row is! Map) return const StatusUnknown();
      final result = row['result'];
      final value = result is String ? jsonDecode(result) : result;
      if (value is! Map) return const StatusUnknown();
      final id = value['id'];
      if (value['ok'] == true && id is String && isUuid(id)) {
        return StatusCompleted(id);
      }
      return const StatusUnknown();
    } catch (_) {
      return const StatusUnknown();
    }
  }

  Future<ReadPage<T>> _catalogPage<T>({
    required String callerUserId,
    required String table,
    required String select,
    required String idColumn,
    required T Function(Map<String, Object?> row) parse,
    String? query,
    String? queryColumn,
    String? cursor,
  }) async {
    _boundedQuery(query);
    if (query != null &&
        query.isNotEmpty &&
        !RegExp(r'^[0-9A-Za-z\u0600-\u06FF _.-]+$').hasMatch(query)) {
      throw const InventoryReadException('invalid_input');
    }
    final filter = _cursorFilter(cursor, idColumn);
    final http.Response response;
    try {
      response = await _get(callerUserId, table, {
        'select': select,
        'order': 'created_at.desc,$idColumn.desc',
        'limit': '51',
        if (query != null && query.isNotEmpty && queryColumn != null)
          queryColumn: 'ilike.*$query*',
        'or': ?filter,
      });
    } on _OwnerChanged {
      throw const InventoryReadException('discarded');
    } on _CallerRejected catch (error) {
      throw InventoryReadException(error.code);
    } catch (_) {
      throw const InventoryReadException();
    }
    if (_missingRelation(response)) return const ReadPage.missing();
    if (response.statusCode >= 400) {
      throw InventoryReadException(_errorCode(response.body));
    }
    try {
      final rows = jsonDecode(response.body);
      if (rows is! List) throw const InventoryReadException();
      final parsed = <T>[];
      for (final row in rows) {
        if (parsed.length == 50) break;
        parsed.add(parse(Map<String, Object?>.from(row as Map)));
      }
      String? next;
      if (rows.length > 50) {
        final last = Map<String, Object?>.from(rows[49] as Map);
        final stamp = last['created_at'];
        final id = last[idColumn];
        if (stamp is! String || id is! String || stamp.contains('|')) {
          throw const InventoryReadException();
        }
        next = '$stamp|$id';
      }
      return ReadPage.ready(parsed, next);
    } on InventoryReadException {
      rethrow;
    } catch (_) {
      throw const InventoryReadException();
    }
  }

  String? _cursorFilter(String? cursor, String idColumn) {
    if (cursor == null) return null;
    final split = cursor.split('|');
    if (split.length != 2 || split[0].isEmpty || !isUuid(split[1])) {
      throw const InventoryReadException('invalid_input');
    }
    final stamp = split[0];
    final id = split[1];
    return '(created_at.lt.$stamp,and(created_at.eq.$stamp,$idColumn.lt.$id))';
  }

  Future<http.Response> _readResponse(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
  ) async {
    try {
      return await _post(callerUserId, rpc, body);
    } on _OwnerChanged {
      throw const InventoryReadException('discarded');
    } on _CallerRejected catch (error) {
      throw InventoryReadException(error.code);
    } catch (_) {
      throw const InventoryReadException();
    }
  }

  Future<http.Response> _rpc(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _post(callerUserId, rpc, body);
    } on _OwnerChanged {
      throw const InventoryReadException('discarded');
    } on _CallerRejected catch (error) {
      throw InventoryReadException(error.code);
    } catch (_) {
      throw const InventoryReadException();
    }
    if (response.statusCode >= 400) {
      throw InventoryReadException(_errorCode(response.body));
    }
    return response;
  }

  Future<FinancialCommandResult> _inventoryCommand(
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
      final id = value['operation_id'] ?? value['id'];
      final replayed = value['replayed'];
      if (value['ok'] == true &&
          id is String &&
          isUuid(id) &&
          replayed is bool) {
        return FinancialCommitted(id, replayed: replayed);
      }
      return const FinancialUnknown();
    } on _OwnerChanged {
      return const FinancialUnknown();
    } on _CallerRejected catch (error) {
      return FinancialRejected(error.code);
    } catch (_) {
      return const FinancialUnknown();
    }
  }

  Future<http.Response> _get(
    String callerUserId,
    String table,
    Map<String, String> query,
  ) async {
    final token = _callerToken(callerUserId);
    final request = http.Request(
      'GET',
      Uri.parse('$_supabaseUrl/rest/v1/$table').replace(queryParameters: query),
    );
    request.headers['apikey'] = _publishableKey;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
    _sameOwner(callerUserId, token);
    return response;
  }

  bool _missingRelation(http.Response response) {
    if (response.statusCode != 404) return false;
    try {
      final json = jsonDecode(response.body);
      if (json is Map) {
        final code = json['code'];
        return code == 'PGRST205' || code == '42P01' || code == 'PGRST202';
      }
    } catch (_) {
      return false;
    }
    return false;
  }

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
    } on _OwnerChanged {
      return const FinancialUnknown();
    } on _CallerRejected catch (error) {
      return FinancialRejected(error.code);
    } catch (_) {
      return const FinancialUnknown();
    }
  }

  /// The token that authorized this call. A later mismatch is [_OwnerChanged].
  String _callerToken(String callerUserId) {
    final owner = _currentUserId();
    final token = _accessToken();
    if (owner == null || owner.isEmpty || token.isEmpty) {
      throw const _CallerRejected('unauthenticated');
    }
    if (owner != callerUserId) {
      throw const _CallerRejected('session_expired');
    }
    return token;
  }

  void _sameOwner(String callerUserId, String token) {
    final owner = _currentUserId();
    final current = _accessToken();
    if (owner != callerUserId ||
        owner == null ||
        owner.isEmpty ||
        current.isEmpty ||
        current != token) {
      throw const _OwnerChanged();
    }
  }

  Future<http.Response> _post(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
  ) async {
    final token = _callerToken(callerUserId);
    final request = http.Request(
      'POST',
      Uri.parse('$_supabaseUrl/rest/v1/rpc/$rpc'),
    );
    request.headers['apikey'] = _publishableKey;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
    _sameOwner(callerUserId, token);
    return response;
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
  bool _callerStill(String callerUserId) {
    final owner = _currentUserId();
    return owner != null && owner.isNotEmpty && owner == callerUserId;
  }

  String? _lockedSignedUrl(String signed, String objectName) {
    if (signed.isEmpty || signed.contains('service_role')) return null;
    final configured = Uri.parse(_supabaseUrl);
    final Uri resolved;
    if (signed.startsWith('http://') || signed.startsWith('https://')) {
      final absolute = Uri.parse(signed);
      if (absolute.scheme != configured.scheme ||
          absolute.host != configured.host ||
          absolute.port != configured.port) {
        return null;
      }
      if (absolute.userInfo.isNotEmpty) return null;
      resolved = absolute;
    } else if (signed.contains('://')) {
      return null;
    } else {
      final relative = signed.startsWith('/') ? signed : '/$signed';
      final parsed = Uri.parse(relative);
      resolved = configured.replace(
        path: '/storage/v1${parsed.path}',
        query: parsed.hasQuery ? parsed.query : null,
      );
    }
    final expected =
        '/storage/v1/object/sign/eldafttar-private-notes/$objectName';
    if (resolved.path != expected) return null;
    return resolved.toString();
  }

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    try {
      final response = await _post(callerUserId, 'post_daily_note', {
        'p_idempotency_key': idempotencyKey,
        'p_payload': payload,
      });
      if (!_callerStill(callerUserId)) return const NoteUnknown();
      if (response.statusCode >= 500) return const NoteUnknown();
      if (response.statusCode >= 400) {
        return NoteRejected(_errorCode(response.body) ?? 'unavailable');
      }
      return parseNoteCommand(jsonDecode(response.body));
    } on _CallerRejected catch (error) {
      return NoteRejected(error.code);
    } catch (_) {
      return const NoteUnknown();
    }
  }

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _post(callerUserId, 'get_daily_note_status', {
        'p_idempotency_key': idempotencyKey,
      });
      if (!_callerStill(callerUserId)) return const NoteStatusUnknown();
      if (response.statusCode >= 500) return const NoteStatusUnknown();
      if (response.statusCode >= 400) {
        return NoteStatusRejected(_errorCode(response.body) ?? 'unavailable');
      }
      return parseNoteStatus(jsonDecode(response.body));
    } on _CallerRejected catch (error) {
      return NoteStatusRejected(error.code);
    } catch (_) {
      return const NoteStatusUnknown();
    }
  }

  @override
  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) async {
    final trimmed = query?.trim();
    if (limit < 1 ||
        limit > 50 ||
        (trimmed != null && trimmed.runes.length > noteSearchMaxChars)) {
      throw const FormatException('notes');
    }
    try {
      final response = await _post(callerUserId, 'list_daily_notes', {
        'p_day_id': dayId,
        'p_before_sequence': beforeSequence,
        'p_limit': limit,
        'p_query': trimmed == null || trimmed.isEmpty ? null : trimmed,
      });
      if (!_callerStill(callerUserId)) {
        throw const NoteReadException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw NoteReadException(_errorCode(response.body));
      }
      return parseDailyNotePage(
        jsonDecode(response.body),
        expectedShopId: shopId,
      );
    } on _OwnerChanged {
      throw const NoteReadException('session_expired');
    } on NoteReadException {
      rethrow;
    } on _CallerRejected catch (error) {
      throw NoteReadException(error.code);
    } on FormatException {
      throw const NoteReadException();
    } catch (_) {
      throw const NoteReadException();
    }
  }

  @override
  Future<DailyNotePage> listNotesForDate({
    required String callerUserId,
    required String shopId,
    required String businessDate,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) async {
    final trimmed = query?.trim();
    if (limit < 1 ||
        limit > 50 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(businessDate) ||
        (trimmed != null && trimmed.runes.length > noteSearchMaxChars)) {
      throw const NoteReadException('invalid_input');
    }
    try {
      final response = await _post(callerUserId, 'list_daily_notes_date_v1', {
        'p_business_date': businessDate,
        'p_before_sequence': beforeSequence,
        'p_limit': limit,
        'p_query': trimmed == null || trimmed.isEmpty ? null : trimmed,
      });
      if (!_callerStill(callerUserId)) {
        throw const NoteReadException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw NoteReadException(_errorCode(response.body));
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['business_date'] != businessDate ||
          body.length != 2) {
        throw const FormatException('notes_date');
      }
      return parseDailyNotePage(body['page'], expectedShopId: shopId);
    } on _OwnerChanged {
      throw const NoteReadException('session_expired');
    } on _CallerRejected catch (error) {
      throw NoteReadException(error.code);
    } on NoteReadException {
      rethrow;
    } catch (_) {
      throw const NoteReadException();
    }
  }

  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) async {
    try {
      final response = await _post(callerUserId, 'get_daily_note', {
        'p_note_id': noteId,
      });
      if (!_callerStill(callerUserId)) {
        throw const NoteReadException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw NoteReadException(_errorCode(response.body));
      }
      return parseDailyNote(jsonDecode(response.body), expectedShopId: shopId);
    } on _OwnerChanged {
      throw const NoteReadException('session_expired');
    } on NoteReadException {
      rethrow;
    } on _CallerRejected catch (error) {
      throw NoteReadException(error.code);
    } on FormatException {
      throw const NoteReadException();
    } catch (_) {
      throw const NoteReadException();
    }
  }

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    if (!_noteObjectName(objectName) ||
        !noteMimeExtensions.containsKey(mimeType) ||
        bytes.isEmpty ||
        bytes.length > noteImageMaxBytes ||
        !objectName.endsWith('.${noteMimeExtensions[mimeType]}')) {
      return const NoteUploadResult(
        NoteUploadDisposition.rejected,
        code: 'attachment_rejected',
      );
    }
    try {
      final response = await _storage(
        callerUserId,
        'POST',
        'object/eldafttar-private-notes/${_encodePath(objectName)}',
        headers: {'Content-Type': mimeType, 'x-upsert': 'false'},
        body: bytes,
      );
      if (!_callerStill(callerUserId)) {
        return const NoteUploadResult(NoteUploadDisposition.unknown);
      }
      if (response.statusCode == 200) {
        return const NoteUploadResult(NoteUploadDisposition.stored);
      }
      if (response.statusCode == 409) {
        return const NoteUploadResult(NoteUploadDisposition.alreadyPresent);
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        return NoteUploadResult(
          NoteUploadDisposition.rejected,
          code: _errorCode(response.body) ?? 'attachment_rejected',
        );
      }
      return const NoteUploadResult(NoteUploadDisposition.unknown);
    } on _CallerRejected catch (error) {
      return NoteUploadResult(NoteUploadDisposition.rejected, code: error.code);
    } catch (_) {
      return const NoteUploadResult(NoteUploadDisposition.unknown);
    }
  }

  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  }) async {
    if (!_noteObjectName(objectName)) {
      throw const NoteReadException('attachment_rejected');
    }
    try {
      final response = await _storage(
        callerUserId,
        'POST',
        'object/sign/eldafttar-private-notes/${_encodePath(objectName)}',
        headers: const {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'expiresIn': 300})),
      );
      if (!_callerStill(callerUserId)) {
        throw const NoteReadException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw NoteReadException(_errorCode(response.body));
      }
      final json = jsonDecode(response.body);
      if (json is! Map) throw const NoteReadException();
      final expires = json['expiresIn'];
      if (expires is int && expires > 300) throw const NoteReadException();
      final signed = json['signedURL'] ?? json['signedUrl'];
      if (signed is! String) throw const NoteReadException();
      final locked = _lockedSignedUrl(signed, objectName);
      if (locked == null) throw const NoteReadException();
      return locked;
    } on _OwnerChanged {
      throw const NoteReadException('session_expired');
    } on NoteReadException {
      rethrow;
    } on _CallerRejected catch (error) {
      throw NoteReadException(error.code);
    } catch (_) {
      throw const NoteReadException();
    }
  }

  @override
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  }) async {
    if ((beforeSequence != null && afterSequence != null) ||
        limit < 1 ||
        limit > 100) {
      throw const FormatException('page');
    }
    try {
      final response = await _post(callerUserId, 'get_ledger_operation_page', {
        'p_day_id': dayId,
        'p_before_sequence': beforeSequence,
        'p_after_sequence': afterSequence,
        'p_limit': limit,
      });
      if (!_callerStill(callerUserId)) {
        throw const LedgerReadException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw LedgerReadException(_errorCode(response.body));
      }
      return parseLedgerOperationPage(
        jsonDecode(response.body),
        expectedShopId: shopId,
      );
    } on _OwnerChanged {
      throw const LedgerReadException('session_expired');
    } on LedgerReadException {
      rethrow;
    } on _CallerRejected catch (error) {
      throw LedgerReadException(error.code);
    } on FormatException {
      throw const LedgerReadException();
    } catch (_) {
      throw const LedgerReadException();
    }
  }

  Future<http.Response> _storage(
    String callerUserId,
    String method,
    String path, {
    required Map<String, String> headers,
    required List<int> body,
  }) {
    final owner = _currentUserId();
    final token = _accessToken();
    if (owner == null || owner.isEmpty || token.isEmpty) {
      throw const _CallerRejected('unauthenticated');
    }
    if (owner != callerUserId) {
      throw const _CallerRejected('session_expired');
    }
    final request = http.Request(
      method,
      Uri.parse('$_supabaseUrl/storage/v1/$path'),
    );
    request.headers.addAll(headers);
    request.headers['apikey'] = _publishableKey;
    request.headers['Authorization'] = 'Bearer $token';
    request.bodyBytes = body;
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  }

  @override
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    final rpc = repairRpcs[command.kind];
    if (rpc == null ||
        !ownsRepairCommand(command.key, command.kind, command.body)) {
      return const RepairRpcRejected('invalid_input');
    }
    try {
      final response = await _post(callerUserId, rpc, command.body);
      if (!_callerStill(callerUserId)) return const RepairRpcUnknown();
      if (response.statusCode >= 500) return const RepairRpcUnknown();
      if (response.statusCode >= 400) {
        final code = _errorCode(response.body);
        if (code == null) return const RepairRpcUnknown();
        return RepairRpcRejected(code);
      }
      return parseRepairCommand(jsonDecode(response.body));
    } on _OwnerChanged {
      return const RepairRpcUnknown();
    } on _CallerRejected catch (error) {
      return RepairRpcRejected(error.code);
    } on FormatException {
      return const RepairRpcUnknown();
    } catch (_) {
      return const RepairRpcUnknown();
    }
  }

  @override
  Future<RepairRemoteStatus> commandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _post(callerUserId, 'get_repair_command_status', {
        'p_idempotency_key': idempotencyKey,
      });
      if (!_callerStill(callerUserId) || response.statusCode >= 500) {
        return const RepairRemoteUnknown();
      }
      if (response.statusCode >= 400) {
        final code = _errorCode(response.body);
        if (code == null) return const RepairRemoteUnknown();
        return RepairRemoteRejected(code);
      }
      return parseRepairCommandStatus(jsonDecode(response.body));
    } on _OwnerChanged {
      return const RepairRemoteUnknown();
    } on _CallerRejected catch (error) {
      return RepairRemoteRejected(error.code);
    } on FormatException {
      return const RepairRemoteUnknown();
    } catch (_) {
      return const RepairRemoteUnknown();
    }
  }

  @override
  Future<RepairContext> context({required String callerUserId}) => _repairRead(
    callerUserId,
    'get_repair_context_v1',
    const {},
    parseRepairContext,
  );

  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) => _repairRead(callerUserId, 'list_repairs_v1', {
    'p_query': query,
    'p_filter': filter,
    'p_limit': limit,
    'p_cursor': cursor,
  }, parseRepairPage);

  @override
  Future<RepairDetail> detail({
    required String callerUserId,
    required String repairId,
  }) => _repairRead(callerUserId, 'get_repair_v1', {
    'p_repair_id': repairId,
  }, parseRepairDetail);

  Future<T> _repairRead<T>(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
    T Function(Object? raw) parse,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (!_callerStill(callerUserId)) {
        throw const RepairReadException('discarded');
      }
      if (response.statusCode >= 400) {
        throw RepairReadException(_errorCode(response.body));
      }
      return parse(jsonDecode(response.body));
    } on RepairReadException {
      rethrow;
    } on _OwnerChanged {
      throw const RepairReadException('discarded');
    } on _CallerRejected catch (error) {
      throw RepairReadException(error.code);
    } on FormatException {
      throw const RepairReadException();
    } catch (_) {
      throw const RepairReadException();
    }
  }

  @override
  Future<DebtRpcResult> submitCommand({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    final rpc = debtRpcs[command.kind];
    if (rpc == null ||
        !ownsDebtCommand(command.key, command.kind, command.body)) {
      return const DebtRpcRejected('invalid_input');
    }
    try {
      final response = await _post(callerUserId, rpc, command.body);
      if (!_callerStill(callerUserId)) return const DebtRpcUnknown();
      if (response.statusCode >= 500) return const DebtRpcUnknown();
      if (response.statusCode >= 400) {
        final code = _errorCode(response.body);
        if (code == null) return const DebtRpcUnknown();
        return DebtRpcRejected(code);
      }
      return parseDebtCommand(jsonDecode(response.body));
    } on _OwnerChanged {
      return const DebtRpcUnknown();
    } on _CallerRejected catch (error) {
      return DebtRpcRejected(error.code);
    } on FormatException {
      return const DebtRpcUnknown();
    } catch (_) {
      return const DebtRpcUnknown();
    }
  }

  @override
  Future<DebtRemoteStatus> readCommandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _post(callerUserId, 'get_debt_command_status_v1', {
        'p_idempotency_key': idempotencyKey,
      });
      if (!_callerStill(callerUserId) || response.statusCode >= 500) {
        return const DebtRemoteUnknown();
      }
      if (response.statusCode >= 400) {
        final code = _errorCode(response.body);
        if (code == null) return const DebtRemoteUnknown();
        return DebtRemoteRejected(code);
      }
      return parseDebtCommandStatus(jsonDecode(response.body));
    } on _OwnerChanged {
      return const DebtRemoteUnknown();
    } on _CallerRejected catch (error) {
      return DebtRemoteRejected(error.code);
    } on FormatException {
      return const DebtRemoteUnknown();
    } catch (_) {
      return const DebtRemoteUnknown();
    }
  }

  @override
  Future<DebtContext> readContext({required String callerUserId}) => _debtRead(
    callerUserId,
    'get_debt_context_v1',
    const {},
    parseDebtContext,
  );

  @override
  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) => _debtRead(callerUserId, 'get_debt_list_v1', {
    'p_query': query,
    'p_filter': filter,
    'p_limit': limit,
    'p_cursor': cursor,
  }, parseDebtPage);

  @override
  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  }) => _debtRead(callerUserId, 'get_debt_v1', {
    'p_source_kind': sourceKind,
    'p_source_id': sourceId,
  }, parseDebtDetail);

  Future<T> _debtRead<T>(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
    T Function(Object? raw) parse,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (!_callerStill(callerUserId)) {
        throw const DebtReadException('discarded');
      }
      if (response.statusCode >= 400) {
        throw DebtReadException(_errorCode(response.body));
      }
      return parse(jsonDecode(response.body));
    } on DebtReadException {
      rethrow;
    } on _OwnerChanged {
      throw const DebtReadException('discarded');
    } on _CallerRejected catch (error) {
      throw DebtReadException(error.code);
    } on FormatException {
      throw const DebtReadException();
    } catch (_) {
      throw const DebtReadException();
    }
  }

  @override
  Object? statementSession(String callerUserId) => contactSession(callerUserId);

  @override
  Object? dueSession(String userId) => contactSession(userId);

  @override
  Future<DebtDueDetail> readDue({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    final d = await _debtRead(userId, 'get_debt_due_v1', {
      'p_source_kind': sourceKind.wire,
      'p_source_id': sourceId,
    }, parseDebtDueDetail);
    if (d.row.shopId != shopId ||
        d.row.summary.sourceKind != sourceKind ||
        d.row.summary.sourceId != sourceId) {
      throw const DebtReadException('discarded');
    }
    return d;
  }

  @override
  Future<DebtReminderPage> readReminders({
    required String userId,
    required String shopId,
    required String query,
    required String filter,
    required String? cursor,
  }) async {
    final p = await _debtRead(userId, 'get_debt_reminders_v1', {
      'p_query': query,
      'p_filter': filter,
      'p_limit': 20,
      'p_cursor': cursor,
    }, parseDebtReminderPage);
    if (p.shopId != shopId ||
        p.items.any((r) => filter != 'all' && r.state != filter)) {
      throw const DebtReadException('discarded');
    }
    return p;
  }

  @override
  Future<DebtDueTransport> sendDue({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) => _dueTransport(userId, shopId, command, false);
  @override
  Future<DebtDueTransport> dueStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) => _dueTransport(userId, shopId, command, true);

  Future<DebtDueTransport> _dueTransport(
    String user,
    String shop,
    PendingFinancialCommand command,
    bool status,
  ) async {
    if (!matchesDebtDueEnvelope(command.key, command.kind, command.body)) {
      return const DebtDueTransport(error: 'invalid_input');
    }
    try {
      final r = await _post(
        user,
        status ? 'get_debt_due_status_v1' : 'post_debt_due_v1',
        command.body,
      );
      if (!_callerStill(user) || r.statusCode >= 500) {
        return const DebtDueTransport();
      }
      if (r.statusCode >= 400) {
        return DebtDueTransport(error: _errorCode(r.body));
      }
      final j = debtMap(jsonDecode(r.body));
      if (status && j['status'] == 'absent' && j.length == 1) {
        return const DebtDueTransport(absent: true);
      }
      if (status && (j['status'] != 'completed' || j.length != 2)) {
        return const DebtDueTransport();
      }
      final receipt = parseDebtDueReceipt(status ? j['result'] : j);
      final payload = debtMap(command.body['p_payload']);
      if (receipt.shopId != shop ||
          receipt.actorId != user ||
          receipt.key != command.key ||
          receipt.sourceKind != payload['source_kind'] ||
          receipt.sourceId != payload['source_id'] ||
          receipt.date?.wire != payload['due_date'] ||
          receipt.version !=
              BigInt.parse(payload['expected_due_version'] as String) +
                  BigInt.one ||
          canonicalDueJson(receipt.payload) != canonicalDueJson(payload)) {
        return const DebtDueTransport();
      }
      return DebtDueTransport(receipt: receipt);
    } on _CallerRejected catch (e) {
      return DebtDueTransport(error: e.code);
    } catch (_) {
      return const DebtDueTransport();
    }
  }

  @override
  Object? nativeSession(String userId) => contactSession(userId);
  @override
  Future<DebtNativeReview> reviewNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
    required String? time,
  }) async {
    final r = await _debtRead(userId, 'review_debt_native_v1', {
      'p_source_kind': sourceKind.wire,
      'p_source_id': sourceId,
      'p_reminder_time': time,
    }, parseDebtNativeReview);
    if (r.detail.row.due.shopId != shopId ||
        r.detail.row.due.summary.sourceKind != sourceKind ||
        r.detail.row.due.summary.sourceId != sourceId ||
        r.time != time) {
      throw const DebtReadException('discarded');
    }
    return r;
  }

  @override
  Future<DebtNativeDetail> readNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    final d = await _debtRead(userId, 'get_debt_native_v1', {
      'p_source_kind': sourceKind.wire,
      'p_source_id': sourceId,
    }, parseDebtNativeDetail);
    if (d.row.due.shopId != shopId ||
        d.row.due.summary.sourceKind != sourceKind ||
        d.row.due.summary.sourceId != sourceId) {
      throw const DebtReadException('discarded');
    }
    return d;
  }

  @override
  Future<DebtNativePage> readNativeQueue({
    required String userId,
    required String shopId,
    required String? cursor,
  }) async {
    final p = await _debtRead(userId, 'get_debt_native_queue_v1', {
      'p_limit': 50,
      'p_cursor': cursor,
    }, parseDebtNativePage);
    if (p.shopId != shopId) throw const DebtReadException('discarded');
    return p;
  }

  @override
  Future<DebtNativeTransport> sendNative({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) => _nativeTransport(userId, shopId, command, false);
  @override
  Future<DebtNativeTransport> nativeStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) => _nativeTransport(userId, shopId, command, true);

  Future<DebtNativeTransport> _nativeTransport(
    String user,
    String shop,
    PendingFinancialCommand command,
    bool status,
  ) async {
    if (!matchesDebtNativeEnvelope(command.key, command.kind, command.body)) {
      return const DebtNativeTransport(error: 'invalid_input');
    }
    try {
      final r = await _post(
        user,
        status ? 'get_debt_native_status_v1' : 'post_debt_native_v1',
        command.body,
      );
      if (!_callerStill(user) || r.statusCode >= 500) {
        return const DebtNativeTransport();
      }
      if (r.statusCode >= 400) {
        return DebtNativeTransport(error: _errorCode(r.body));
      }
      final j = debtMap(jsonDecode(r.body));
      if (status && j['status'] == 'absent' && j.length == 1) {
        return const DebtNativeTransport(absent: true);
      }
      if (status && (j['status'] != 'completed' || j.length != 2)) {
        return const DebtNativeTransport();
      }
      final receipt = parseDebtNativeReceipt(status ? j['result'] : j);
      final payload = debtMap(command.body['p_payload']);
      if (receipt.shopId != shop ||
          receipt.actorId != user ||
          receipt.key != command.key ||
          receipt.sourceKind != payload['source_kind'] ||
          receipt.sourceId != payload['source_id'] ||
          receipt.time != payload['reminder_time'] ||
          receipt.version !=
              BigInt.parse(payload['expected_native_version'] as String) +
                  BigInt.one ||
          canonicalDueJson(receipt.payload) != canonicalDueJson(payload)) {
        return const DebtNativeTransport();
      }
      return DebtNativeTransport(receipt: receipt);
    } on _CallerRejected catch (e) {
      return DebtNativeTransport(error: e.code);
    } catch (_) {
      return const DebtNativeTransport();
    }
  }

  @override
  Future<DebtStatement> readStatement({
    required String callerUserId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    final statement = await _debtRead(callerUserId, 'get_debt_statement_v1', {
      'p_source_kind': sourceKind.wire,
      'p_source_id': sourceId,
    }, parseDebtStatement);
    if (statement.shopId != shopId ||
        statement.sourceKind != sourceKind ||
        statement.sourceId != sourceId) {
      throw const DebtReadException('discarded');
    }
    return statement;
  }

  @override
  Future<CustomerTransport> sendCustomer({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    if (!matchesCustomerEnvelope(command.key, command.kind, command.body)) {
      return const CustomerTransport(error: 'invalid_input');
    }
    try {
      final r = await _post(
        callerUserId,
        customerRpcs[command.kind]!,
        command.body,
      );
      if (!_callerStill(callerUserId) || r.statusCode >= 500) {
        return const CustomerTransport();
      }
      if (r.statusCode >= 400) {
        return CustomerTransport(error: _errorCode(r.body));
      }
      return CustomerTransport(
        receipt: parseCustomerReceipt(jsonDecode(r.body), command),
      );
    } on _CallerRejected catch (e) {
      return CustomerTransport(error: e.code);
    } catch (_) {
      return const CustomerTransport();
    }
  }

  @override
  Future<CustomerTransport> customerStatus({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    try {
      final p = customerMap(command.body['p_payload']);
      final r = await _post(
        callerUserId,
        command.kind == 'customer_saved_number'
            ? 'get_customer_command_status_v2'
            : 'get_customer_command_status_v1',
        {
          'p_idempotency_key': command.key,
          'p_command_kind': command.kind,
          'p_customer_id': p['customer_id'],
          'p_payload': p,
        },
      );
      if (!_callerStill(callerUserId) || r.statusCode >= 400) {
        return const CustomerTransport();
      }
      final m = customerMap(jsonDecode(r.body));
      if (m['status'] == 'absent') return const CustomerTransport(absent: true);
      if (m['status'] != 'completed' || m['command_kind'] != command.kind) {
        return const CustomerTransport();
      }
      final receipt = parseCustomerReceipt(m['result'], command);
      if (receipt.customer.id != m['customer_id']) {
        return const CustomerTransport();
      }
      return CustomerTransport(receipt: receipt);
    } catch (_) {
      return const CustomerTransport();
    }
  }

  Future<T> _customerRead<T>(
    String caller,
    String rpc,
    Map<String, Object?> body,
    T Function(Object?) parse,
  ) async {
    try {
      final r = await _post(caller, rpc, body);
      if (!_callerStill(caller)) {
        throw const CustomerReadException('session_expired');
      }
      if (r.statusCode >= 400) throw CustomerReadException(_errorCode(r.body));
      return parse(jsonDecode(r.body));
    } on CustomerReadException {
      rethrow;
    } on _CallerRejected catch (e) {
      throw CustomerReadException(e.code);
    } on _OwnerChanged {
      throw const CustomerReadException('session_expired');
    } catch (_) {
      throw const CustomerReadException();
    }
  }

  @override
  Future<CustomerPage> customers({
    required String callerUserId,
    required String query,
    required String sort,
    required String filter,
    required String? cursor,
  }) => _customerRead(
    callerUserId,
    'get_customer_list_v3',
    {
      'p_query': query,
      'p_sort': sort,
      'p_filter': filter,
      'p_limit': 20,
      'p_cursor': cursor,
    },
    (raw) => parseCustomerPage(
      raw,
      requireStatistics: true,
      requireSavedNumbers: true,
    ),
  );
  @override
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  }) => _customerRead(
    callerUserId,
    'get_customer_v3',
    {
      'p_customer_id': id,
      'p_notes_limit': 20,
      'p_notes_cursor': notesCursor,
      'p_history_limit': 20,
      'p_history_cursor': historyCursor,
      'p_links_limit': 20,
      'p_links_cursor': linksCursor,
    },
    (raw) {
      final d = parseCustomerDetail(
        raw,
        requireStatistics: true,
        requireSavedNumbers: true,
      );
      if (d.customer.id != id) throw const FormatException('customer');
      return d;
    },
  );
  @override
  Future<CustomerSection> customerCandidates({
    required String callerUserId,
    required String query,
    required String? cursor,
  }) => _customerRead(
    callerUserId,
    'get_customer_link_candidates_v1',
    {'p_query': query, 'p_limit': 20, 'p_cursor': cursor},
    (raw) => parseCustomerSection(raw, type: 'candidates'),
  );

  @override
  Object? appearanceSession(String userId) {
    try {
      return _callerToken(userId);
    } catch (_) {
      return null;
    }
  }

  Future<AppearanceTransport> _appearanceCommand(
    String callerUserId,
    String shopId,
    String rpc,
    String kind,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (!_callerStill(callerUserId)) {
        return const AppearanceTransport(error: 'discarded');
      }
      if (response.statusCode >= 500) return const AppearanceTransport();
      if (response.statusCode >= 400) {
        return AppearanceTransport(error: _errorCode(response.body));
      }
      final receipt = parseAppearanceReceipt(
        jsonDecode(response.body),
        kind: kind,
      );
      if (receipt.shopId != shopId) {
        return const AppearanceTransport();
      }
      return AppearanceTransport(receipt: receipt);
    } on _OwnerChanged {
      return const AppearanceTransport(error: 'discarded');
    } on _CallerRejected catch (error) {
      return AppearanceTransport(error: error.code);
    } catch (_) {
      return const AppearanceTransport();
    }
  }

  @override
  Future<InvoiceAppearanceSnapshot> readAppearance({
    required String userId,
    required String shopId,
  }) => _appearanceRead(
    userId,
    'get_invoice_appearance_v1',
    const {},
    (raw) => parseInvoiceAppearance(raw, shopId: shopId),
  );

  @override
  Future<InvoiceAppearanceReview> reviewAppearance({
    required String userId,
    required String shopId,
    required Map<String, Object?> payload,
  }) => _appearanceRead(userId, 'review_invoice_appearance_v1', {
    'p_payload': payload,
  }, parseInvoiceAppearanceReview);

  @override
  Future<AppearanceTransport> sendAppearance({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => _appearanceCommand(
    userId,
    shopId,
    'post_invoice_appearance_v1',
    invoiceAppearanceKind,
    body,
  );

  @override
  Future<AppearanceTransport> appearanceStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => _appearanceStatus(
    userId,
    shopId,
    'get_invoice_appearance_status_v1',
    invoiceAppearanceKind,
    body,
  );

  @override
  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final extension = mimeType == 'image/png'
        ? 'png'
        : mimeType == 'image/jpeg'
        ? 'jpg'
        : null;
    final parts = objectName.split('/');
    final sha = parts.length == 2 && extension != null
        ? parts[1].replaceFirst(RegExp('.$extension\$'), '')
        : '';
    if (extension == null ||
        parts.length != 2 ||
        parts[0] != shopId ||
        !isUuid(shopId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        objectName != '$shopId/$sha.$extension' ||
        bytes.isEmpty ||
        bytes.length > 2097152) {
      return const LogoUploadResult(
        LogoUploadDisposition.rejected,
        code: 'logo_rejected',
      );
    }
    try {
      final response = await _storage(
        userId,
        'POST',
        'object/$invoiceLogoBucket/${_encodePath(objectName)}',
        headers: {'Content-Type': mimeType, 'x-upsert': 'false'},
        body: bytes,
      );
      if (!_callerStill(userId)) {
        return const LogoUploadResult(LogoUploadDisposition.unknown);
      }
      if (response.statusCode == 200) {
        return const LogoUploadResult(LogoUploadDisposition.stored);
      }
      if (response.statusCode == 409) {
        return const LogoUploadResult(LogoUploadDisposition.alreadyPresent);
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        return LogoUploadResult(
          LogoUploadDisposition.rejected,
          code: _errorCode(response.body) ?? 'logo_rejected',
        );
      }
      return const LogoUploadResult(LogoUploadDisposition.unknown);
    } on _CallerRejected catch (error) {
      return LogoUploadResult(LogoUploadDisposition.rejected, code: error.code);
    } catch (_) {
      return const LogoUploadResult(LogoUploadDisposition.unknown);
    }
  }

  @override
  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  }) => _appearanceRead(
    userId,
    'confirm_invoice_logo_v1',
    {'p_bytes': base64Bytes},
    (raw) => parseLogoConfirmation(raw, shopId: shopId, sha256: sha256),
  );

  @override
  Future<InvoiceBrandSource> readBrandSource({
    required String userId,
    required String shopId,
    required String operationId,
  }) => _appearanceRead(
    userId,
    'get_invoice_brand_source_v1',
    {'p_operation_id': operationId},
    (raw) =>
        parseInvoiceBrandSource(raw, shopId: shopId, operationId: operationId),
  );

  @override
  Future<AppearanceTransport> sendPresentation({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => _appearanceCommand(
    userId,
    shopId,
    'post_invoice_presentation_v2',
    invoicePresentationKind,
    body,
  );

  @override
  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => _appearanceStatus(
    userId,
    shopId,
    'get_invoice_presentation_status_v1',
    invoicePresentationKind,
    body,
  );

  @override
  Future<InvoicePresentationList> listPresentations({
    required String userId,
    required String shopId,
    required String operationId,
  }) => _appearanceRead(
    userId,
    'get_invoice_presentations_v1',
    {'p_operation_id': operationId},
    (raw) => parseInvoicePresentationList(
      raw,
      shopId: shopId,
      operationId: operationId,
    ),
  );

  @override
  Future<InvoicePresentationCopy> readPresentation({
    required String userId,
    required String shopId,
    required String operationId,
    required int edition,
  }) => _appearanceRead(
    userId,
    'get_invoice_presentation_v1',
    {'p_operation_id': operationId, 'p_edition': edition},
    (raw) => parseInvoicePresentationCopy(
      raw,
      shopId: shopId,
      operationId: operationId,
      edition: edition,
    ),
  );

  Future<AppearanceTransport> _appearanceStatus(
    String callerUserId,
    String shopId,
    String rpc,
    String kind,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (!_callerStill(callerUserId)) {
        return const AppearanceTransport(error: 'discarded');
      }
      if (response.statusCode >= 500) return const AppearanceTransport();
      if (response.statusCode >= 400) {
        return AppearanceTransport(error: _errorCode(response.body));
      }
      final transport = parseAppearanceStatus(
        jsonDecode(response.body),
        kind: kind,
      );
      if (transport.receipt != null && transport.receipt!.shopId != shopId) {
        return const AppearanceTransport();
      }
      return transport;
    } on _OwnerChanged {
      return const AppearanceTransport(error: 'discarded');
    } on _CallerRejected catch (error) {
      return AppearanceTransport(error: error.code);
    } catch (_) {
      return const AppearanceTransport();
    }
  }

  @override
  Object? messageSession(String userId) => appearanceSession(userId);

  Future<T> _messageRead<T>(
    String user,
    String rpc,
    Map<String, Object?> body,
    T Function(Object?) parse,
  ) async {
    try {
      return await _appearanceRead(user, rpc, body, parse);
    } on InvoiceAppearanceException catch (e) {
      throw MessageGatewayException(e.code);
    }
  }

  @override
  Future<MessageProfile> readMessage(String user, String shop) => _messageRead(
    user,
    'get_invoice_message_v1',
    {},
    (raw) => parseMessageProfile(raw, shop),
  );
  @override
  Future<MessageReview> reviewMessage(
    String user,
    String shop,
    Map<String, Object?> payload,
  ) => _messageRead(user, 'review_invoice_message_v1', {
    'p_payload': payload,
  }, parseMessageReview);
  @override
  Future<MessageSource> readMessageSource(
    String user,
    String shop,
    String operation,
  ) => _messageRead(
    user,
    'get_invoice_message_source_v1',
    {'p_operation_id': operation},
    (raw) => parseMessageSource(raw, shop, operation),
  );
  @override
  Future<MessageTransport> sendMessage(
    String user,
    String shop,
    Map<String, Object?> body,
  ) => _messageTransport(user, shop, 'post_invoice_message_v1', body, false);
  @override
  Future<MessageTransport> messageStatus(
    String user,
    String shop,
    Map<String, Object?> body,
  ) => _messageTransport(
    user,
    shop,
    'get_invoice_message_status_v1',
    body,
    true,
  );

  Future<MessageTransport> _messageTransport(
    String user,
    String shop,
    String rpc,
    Map<String, Object?> body,
    bool status,
  ) async {
    try {
      final response = await _post(user, rpc, body);
      if (!_callerStill(user)) {
        return const MessageTransport(error: 'discarded');
      }
      if (response.statusCode >= 500) return const MessageTransport();
      if (response.statusCode >= 400) {
        return MessageTransport(error: _errorCode(response.body));
      }
      final raw = jsonDecode(response.body);
      final result = status
          ? parseMessageStatus(raw)
          : MessageTransport(receipt: parseMessageReceipt(raw));
      if (result.receipt != null && result.receipt!.shop != shop) {
        return const MessageTransport();
      }
      return result;
    } on _OwnerChanged {
      return const MessageTransport(error: 'discarded');
    } on _CallerRejected catch (e) {
      return MessageTransport(error: e.code);
    } catch (_) {
      return const MessageTransport();
    }
  }

  Future<T> _appearanceRead<T>(
    String callerUserId,
    String rpc,
    Map<String, Object?> body,
    T Function(Object?) parse,
  ) async {
    try {
      final response = await _post(callerUserId, rpc, body);
      if (!_callerStill(callerUserId)) {
        throw const InvoiceAppearanceException('session_expired');
      }
      if (response.statusCode >= 400) {
        throw InvoiceAppearanceException(_errorCode(response.body));
      }
      return parse(jsonDecode(response.body));
    } on InvoiceAppearanceException {
      rethrow;
    } on _OwnerChanged {
      throw const InvoiceAppearanceException('session_expired');
    } on _CallerRejected catch (error) {
      throw InvoiceAppearanceException(error.code);
    } on FormatException {
      throw const InvoiceAppearanceException();
    } catch (_) {
      throw const InvoiceAppearanceException();
    }
  }
}

bool _noteObjectName(String name) {
  final parts = name.split('/');
  if (parts.length != 3) return false;
  final dot = parts[2].lastIndexOf('.');
  if (dot <= 0) return false;
  final objectId = parts[2].substring(0, dot);
  final extension = parts[2].substring(dot + 1);
  return isCanonicalNoteId(parts[0]) &&
      isCanonicalNoteId(parts[1]) &&
      isCanonicalNoteId(objectId) &&
      const {'jpg', 'png', 'webp'}.contains(extension) &&
      name == '${parts[0]}/${parts[1]}/$objectId.$extension';
}

String _encodePath(String name) =>
    name.split('/').map(Uri.encodeComponent).join('/');

class _CallerRejected implements Exception {
  const _CallerRejected(this.code);
  final String code;
}

/// The response arrived after the signed-in owner or token changed.
class _OwnerChanged implements Exception {
  const _OwnerChanged();
}

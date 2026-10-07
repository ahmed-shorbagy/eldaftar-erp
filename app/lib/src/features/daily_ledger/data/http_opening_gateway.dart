import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../inventory/application/inventory_contract.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../../inventory/data/inventory_codec.dart';
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

const _errorCodes = <String>{
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
};

class HttpOpeningGateway
    implements
        OpeningGateway,
        FinancialGateway,
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
        LedgerFeedGateway {
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
      'close_day' => 'close_daily_ledger_day',
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

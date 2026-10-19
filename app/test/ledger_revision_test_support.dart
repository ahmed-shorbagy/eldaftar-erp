import 'dart:async';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_date_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_trade_change.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_date_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_trade_change_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'ledger_feed_merge_test.dart' show pageJson, line;

const revisionShop = '22222222-2222-4222-8222-222222222222';
const revisionDay = '33333333-3333-4333-8333-333333333333';
const revisionOperation = '44444444-4444-4444-8444-444444444444';
const revisionKey = '55555555-5555-4555-8555-555555555555';
const revisionUser = 'owner-a';

Map<String, Object?> sourceTrade({
  String kind = 'sale',
  String milligrams = '1255',
}) => {
  'version': 1,
  'kind': kind,
  'total_piastres': '10000',
  'tenders': [
    {'method': 'cash', 'piastres': '10000'},
  ],
  'items': [
    {
      'category': 'worked_jewelry',
      'karat': 21,
      'milligrams': milligrams,
      'count': '1',
      'item_name': 'خاتم',
      'line_price_piastres': null,
    },
  ],
  'description': 'وصف محفوظ',
  'customer_name': 'عميل تجريبي',
  'customer_phone': '01011111111',
  'note': 'ملاحظة محفوظة',
};
Map<String, Object?> reviewJson({
  String action = 'delete',
  String kind = 'sale',
}) => {
  'version': 1,
  'shop_id': revisionShop,
  'operation_id': revisionOperation,
  'action': action,
  'expected_day_id': revisionDay,
  'expected_day_version': 7,
  'source_sha256': 'a' * 64,
  'review_token': 'b' * 64,
  'source': {'kind': kind, 'payload': sourceTrade(kind: kind)},
  'effects': {
    'cash': [
      {'method': 'cash', 'delta_piastres': kind == 'sale' ? '-10000' : '10000'},
    ],
    'stock': [
      {
        'category': 'worked_jewelry',
        'karat': 21,
        'delta_milligrams': kind == 'sale' ? '1255' : '-1255',
        'delta_count': kind == 'sale' ? '1' : '-1',
      },
    ],
    'scrap': <Object?>[],
    'payable_delta_piastres': '0',
  },
};
LedgerTradeChangeReview changeReview({String action = 'delete'}) =>
    parseTradeChangeReview(
      reviewJson(action: action),
      shopId: revisionShop,
      operationId: revisionOperation,
      action: action,
    );

Map<String, Object?> dateJson({
  String date = '2026-10-18',
  List<LedgerFeedLine>? rows,
  bool more = false,
  String? before,
}) => {
  'read_model_version': 1,
  'shop_id': revisionShop,
  'business_date': date,
  'server_date': '2026-10-19',
  'day_ids': rows?.isEmpty == true ? <String>[] : [revisionDay],
  'day_summary': {
    'sale_piastres': rows?.isEmpty == true ? '0' : '10000',
    'purchase_piastres': '0',
    'expense_piastres': '0',
    'sale_count': rows?.isEmpty == true ? 0 : 1,
    'purchase_count': 0,
    'expense_count': 0,
    'gold_by_bucket': <Object?>[],
  },
  'feed_page': {
    ...pageJson(
      direction: 'desc',
      limit: 100,
      items: rows ?? [line(2, kind: 'sale')],
      hasMore: more,
      before: before,
    ),
    'day_id': null,
  },
};

class RevisionGateway extends FakeFinancialGateway
    implements LedgerTradeChangeGateway, LedgerDateGateway {
  final posts = <PendingFinancialCommand>[];
  final reviews = <Map<String, Object?>>[];
  final dates = <String?>[];
  final cursors = <String?>[];
  bool pendingAtPost = false;
  Map<String, Object?> operationPayload = sourceTrade();
  Map<String, Object?>? tradeChange;
  LedgerDateSnapshot dateValue = parseLedgerDate(dateJson(), revisionShop);
  Completer<LedgerDateSnapshot>? heldDate;
  Completer<FinancialCommandResult>? heldPost;
  String? reviewFailure;
  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {
    'kind': 'sale',
    'shop_id': revisionShop,
    'shop_sequence': '2',
    'payload': operationPayload,
    if (tradeChange != null) 'trade_change': tradeChange,
  };
  @override
  Future<LedgerTradeChangeReview> reviewTradeChange({
    required String userId,
    required String shopId,
    required String operationId,
    required String action,
    Map<String, Object?>? replacement,
  }) async {
    reviews.add({'action': action, 'replacement': replacement});
    if (reviewFailure != null) throw StateError(reviewFailure!);
    return changeReview(action: action);
  }

  @override
  Future<FinancialCommandResult> postTradeChange({
    required String userId,
    required PendingFinancialCommand command,
  }) async {
    pendingAtPost =
        (await const PendingFinancialCommands().read(
          userId,
          revisionShop,
        ))?.key ==
        command.key;
    posts.add(command);
    return heldPost?.future ?? result;
  }

  @override
  Future<LedgerDateSnapshot> readLedgerDate({
    required String userId,
    required String shopId,
    String? businessDate,
    String? beforeSequence,
  }) async {
    dates.add(businessDate);
    cursors.add(beforeSequence);
    return heldDate?.future ?? dateValue;
  }
}

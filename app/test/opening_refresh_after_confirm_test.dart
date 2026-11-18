// Regression for the owner report of 2026-11-17: after confirming zero opening
// balances the ledger stayed on «تعذر تحديث الدفتر بعد التأكيد».
//
// The scripted ledger below has the shape `get_daily_ledger_home_v2` returned
// for a newly opened shop on the development project on 2026-11-18. That read
// names the opening row `opening_balances`; only the legacy `get_daily_ledger`
// names it `opening_balances_confirmed`.
import 'package:eldafttar/src/features/daily_ledger/application/opening_flow.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_ledger_flow_test.dart'
    show MemoryStore, ScriptGateway, shopId, userId, zeroDraft;

const _day = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _operation = '33333333-3333-4333-8333-333333333333';
const _key = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> _openingRow() => {
  'kind': 'opening_balances',
  'karat': null,
  'has_note': false,
  'label_ar': 'رصيد افتتاحي',
  'is_return': false,
  'party_name': null,
  'occurred_at': '2026-11-17T15:49:58.41185+00:00',
  'party_phone': null,
  'piece_count': null,
  'item_summary': null,
  'operation_id': _operation,
  'total_pounds': null,
  'weight_grams': null,
  'is_daily_note': false,
  'payment_label': null,
  'shop_sequence': '1',
  'occurred_at_shop': '2026-11-17T17:49:58',
  'occurred_at_cairo': '2026-11-17T17:49:58',
  'actor_display_name': 'منى',
};

/// `get_daily_ledger_home_v2` of a shop whose only operation is the opening.
Map<String, Object?> freshShopHome({bool dayClosed = false}) => {
  'read_model_version': 3,
  'state': 'confirmed',
  'entitlement_status': 'active',
  'can_confirm': false,
  'business_day': {
    'id': _day,
    'opened_at': '2026-11-17T15:49:58.41185+00:00',
    'business_date': '2026-11-17',
  },
  'cash': [
    for (final method in const [
      ('cash', 'نقدي'),
      ('instant_transfer', 'انستا'),
      ('wallet', 'محفظة'),
      ('card', 'فيزا'),
    ])
      {
        'method': method.$1,
        'pounds': '0.00',
        'archived': false,
        'label_ar': method.$2,
        'piastres': '0',
      },
  ],
  'stock': <Object?>[],
  'scrap': <Object?>[],
  // After a close the home feed is empty until a new day is opened.
  'feed': [if (!dayClosed) _openingRow()],
  'feed_page': {
    'limit': 100,
    'has_more': false,
    'direction': 'desc',
    'server_sequence': '1',
    'snapshot_sequence': '1',
    'next_before_sequence': null,
  },
  'day_summary': {
    'sale_count': 0,
    'repair_count': 0,
    'expense_count': 0,
    'sale_piastres': '0',
    'gold_by_bucket': <Object?>[],
    'purchase_count': 0,
    'repair_piastres': '0',
    'expense_piastres': '0',
    'purchase_piastres': '0',
  },
  'journal_context': {
    'day_ids': dayClosed ? <String>[] : [_day],
    'note_count': 0,
    'server_now': '2026-11-17T15:50:00.000000Z',
    'return_count': 0,
    'business_date': '2026-11-17',
    'next_midnight_at': '2026-11-17T22:00:00.000000Z',
  },
  'day_reset': dayClosed,
  'last_closed_business_date': dayClosed ? '2026-11-17' : null,
  'trade_change_sequence': '0',
};

void main() {
  test('the home read names the opening row opening_balances', () {
    final ledger = parseDailyLedger(freshShopHome());
    expect(ledger.isConfirmed, isTrue);
    expect(ledger.feed.single.kind, 'opening_balances');
    expect(ledger.feed.single.operationId, _operation);
  });

  test(
    'confirming zero balances opens the ledger from the home read',
    () async {
      final store = MemoryStore();
      final gateway =
          ScriptGateway(ledgerView: parseDailyLedger(freshShopHome()))
            ..confirmResult = const ConfirmCommitted(
              operationId: _operation,
              businessDayId: _day,
              businessDate: '2026-11-17',
              replayed: false,
            );
      final flow = OpeningFlowCoordinator(
        gateway: gateway,
        store: store,
        newKey: () => _key,
      );

      final result = await flow.confirm(
        userId: userId,
        shopId: shopId,
        draft: zeroDraft(),
        writesAllowed: true,
      );

      expect(result, isA<OpeningReady>());
      expect(gateway.confirmCalls, 1);
      expect(store.saved, isNull);
      expect(flow.hasUnresolvedAttempt, isFalse);
    },
  );

  test(
    'a device stuck on the acknowledged opening recovers on next launch',
    () async {
      // What the affected build left behind: the server acknowledged the
      // opening, the read was refused, and the attempt stayed stored.
      final store = MemoryStore()
        ..saved = PendingOpening(
          idempotencyKey: _key,
          payload: zeroDraft().toCanonicalJson(),
          disposition: PendingDisposition.acknowledged,
          operationId: _operation,
        );
      final gateway = ScriptGateway(
        ledgerView: parseDailyLedger(freshShopHome()),
      );
      final flow = OpeningFlowCoordinator(gateway: gateway, store: store);

      final result = await flow.open(
        userId: userId,
        shopId: shopId,
        writesAllowed: true,
      );

      expect(result, isA<OpeningReady>());
      expect(
        gateway.confirmCalls,
        0,
        reason: 'the opening is not posted twice',
      );
      expect(store.saved, isNull);
    },
  );

  test(
    'the stuck device also recovers after the opening day was closed',
    () async {
      final store = MemoryStore()
        ..saved = PendingOpening(
          idempotencyKey: _key,
          payload: zeroDraft().toCanonicalJson(),
          disposition: PendingDisposition.acknowledged,
          operationId: _operation,
        );
      final closed = parseDailyLedger(freshShopHome(dayClosed: true));
      expect(closed.feed, isEmpty);
      final gateway = ScriptGateway(ledgerView: closed);
      final flow = OpeningFlowCoordinator(gateway: gateway, store: store);

      final result = await flow.open(
        userId: userId,
        shopId: shopId,
        writesAllowed: true,
      );

      expect(result, isA<OpeningReady>());
      expect(store.saved, isNull);
    },
  );

  test('a failed read after the confirm resolves on retry', () async {
    final store = MemoryStore();
    final gateway = ScriptGateway()
      ..ledgerThrows = true
      ..confirmResult = const ConfirmCommitted(
        operationId: _operation,
        businessDayId: _day,
        businessDate: '2026-11-17',
        replayed: false,
      );
    final flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: () => _key,
    );

    final first = await flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zeroDraft(),
      writesAllowed: true,
    );
    expect(first, isA<OpeningRefreshFailed>());
    expect(store.saved?.disposition, PendingDisposition.acknowledged);

    gateway
      ..ledgerThrows = false
      ..ledgerView = parseDailyLedger(freshShopHome());
    final retry = await flow.refresh(
      userId: userId,
      shopId: shopId,
      writesAllowed: true,
    );

    expect(retry, isA<OpeningReady>());
    expect(gateway.confirmCalls, 1, reason: 'the retry only reads');
    expect(store.saved, isNull);
  });
}

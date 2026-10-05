import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const user = 'owner-a';

LedgerFeedLine line(int sequence, {String kind = 'daily_note'}) {
  final id =
      '${sequence.toString().padLeft(8, '0')}-0000-4000-8000-000000000000';
  final label = switch (kind) {
    'sale' => 'بيع',
    'sale_return' => 'مرتجع بيع',
    _ => 'ملاحظة يومية',
  };
  return LedgerFeedLine(
    kind: kind,
    labelAr: label,
    operationId: id,
    actorDisplayName: 'منى',
    occurredAt: '2026-01-01T22:30:00Z',
    occurredAtCairo: '2026-01-02T00:30:00',
    occurredAtShop: '2026-01-02T00:30:00',
    shopSequence: '$sequence',
    isDailyNote: kind == 'daily_note',
    isReturn: kind == 'sale_return',
  );
}

Map<String, Object?> pageJson({
  required String direction,
  required int limit,
  required List<LedgerFeedLine> items,
  String? before,
  String? after,
  String shopId = shop,
  bool hasMore = false,
}) => {
  'shop_id': shopId,
  'day_id': day,
  'direction': direction,
  'limit': limit,
  'has_more': hasMore,
  'server_sequence': '250',
  'snapshot_sequence': '250',
  'next_before_sequence': before,
  'next_after_sequence': after,
  'items': [
    for (final item in items)
      {
        'kind': item.kind,
        'label_ar': item.labelAr,
        'operation_id': item.operationId,
        'actor_display_name': item.actorDisplayName,
        'occurred_at': item.occurredAt,
        'occurred_at_cairo': item.occurredAtCairo,
        'occurred_at_shop': item.occurredAtShop,
        'has_note': item.hasNote,
        'is_daily_note': item.isDailyNote,
        'is_return': item.isReturn,
        'shop_sequence': item.shopSequence,
      },
  ],
};

void main() {
  test(
    'business summaries preserve decimal precision and reject malformed fields',
    () {
      final data = pageJson(
        direction: 'desc',
        limit: 1,
        items: [line(1, kind: 'sale')],
      );
      final row = (data['items'] as List).single as Map<String, Object?>;
      row.addAll({
        'party_name': 'عميل تجريبي',
        'total_pounds': '90071992547409.93',
        'weight_grams': '1.830',
        'karat': 21,
        'payment_label': 'كاش',
      });
      final page = parseLedgerOperationPage(data, expectedShopId: shop);
      expect(page.items.single.totalPounds, '90071992547409.93');
      expect(page.items.single.weightGrams, '1.830');
      expect(page.items.single.partyName, 'عميل تجريبي');
      for (final field in {
        'total_pounds': 1.2,
        'weight_grams': '1.83',
        'karat': 23,
        'payment_label': 'bad\nlabel',
      }.entries) {
        final previous = row[field.key];
        row[field.key] = field.value;
        expect(
          () => parseLedgerOperationPage(data, expectedShopId: shop),
          throwsFormatException,
        );
        row[field.key] = previous;
      }
    },
  );
  test('merges more than 200 lines without duplicates', () {
    final first = [for (var n = 250; n >= 151; n--) line(n)];
    final second = [for (var n = 150; n >= 51; n--) line(n)];
    final third = [for (var n = 50; n >= 1; n--) line(n)];
    var state = LedgerActivityState.empty;
    state = mergeLedgerPage(
      current: state,
      userId: user,
      shopId: shop,
      dayId: day,
      incoming: first,
      serverSequence: '250',
      direction: 'desc',
      hasMore: true,
      nextCursor: '151',
    );
    state = mergeLedgerPage(
      current: state,
      userId: user,
      shopId: shop,
      dayId: day,
      incoming: second,
      serverSequence: '250',
      direction: 'desc',
      hasMore: true,
      nextCursor: '51',
    );
    state = mergeLedgerPage(
      current: state,
      userId: user,
      shopId: shop,
      dayId: day,
      incoming: third,
      serverSequence: '250',
      direction: 'desc',
      hasMore: false,
    );
    state = mergeLedgerPage(
      current: state,
      userId: user,
      shopId: shop,
      dayId: day,
      incoming: first,
      serverSequence: '250',
      direction: 'desc',
      hasMore: true,
      nextCursor: '151',
    );
    expect(state.lines, hasLength(250));
    expect(state.lines.map((item) => item.operationId).toSet(), hasLength(250));
    expect(state.lines.first.shopSequence, '250');
    expect(state.lines.last.shopSequence, '1');
    expect(state.hasOlder, isFalse);
  });

  test(
    'before and after pages stay disjoint and ordered responses do not drop rows',
    () {
      final older = [for (var n = 80; n >= 1; n--) line(n)];
      final newer = [for (var n = 180; n >= 101; n--) line(n)];
      expect(feedIdsDisjoint(older, newer), isTrue);
      var state = mergeLedgerPage(
        current: LedgerActivityState.empty,
        userId: user,
        shopId: shop,
        dayId: day,
        incoming: newer,
        serverSequence: '180',
        direction: 'asc',
        hasMore: false,
      );
      state = mergeLedgerPage(
        current: state,
        userId: user,
        shopId: shop,
        dayId: day,
        incoming: older,
        serverSequence: '90',
        direction: 'desc',
        hasMore: false,
      );
      expect(state.lines, hasLength(160));
      expect(state.serverSequence, '180');
      final stale = mergeLedgerPage(
        current: state,
        userId: user,
        shopId: shop,
        dayId: day,
        incoming: newer,
        serverSequence: '100',
        direction: 'desc',
        hasMore: false,
      );
      expect(identical(stale, state), isTrue);
      final replaced = mergeLedgerPage(
        current: state,
        userId: 'owner-b',
        shopId: shop,
        dayId: day,
        incoming: [line(7)],
        serverSequence: '7',
        direction: 'desc',
        hasMore: false,
      );
      expect(replaced.lines, hasLength(1));
      expect(replaced.userId, 'owner-b');
    },
  );

  test(
    'a restarted controller adopts the summary and keeps the older cursor',
    () {
      final summary = DailyLedgerView(
        state: 'confirmed',
        entitlementStatus: 'active',
        canConfirm: false,
        businessDay: const LedgerBusinessDay(
          id: day,
          businessDate: '2026-01-02',
          openedAt: '2026-01-01T22:30:00Z',
        ),
        cash: const [],
        stock: const [],
        scrap: const [],
        feed: [line(250), line(249)],
        feedCursor: const LedgerFeedCursor(
          limit: 100,
          hasMore: true,
          direction: 'desc',
          serverSequence: '250',
          snapshotSequence: '250',
          nextBeforeSequence: '249',
        ),
      );
      final first = LedgerActivityController()
        ..adoptSummary(userId: user, shopId: shop, ledger: summary);
      first.state = mergeLedgerPage(
        current: first.state,
        userId: user,
        shopId: shop,
        dayId: day,
        incoming: [line(10)],
        serverSequence: '250',
        direction: 'desc',
        hasMore: true,
        nextCursor: '9',
      );
      final restarted = LedgerActivityController()
        ..state = first.state
        ..adoptSummary(userId: user, shopId: shop, ledger: summary);
      expect(restarted.state.lines.map((item) => item.shopSequence), [
        '250',
        '249',
        '10',
      ]);
      expect(restarted.state.hasOlder, isTrue);
      expect(restarted.state.olderCursor, '9');
      expect(
        displayedShopTime(
          occurredAtUtc: '2026-01-01T22:30:00Z',
          occurredAtShop: '2026-01-02T00:30:00',
        ),
        '2026-01-02T00:30:00',
      );
    },
  );

  test('rejects invalid pages, overflow, cross-shop, and both cursors', () {
    expect(
      () => parseLedgerOperationPage(
        pageJson(direction: 'desc', limit: 0, items: const []),
        expectedShopId: shop,
      ),
      throwsFormatException,
    );
    expect(
      () => parseLedgerOperationPage(
        pageJson(direction: 'desc', limit: 101, items: [line(1)]),
        expectedShopId: shop,
      ),
      throwsFormatException,
    );
    expect(
      () => parseLedgerOperationPage(
        pageJson(
          direction: 'desc',
          limit: 1,
          items: [line(1)],
          shopId: '99999999-9999-4999-8999-999999999999',
        ),
        expectedShopId: shop,
      ),
      throwsFormatException,
    );
    final both = pageJson(direction: 'desc', limit: 1, items: [line(1)]);
    both['next_before_sequence'] = '1';
    both['next_after_sequence'] = '2';
    both['has_more'] = true;
    expect(
      () => parseLedgerOperationPage(both, expectedShopId: shop),
      throwsFormatException,
    );
    final overflow = pageJson(direction: 'desc', limit: 1, items: [line(1)]);
    (overflow['items'] as List).single['shop_sequence'] = '9223372036854775808';
    expect(
      () => parseLedgerOperationPage(overflow, expectedShopId: shop),
      throwsFormatException,
    );
    final numeric = pageJson(direction: 'desc', limit: 1, items: [line(1)]);
    (numeric['items'] as List).single['shop_sequence'] = 12;
    expect(
      () => parseLedgerOperationPage(numeric, expectedShopId: shop),
      throwsFormatException,
    );
  });

  test('a summary above the held head does not skip 520 unseen rows', () async {
    final head = [
      for (var sequence = 100; sequence >= 51; sequence--) line(sequence),
    ];
    final held = mergeLedgerPage(
      current: LedgerActivityState.empty,
      userId: user,
      shopId: shop,
      dayId: day,
      incoming: head,
      serverSequence: '100',
      direction: 'desc',
      hasMore: true,
      nextCursor: '50',
    );
    expect(held.catchUpAnchor, '100');
    expect(held.olderCursor, '50');
    final summary = DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: 'active',
      canConfirm: false,
      businessDay: const LedgerBusinessDay(
        id: day,
        businessDate: '2026-01-02',
        openedAt: '2026-01-01T22:30:00Z',
      ),
      cash: const [],
      stock: const [],
      scrap: const [],
      feed: [
        for (var sequence = 720; sequence >= 621; sequence--) line(sequence),
      ],
      feedCursor: const LedgerFeedCursor(
        limit: 100,
        hasMore: true,
        direction: 'desc',
        serverSequence: '720',
        snapshotSequence: '720',
        nextBeforeSequence: '621',
      ),
    );
    final controller = LedgerActivityController()..state = held;
    controller.adoptSummary(userId: user, shopId: shop, ledger: summary);
    final sequences = controller.state.lines
        .map((item) => item.shopSequence)
        .whereType<String>()
        .toSet();
    final missing = [
      for (var sequence = 101; sequence <= 620; sequence++) '$sequence',
    ].where((sequence) => !sequences.contains(sequence));
    expect(missing, hasLength(520));
    expect(controller.state.olderCursor, '50');
    expect(controller.state.catchUpAnchor, '100');
    expect(controller.state.highestSequence, '720');
    final feed = ScriptFeed()
      ..next = LedgerOperationPage(
        shopId: shop,
        dayId: day,
        direction: 'asc',
        limit: 100,
        hasMore: true,
        serverSequence: '720',
        snapshotSequence: '720',
        nextAfterSequence: '200',
        items: [
          for (var sequence = 101; sequence <= 200; sequence++) line(sequence),
        ],
      );
    await controller.catchUp(gateway: feed, userId: user, maxPages: 1);
    expect(feed.requests.single.after, '100');
    expect(controller.state.olderCursor, '50');
    expect(
      controller.state.lines.any((item) => item.shopSequence == '101'),
      isTrue,
    );
    expect(
      controller.state.lines.any((item) => item.shopSequence == '50'),
      isFalse,
    );
  });

  test(
    'loadOlder drops a late failure and does not clear the next busy flag',
    () async {
      final feed = ScriptFeed();
      final first = Completer<LedgerOperationPage>();
      feed.gate = first;
      final controller = LedgerActivityController()..state = _held();
      final older = controller.loadOlder(gateway: feed, userId: user);
      expect(controller.busy, isTrue);
      controller.reset();
      expect(controller.busy, isFalse);
      final second = Completer<LedgerOperationPage>();
      feed.gate = second;
      controller.state = _held(owner: 'owner-b');
      final newer = controller.loadOlder(gateway: feed, userId: 'owner-b');
      expect(controller.busy, isTrue);
      first.completeError(StateError('stale'));
      await older;
      expect(controller.busy, isTrue);
      expect(controller.state.userId, 'owner-b');
      second.complete(
        LedgerOperationPage(
          shopId: shop,
          dayId: day,
          direction: 'desc',
          limit: 100,
          hasMore: false,
          serverSequence: '100',
          snapshotSequence: '100',
          items: [line(40)],
        ),
      );
      await newer;
      expect(controller.busy, isFalse);
      expect(controller.state.userId, 'owner-b');
      expect(
        controller.state.lines.map((item) => item.shopSequence),
        containsAll(['100', '40']),
      );
    },
  );

  test(
    'catchUp drops a late failure and a page for another shop or day',
    () async {
      final feed = ScriptFeed();
      final first = Completer<LedgerOperationPage>();
      feed.gate = first;
      final controller = LedgerActivityController()..state = _held();
      final pending = controller.catchUp(gateway: feed, userId: user);
      expect(feed.requests.single.after, '100');
      controller.reset();
      final second = Completer<LedgerOperationPage>();
      feed.gate = second;
      controller.state = _held(owner: 'owner-b');
      final follow = controller.catchUp(gateway: feed, userId: 'owner-b');
      expect(controller.busy, isTrue);
      first.completeError(StateError('stale'));
      expect(await pending, 0);
      expect(controller.busy, isTrue);
      expect(controller.state.userId, 'owner-b');
      second.complete(
        LedgerOperationPage(
          shopId: '99999999-9999-4999-8999-999999999999',
          dayId: day,
          direction: 'asc',
          limit: 100,
          hasMore: false,
          serverSequence: '720',
          snapshotSequence: '720',
          items: [line(720)],
        ),
      );
      expect(await follow, 0);
      expect(controller.busy, isFalse);
      expect(controller.state.lines, hasLength(2));
      expect(feed.requests[1].after, '100');
      feed.next = LedgerOperationPage(
        shopId: shop,
        dayId: '77777777-7777-4777-8777-777777777777',
        direction: 'desc',
        limit: 100,
        hasMore: false,
        serverSequence: '100',
        snapshotSequence: '100',
        items: [line(3)],
      );
      await controller.loadOlder(gateway: feed, userId: 'owner-b');
      expect(controller.state.olderCursor, '50');
      expect(
        controller.state.lines.any((item) => item.shopSequence == '3'),
        isFalse,
      );
    },
  );
}

LedgerActivityState _held({String owner = user}) => LedgerActivityState(
  userId: owner,
  shopId: shop,
  dayId: day,
  lines: [line(100), line(51)],
  serverSequence: '100',
  hasOlder: true,
  olderCursor: '50',
  catchUpAnchor: '100',
);

class ScriptFeed implements LedgerFeedGateway {
  final requests = <({String? before, String? after})>[];
  Completer<LedgerOperationPage>? gate;
  LedgerOperationPage? next;

  @override
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  }) async {
    requests.add((before: beforeSequence, after: afterSequence));
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    final page = next;
    if (page == null) throw StateError('missing page');
    return page;
  }
}

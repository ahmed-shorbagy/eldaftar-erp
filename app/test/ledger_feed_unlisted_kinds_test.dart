// Found on 2026-11-18: after «إضافة مخزون» the daily ledger showed «تعذر إتمام
// العملية». The open day's feed carries every operation of the day, and the
// server gives no ledger label to stock operations from «الجرد الفوري», trader
// receipts, or the reversal an edit or delete leaves behind. The parser threw
// on the null label. Such rows are now left out of the ledger.

import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_feed_merge_test.dart' show line, pageJson, shop;
import 'legacy_read_shapes_test.dart' show v2Home;

/// Every `financial_operations.kind` for which
/// `private.ledger_operation_label` returned null on development.
const unlistedKinds = [
  'inventory_addition',
  'inventory_removal',
  'inventory_correction',
  'inventory_conversion',
  'inventory_receipt',
  'inventory_recognition',
  'ownership_transfer',
  'receipt_manual_allocation',
  'expense_reversal',
  'customer_return_reversal',
];

/// The row development returned for a stock addition, with its ids replaced.
Map<String, Object?> additionRow() => {
  'kind': 'inventory_addition',
  'karat': null,
  'has_note': false,
  'label_ar': null,
  'is_return': false,
  'party_name': null,
  'occurred_at': '2026-11-18T08:39:04.838647+00:00',
  'party_phone': null,
  'piece_count': null,
  'item_summary': null,
  'operation_id': 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'total_pounds': null,
  'weight_grams': null,
  'is_daily_note': false,
  'payment_label': null,
  'shop_sequence': '10',
  'occurred_at_shop': '2026-11-18T10:39:04',
  'occurred_at_cairo': '2026-11-18T10:39:04',
  'actor_display_name': 'صاحب المحل',
};

Map<String, Object?> homeWith(void Function(List<Object?> feed) edit) {
  final body = jsonDecode(jsonEncode(v2Home())) as Map<String, Object?>;
  edit(body['feed']! as List<Object?>);
  return body;
}

void main() {
  test('a stock addition in the open day no longer breaks the ledger', () {
    final ledger = parseDailyLedger(
      homeWith((feed) => feed.insert(0, additionRow())),
    );
    expect(ledger.feed, hasLength(3));
    expect(ledger.feed.map((row) => row.kind), isNot(contains(isNull)));
    expect(
      ledger.feed.map((row) => row.kind),
      isNot(contains('inventory_addition')),
    );
    expect(ledger.feed.first.shopSequence, '9');
  });

  for (final kind in unlistedKinds) {
    test('an unlabelled $kind row is left out and the rest is kept', () {
      final ledger = parseDailyLedger(
        homeWith((feed) {
          final row = feed[2]! as Map;
          row['kind'] = kind;
          row['label_ar'] = null;
        }),
      );
      expect(ledger.feed.map((row) => row.shopSequence), ['9', '8']);
    });
  }

  test('a day whose only rows are unlisted reads as an empty ledger', () {
    final ledger = parseDailyLedger(
      homeWith((feed) {
        for (final row in feed.cast<Map>()) {
          row['kind'] = 'inventory_addition';
          row['label_ar'] = null;
        }
      }),
    );
    expect(ledger.feed, isEmpty);
    final page = parseLedgerOperationPage(
      pageJson(direction: 'desc', limit: 5, items: [])
        ..['items'] = [additionRow()],
      expectedShopId: shop,
    );
    expect(page.items, isEmpty);
  });

  test('the paged read leaves the same rows out and keeps its cursor', () {
    final json = pageJson(
      direction: 'desc',
      limit: 5,
      items: [
        line(12, kind: 'sale'),
        line(11),
      ],
      hasMore: true,
      before: '10',
    );
    (json['items']! as List).insert(1, additionRow());
    final page = parseLedgerOperationPage(json, expectedShopId: shop);
    expect(page.items.map((row) => row.shopSequence), ['12', '11']);
    expect(page.hasMore, isTrue);
    expect(page.nextBeforeSequence, '10');
    expect(page.serverSequence, '250');
  });

  test('a ledger kind that arrives without its label is still refused', () {
    expect(
      () => parseDailyLedger(
        homeWith((feed) => (feed[0]! as Map)['label_ar'] = null),
      ),
      throwsFormatException,
    );
  });

  test('an unknown kind that carries a label is still refused', () {
    expect(
      () => parseDailyLedger(
        homeWith((feed) {
          final row = feed[0]! as Map;
          row['kind'] = 'inventory_addition';
          row['label_ar'] = 'إضافة مخزون';
        }),
      ),
      throwsFormatException,
    );
  });

  test('a malformed row is still refused, labelled or not', () {
    expect(
      () => parseDailyLedger(homeWith((feed) => feed.insert(0, 'not a row'))),
      throwsFormatException,
    );
    expect(
      () => parseDailyLedger(
        homeWith((feed) => feed.insert(0, {'label_ar': null, 'kind': 7})),
      ),
      throwsFormatException,
    );
  });
}

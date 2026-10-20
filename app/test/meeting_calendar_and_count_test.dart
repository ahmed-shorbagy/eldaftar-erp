import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/closing_count_observation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_ledger_http_test.dart' show confirmedBody, dayId;

Map<String, Object?> calendarBody() => {
  ...confirmedBody(),
  'read_model_version': 3,
  'day_summary': {
    'sale_piastres': '0',
    'purchase_piastres': '0',
    'expense_piastres': '0',
    'sale_count': 0,
    'purchase_count': 0,
    'expense_count': 0,
    'gold_by_bucket': <Object?>[],
  },
  'feed': <Object?>[],
  'journal_context': {
    'business_date': '2026-10-20',
    'day_ids': <String>[],
    'server_now': '2026-10-19T21:00:00Z',
    'next_midnight_at': '2026-10-20T21:00:00Z',
    'return_count': 0,
    'note_count': 0,
  },
};
const book = <String, Object?>{
  'cash': {'cash': '100'},
  'scrap': <Object?>[],
  'stock': [
    {
      'category': 'worked_jewelry',
      'karat': 21,
      'count': '5',
      'milligrams': '5000',
    },
  ],
};
Map<String, Object?> observations({String count = '3', Object? weight}) => {
  'version': 2,
  'cash': book['cash'],
  'scrap': book['scrap'],
  'stock': [
    {
      'item_name': 'خاتم',
      'category': 'worked_jewelry',
      'karat': 21,
      'count': count,
      'milligrams': weight,
    },
    {
      'item_name': 'حلق',
      'category': 'worked_jewelry',
      'karat': 21,
      'count': '2',
      'milligrams': '1000',
    },
  ],
};
void main() {
  test(
    'empty calendar journal preserves yesterday financial day and exact current balances',
    () {
      final view = parseDailyLedger(calendarBody());
      expect(view.businessDay?.id, dayId);
      expect(view.businessDay?.businessDate, '2026-09-26');
      expect(view.journalContext?.businessDate, '2026-10-20');
      expect(view.journalContext?.untilNextMidnight, const Duration(days: 1));
      expect(view.cash.first.piastres, '1000000');
      expect(view.feed, isEmpty);
      expect(view.daySummary?.saleCount, 0);
    },
  );
  test(
    'calendar contract rejects invented activity, invalid dates, clocks and counters',
    () {
      for (final edit in <String, Object?>{
        'business_date': '2026-02-30',
        'server_now': 'not a timestamp',
        'next_midnight_at': '2026-10-19T20:59:59Z',
        'return_count': -1,
        'note_count': 1,
        'day_ids': ['invalid'],
      }.entries) {
        final body = calendarBody();
        (body['journal_context'] as Map)[edit.key] = edit.value;
        expect(
          () => parseDailyLedger(body),
          throwsFormatException,
          reason: edit.key,
        );
      }
    },
  );
  test(
    'named physical counts preserve null weights and compare measured totals exactly',
    () {
      final unmeasured = observations();
      expect(closingObservationsMatch(unmeasured, book), isTrue);
      expect(
        ((unmeasured['stock'] as List).first as Map)['milligrams'],
        isNull,
      );
      expect(
        closingObservationsMatch(observations(weight: '4000'), book),
        isTrue,
      );
      expect(
        closingObservationsMatch(observations(weight: '3999'), book),
        isFalse,
      );
      expect(
        closingObservationsMatch(observations(weight: '5001'), book),
        isFalse,
      );
      expect(closingObservationsMatch(observations(count: '4'), book), isFalse);
      expect(
        closingObservationsMatch(observations(count: '3.0'), book),
        isFalse,
      );
      expect(
        closingObservationsMatch(
          observations(count: '9223372036854775808'),
          book,
        ),
        isFalse,
      );
      final duplicate = observations();
      ((duplicate['stock'] as List)[1] as Map)['item_name'] = 'خاتم';
      expect(closingObservationsMatch(duplicate, book), isFalse);
    },
  );
}

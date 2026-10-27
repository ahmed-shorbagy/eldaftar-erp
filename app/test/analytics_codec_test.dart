import 'package:eldafttar/src/features/analytics/data/analytics_codec.dart';
import 'package:eldafttar/src/features/analytics/domain/period_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _summary() => {
  for (final key in const [
    'sales',
    'sale_returns',
    'net_sales',
    'purchases',
    'purchase_returns',
    'net_purchases',
    'expenses',
    'net_cash',
    'opening_cash',
    'sale_count',
    'purchase_count',
    'expense_count',
    'return_count',
    'operation_count',
    'audit_row_count',
  ])
    key: '0',
};

void main() {
  test('parses owner month analytics with actors', () {
    final report = parsePeriodAnalytics({
      'version': 1,
      'shop_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'shop_name': 'متجر',
      'time_zone': 'Africa/Cairo',
      'period': 'month',
      'anchor_date': '2026-10-15',
      'start_date': '2026-10-01',
      'end_date': '2026-10-31',
      'contains_open_day': false,
      'is_owner': true,
      'summary': _summary(),
      'gold': [
        for (final k in [14, 18, 21, 22, 24])
          {'karat': k, 'sold': '0', 'bought': '0'},
      ],
      'actors': [
        {
          'actor_user_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'display_name': 'أحمد',
          'role': 'employee',
          'gold': [
            {'karat': 21, 'sold': '1000', 'bought': '0'},
          ],
          'sold_total': '1000',
          'bought_total': '0',
        },
      ],
      'day_count': 3,
      'fingerprint': 'a' * 64,
      'server_date': '2026-10-27',
      'first_business_date': '2026-09-01',
      'last_selectable_date': '2026-10-27',
      'generated_at_shop': '2026-10-27 12:00:00',
      'generated_at_utc': '2026-10-27T09:00:00Z',
    });
    expect(report.periodKind, AnalyticsPeriod.month);
    expect(report.isOwner, isTrue);
    expect(report.actors, hasLength(1));
    expect(report.actors.first.displayName, 'أحمد');
    expect(report.actors.first.soldTotal, BigInt.from(1000));
  });

  test('rejects non-owner actor payload', () {
    expect(
      () => parsePeriodAnalytics({
        'version': 1,
        'shop_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'shop_name': 'متجر',
        'time_zone': 'Africa/Cairo',
        'period': 'week',
        'anchor_date': '2026-10-07',
        'start_date': '2026-10-01',
        'end_date': '2026-10-07',
        'contains_open_day': false,
        'is_owner': false,
        'summary': _summary(),
        'gold': [
          for (final k in [14, 18, 21, 22, 24])
            {'karat': k, 'sold': '0', 'bought': '0'},
        ],
        'actors': [
          {
            'actor_user_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            'display_name': 'أحمد',
            'role': 'employee',
            'gold': [],
            'sold_total': '0',
            'bought_total': '0',
          },
        ],
        'day_count': 0,
        'fingerprint': 'a' * 64,
        'server_date': '2026-10-27',
        'first_business_date': '2026-09-01',
        'last_selectable_date': '2026-10-27',
        'generated_at_shop': '2026-10-27 12:00:00',
        'generated_at_utc': '2026-10-27T09:00:00Z',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}

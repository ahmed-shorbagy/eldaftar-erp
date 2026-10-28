import 'package:eldafttar/src/features/audit_trail/data/supabase_audit_trail_gateway.dart';
import 'package:eldafttar/src/features/audit_trail/domain/audit_trail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('decodes a stable page and keeps a missing actor name empty', () {
    final page = decodeAuditTrailPage({
      'entries': [
        {
          'id': 'a4200000-0000-4000-8000-000000000003',
          'action': 'trade_deleted',
          'action_label': 'حذف عملية',
          'action_family': 'delete',
          'actor_user_id': 'a4000000-0000-4000-8000-0000000000a1',
          'actor_display_name': 'مالك السجل',
          'created_at': '2026-10-28T15:00:00+00:00',
          'created_at_shop': '2026-10-28 17:00:00',
          'operation_id': 'a4500000-0000-4000-8000-000000000003',
          'shop_sequence': '3',
          'business_date': '2026-10-28',
          'summary': 'تسلسل 3 · 2026-10-28 · حذف دون بديل',
        },
        {
          'id': 'a4200000-0000-4000-8000-000000000005',
          'action': 'inventory_removal_confirmed',
          'action_label': 'خصم مخزون',
          'action_family': 'deduction',
          'actor_user_id': 'a4000000-0000-4000-8000-0000000000aa',
          'actor_display_name': null,
          'created_at': '2026-10-28T14:00:00Z',
          'created_at_shop': '2026-10-28 16:00:00',
          'operation_id': 'a4500000-0000-4000-8000-000000000005',
          'shop_sequence': 5,
          'business_date': null,
          'summary': 'تسلسل 5',
        },
      ],
      'next_cursor_at': '2026-10-28T14:00:00+00:00',
      'next_cursor_id': 'a4200000-0000-4000-8000-000000000005',
      'time_zone': 'Africa/Cairo',
      'snapshot_at': '2026-10-28T15:05:00Z',
    });

    expect(page.entries, hasLength(2));
    expect(page.hasMore, isTrue);
    expect(page.timeZone, 'Africa/Cairo');
    expect(page.entries.first.actionLabel, 'حذف عملية');
    expect(page.entries.first.family, AuditTrailFamily.delete);
    expect(page.entries.first.shopSequence, '3');
    expect(page.entries.first.createdAt, DateTime.utc(2026, 10, 28, 15));
    expect(page.entries[1].actorDisplayName, isNull);
    expect(page.entries[1].shopSequence, '5');
    expect(page.entries[1].businessDate, isNull);
    expect(page.nextCursorId, 'a4200000-0000-4000-8000-000000000005');
  });

  test('rejects a broken cursor, an unknown family and an empty summary', () {
    expect(
      () => decodeAuditTrailPage({
        'entries': const [],
        'next_cursor_at': '2026-10-28T14:00:00Z',
        'next_cursor_id': null,
        'time_zone': 'Africa/Cairo',
        'snapshot_at': '2026-10-28T15:05:00Z',
      }),
      throwsA(
        isA<AuditTrailException>().having(
          (error) => error.failure,
          'failure',
          AuditTrailFailure.unavailable,
        ),
      ),
    );

    expect(
      () => decodeAuditTrailPage({
        'entries': [
          {
            'id': 'row',
            'action': 'mystery',
            'action_label': 'عملية مسجّلة',
            'action_family': 'other',
            'actor_user_id': 'user',
            'actor_display_name': null,
            'created_at': '2026-10-28T15:00:00Z',
            'created_at_shop': '2026-10-28 17:00:00',
            'operation_id': 'op',
            'shop_sequence': '1',
            'business_date': '2026-10-28',
            'summary': 'سجل مالي',
          },
        ],
        'next_cursor_at': null,
        'next_cursor_id': null,
        'time_zone': 'Africa/Cairo',
        'snapshot_at': '2026-10-28T15:05:00Z',
      }),
      throwsA(isA<AuditTrailException>()),
    );

    expect(
      () => decodeAuditTrailPage({
        'entries': [
          {
            'id': 'row',
            'action': 'sale_confirmed',
            'action_label': 'بيع',
            'action_family': 'post',
            'actor_user_id': 'user',
            'actor_display_name': '',
            'created_at': '2026-10-28T15:00:00Z',
            'created_at_shop': '2026-10-28 17:00:00',
            'operation_id': 'op',
            'shop_sequence': '1',
            'business_date': '2026-10-28',
            'summary': 'تسلسل 1',
          },
        ],
        'next_cursor_at': null,
        'next_cursor_id': null,
        'time_zone': 'Africa/Cairo',
        'snapshot_at': '2026-10-28T15:05:00Z',
      }),
      throwsA(isA<AuditTrailException>()),
    );
  });

  test(
    'maps database denials to access loss and a stale cursor separately',
    () {
      expect(
        auditTrailFailureFromPostgrest(
          const PostgrestException(message: 'forbidden', code: 'P0001'),
        ),
        AuditTrailFailure.accessLost,
      );
      expect(
        auditTrailFailureFromPostgrest(
          const PostgrestException(message: 'shop_unavailable'),
        ),
        AuditTrailFailure.accessLost,
      );
      expect(
        auditTrailFailureFromPostgrest(
          const PostgrestException(message: 'session_expired'),
        ),
        AuditTrailFailure.accessLost,
      );
      expect(
        auditTrailFailureFromPostgrest(
          const PostgrestException(message: 'stale_cursor', code: 'P0001'),
        ),
        AuditTrailFailure.staleCursor,
      );
      expect(
        auditTrailFailureFromPostgrest(
          const PostgrestException(message: 'invalid_input', code: '22023'),
        ),
        AuditTrailFailure.unavailable,
      );
    },
  );
}

import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retention notice keeps the shop-local end date', () {
    final notice = subscriptionNoticeFromApi({
      'shop_id': '11111111-1111-4111-8111-111111111111',
      'kind': 'retention_ending',
      'entitlement_expires_at': '2026-06-16T21:00:00Z',
      'retention_ends_at': '2026-10-15T21:00:00Z',
      'retention_ends_on': '2026-10-16',
    });

    expect(notice.kind, SubscriptionNoticeKind.retentionEnding);
    expect(notice.retentionEndsOn, '2026-10-16');
    expect(subscriptionNoticeKindToApi(notice.kind), 'retention_ending');
    expect(notice.expiresAt, DateTime.utc(2026, 6, 16, 21));
  });

  test('retention notice without a shop date is rejected', () {
    expect(
      () => subscriptionNoticeFromApi({
        'shop_id': '11111111-1111-4111-8111-111111111111',
        'kind': 'retention_ending',
        'entitlement_expires_at': '2026-06-16T21:00:00Z',
      }),
      throwsA(
        isA<SubscriptionNoticeException>().having(
          (error) => error.failure,
          'failure',
          SubscriptionNoticeFailure.invalidResponse,
        ),
      ),
    );
  });

  test('expired notice ignores a retention date', () {
    final notice = subscriptionNoticeFromApi({
      'shop_id': '11111111-1111-4111-8111-111111111111',
      'kind': 'expired',
      'entitlement_expires_at': '2026-06-16T21:00:00Z',
      'retention_ends_on': null,
    });

    expect(notice.kind, SubscriptionNoticeKind.expired);
    expect(notice.retentionEndsOn, isNull);
  });
}

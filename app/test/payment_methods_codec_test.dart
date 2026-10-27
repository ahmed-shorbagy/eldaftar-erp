import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/payment_method_catalog.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_balances.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PaymentMethodCatalog.resetDefaults);

  test('parseDailyLedger accepts renamed cash labels and archived flag', () {
    final pounds = (Piastres.parseWire('0') as Accepted<Piastres>).value.poundsText;
    final view = parseDailyLedger({
      'read_model_version': 1,
      'state': 'confirmed',
      'entitlement_status': 'active',
      'can_confirm': false,
      'business_day': {
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'business_date': '2026-10-27',
        'opened_at': '2026-10-27T08:00:00+00:00',
      },
      'cash': [
        {
          'method': 'cash',
          'label_ar': 'صندوق المحل',
          'piastres': '0',
          'pounds': pounds,
          'archived': false,
        },
        {
          'method': 'instant_transfer',
          'label_ar': 'انستاباي',
          'piastres': '0',
          'pounds': pounds,
        },
        {
          'method': 'wallet',
          'label_ar': 'محفظة',
          'piastres': '0',
          'pounds': pounds,
          'archived': true,
        },
        {
          'method': 'card',
          'label_ar': 'فيزا',
          'piastres': '0',
          'pounds': pounds,
          'archived': false,
        },
      ],
      'stock': <Object?>[],
      'scrap': <Object?>[],
      'feed': [
        {
          'kind': 'opening_balances_confirmed',
          'label_ar': 'رصيد افتتاحي',
          'operation_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'actor_display_name': 'منى',
          'occurred_at': '2026-10-27T08:00:00+00:00',
          'occurred_at_cairo': '2026-10-27T11:00:00',
        },
      ],
    });

    expect(view.cash.singleWhere((line) => line.method == 'cash').labelAr,
        'صندوق المحل');
    expect(view.cash.singleWhere((line) => line.method == 'wallet').archived, isTrue);
    expect(PaymentMethodCatalog.label(CashMethod.cash), 'صندوق المحل');
    expect(PaymentMethodCatalog.isArchived(CashMethod.wallet), isTrue);
    expect(
      PaymentMethodCatalog.entryChoices(),
      isNot(contains(CashMethod.wallet)),
    );
  });
}

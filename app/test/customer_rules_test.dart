import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/domain/customer_rules.dart';
import 'package:eldafttar/src/features/customers/application/customer_contract.dart';
import 'customer_fixtures.dart';

void main() {
  for (final number in [
    '٠١٠١١١١١١١١',
    '۰۱۰۱۱۱۱۱۱۱۱',
    '01011111111',
    '00201011111111',
    '+20 10 1111 1111',
    '(010) 1111-1111',
  ]) {
    test(
      'normalizes $number',
      () => expect(normalizeCustomerPhone(number), '+201011111111'),
    );
  }
  for (final number in [
    'abc',
    '+20119999999999',
    '201011111111',
    '0123',
    '++201011111111',
    '+201011111111\n',
  ]) {
    test(
      'rejects malformed $number',
      () => expect(normalizeCustomerPhone(number), isNull),
    );
  }
  test('duplicates compare normalized identity and primary is explicit', () {
    expect(
      customerPhoneIssue([
        const CustomerPhone(number: '01011111111', primary: true),
        const CustomerPhone(number: '+201011111111', primary: false),
      ]),
      'duplicate_phone',
    );
    expect(
      customerPhoneIssue([
        const CustomerPhone(number: '+33123456789', primary: false),
      ]),
      'primary_required',
    );
    expect(customerPhoneIssue([]), isNull);
  });
  test('Arabic name and multiline dated note rules', () {
    expect(validCustomerName('منى Mona'), isTrue);
    expect(validCustomerName(' '), isFalse);
    expect(validCustomerNote('طلب أول\nتفاصيل ثانية'), isTrue);
    expect(validCustomerNote('طلب\u0001'), isFalse);
  });
  test(
    'strict durable envelope rejects unknown fields and oversized version',
    () {
      final c = createCustomerCommand();
      expect(matchesCustomerEnvelope(c.key, c.kind, c.body), isTrue);
      final p = createCustomerPayload()..['extra'] = 'ignored';
      expect(
        matchesCustomerEnvelope(commandKey, 'customer_create', {
          'p_idempotency_key': commandKey,
          'p_payload': p,
        }),
        isFalse,
      );
      expect(
        matchesCustomerEnvelope(commandKey, 'customer_archive', {
          'p_idempotency_key': commandKey,
          'p_payload': {
            'version': 1,
            'kind': 'customer_archive',
            'customer_id': customerId,
            'expected_version': '9223372036854775808',
          },
        }),
        isFalse,
      );
    },
  );
}

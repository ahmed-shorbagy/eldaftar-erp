import 'dart:math';

import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = '11111111-1111-4111-8111-111111111111';

  OwnerRegistration? registration({
    String idempotencyKey = key,
    String ownerName = 'منى حسن',
    String businessName = 'ذهب الجيزة',
    String email = 'owner@example.test',
    String phone = '01012345678',
    String governorateCode = 'EG-GZ',
    String password = 'example-password',
  }) {
    return OwnerRegistration.tryCreate(
      idempotencyKey: idempotencyKey,
      ownerName: ownerName,
      businessName: businessName,
      email: email,
      phone: phone,
      governorateCode: governorateCode,
      password: password,
    );
  }

  test('requires all six signup fields', () {
    expect(registration(), isNotNull);
    expect(registration(ownerName: ' '), isNull);
    expect(registration(businessName: ''), isNull);
    expect(registration(email: ''), isNull);
    expect(registration(phone: ''), isNull);
    expect(registration(governorateCode: ''), isNull);
    expect(registration(password: ''), isNull);
    expect(registration(password: '        '), isNull);
  });

  test('normalizes email and hides the password from debug text', () {
    final created = registration(email: ' Owner@Example.TEST ')!;
    expect(created.email, 'owner@example.test');
    expect(created.ownerName, 'منى حسن');
    expect('$created', isNot(contains('example-password')));
    expect(AccountEmail.tryCanonical('a@b'), isNull);
    expect(AccountEmail.tryCanonical('${'a' * 310}@example.test'), isNull);
  });

  test('maps supported Egyptian mobiles to one canonical +20 form', () {
    const canonical = '+201012345678';
    expect(EgyptianPhone.tryCanonical('01012345678'), canonical);
    expect(EgyptianPhone.tryCanonical('010 1234 5678'), canonical);
    expect(EgyptianPhone.tryCanonical('(010) 1234-5678'), canonical);
    expect(EgyptianPhone.tryCanonical('+20 10 1234 5678'), canonical);
    expect(EgyptianPhone.tryCanonical('00201012345678'), canonical);
    expect(EgyptianPhone.tryCanonical('0020 10-1234-5678'), canonical);
    expect(EgyptianPhone.tryCanonical('01112345678'), '+201112345678');
    expect(EgyptianPhone.tryCanonical('+201212345678'), '+201212345678');
    expect(EgyptianPhone.tryCanonical('01512345678'), '+201512345678');
  });

  test('rejects invalid and non-Egyptian phones', () {
    const rejected = [
      '01312345678',
      '0101234567',
      '010123456789',
      '201012345678',
      '+966512345678',
      '+441234567890',
      '0020101234567',
      '+2001012345678',
      '010.12345678',
      '010\t12345678',
      '010\n12345678',
      '01012345678x',
      '+',
      '   ',
    ];
    for (final phone in rejected) {
      expect(EgyptianPhone.tryCanonical(phone), isNull, reason: phone);
    }
  });

  test('accepts the 27 ISO governorates and rejects others', () {
    expect(EgyptianGovernorates.codes, hasLength(27));
    for (final code in EgyptianGovernorates.codes) {
      expect(registration(governorateCode: code), isNotNull, reason: code);
    }
    for (final code in ['EG-HU', 'EG-XX', 'eg-gz', 'GZ', 'US-NY', 'EG-CAI']) {
      expect(EgyptianGovernorates.isValid(code), isFalse, reason: code);
      expect(registration(governorateCode: code), isNull, reason: code);
    }
  });

  test('password length is measured in UTF-8 bytes', () {
    expect(AccountPassword.isAcceptable('abcdefg'), isFalse);
    expect(AccountPassword.isAcceptable('abcdefgh'), isTrue);
    expect(AccountPassword.isAcceptable('a' * 72), isTrue);
    expect(AccountPassword.isAcceptable('a' * 73), isFalse);
    expect(AccountPassword.isAcceptable('م' * 36), isTrue);
    expect(AccountPassword.isAcceptable('م' * 37), isFalse);
    expect(AccountName.tryCanonical('أ' * 120), hasLength(120));
    expect(AccountName.tryCanonical('أ' * 121), isNull);
  });

  test('idempotency keys are UUID version 4', () {
    final generated = IdempotencyKey.generate(Random(7));
    expect(IdempotencyKey.isV4(generated), isTrue);
    expect(registration(idempotencyKey: generated), isNotNull);
    expect(
      registration(idempotencyKey: '11111111-1111-1111-8111-111111111111'),
      isNull,
    );
  });

  test(
    'sign-in accepts either canonical identifier and the same password rule',
    () {
      final email = SignInRequest.tryCreate(
        kind: SignInIdentifier.email,
        identifier: ' Owner@Example.TEST ',
        password: 'example-password',
      )!;
      final phone = SignInRequest.tryCreate(
        kind: SignInIdentifier.phone,
        identifier: '010-1234-5678',
        password: 'example-password',
      )!;
      expect(email.identifier, 'owner@example.test');
      expect(phone.identifier, '+201012345678');
      expect('$email$phone', isNot(contains('example-password')));
      expect(
        SignInRequest.tryCreate(
          kind: SignInIdentifier.phone,
          identifier: '+966512345678',
          password: 'example-password',
        ),
        isNull,
      );
      expect(
        SignInRequest.tryCreate(
          kind: SignInIdentifier.email,
          identifier: 'owner@example.test',
          password: 'short',
        ),
        isNull,
      );
    },
  );
}

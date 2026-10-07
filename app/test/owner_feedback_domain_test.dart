import 'package:eldafttar/src/features/auth/domain/registration_country.dart';
import 'package:eldafttar/src/features/auth/domain/owner_registration.dart';
import 'package:eldafttar/src/theme/amount_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('country and phone agree and unsupported countries fail closed', () {
    final sa = RegistrationCountry.byCode('SA')!;
    expect(sa.canonicalPhone('050 123-4567'), '+966501234567');
    expect(sa.canonicalPhone('00966501234567'), '+966501234567');
    expect(sa.canonicalPhone('+971501234567'), isNull);
    expect(sa.canonicalPhone('0501234567x'), isNull);
    expect(sa.canonicalPhone('123'), isNull);
    expect(RegistrationCountry.internationalPhone('0501234567'), isNull);
    expect(
      RegistrationCountry.internationalPhone('+966501234567'),
      '+966501234567',
    );
    expect(RegistrationCountry.byCode('ZZ'), isNull);
    expect(RegistrationCountry.validRegion('SA:'), isTrue);
    expect(RegistrationCountry.validRegion('ZZ:منطقة'), isFalse);
    expect(RegistrationCountry.validRegion('EG:الجيزة'), isTrue);
    expect(RegistrationCountry.validRegion('SA:الرياض'), isTrue);
  });
  test(
    'every supported country permits an omitted region and validates its phone',
    () {
      for (final country in RegistrationCountry.all) {
        expect(country.regionCode('  '), '${country.code}:');
        expect(RegistrationCountry.validRegion('${country.code}:'), isTrue);
        expect(country.regionCode('أ' * 121), isNull);
        expect(country.regionCode('مدينة\nأخرى'), isNull);
        final profile = OwnerRegistration.tryCreate(
          idempotencyKey: '11111111-1111-4111-8111-111111111111',
          ownerName: 'مالك تجريبي',
          businessName: 'محل تجريبي',
          email: 'owner@example.test',
          phone: country.code == 'EG'
              ? '01012345678'
              : '+${country.dialCode}501234567',
          governorateCode: '${country.code}:',
          password: 'example-password',
        );
        expect(profile, isNotNull, reason: country.code);
      }
      expect(RegistrationCountry.validRegion('ZZ:'), isFalse);
      expect(RegistrationCountry.validRegion('SA: '), isFalse);
    },
  );
  test('international owner registration retains exact replay profile', () {
    final profile = OwnerRegistration.tryCreate(
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
      ownerName: 'مالك تجريبي',
      businessName: 'محل تجريبي',
      email: 'owner@example.test',
      phone: '0501234567',
      governorateCode: 'SA:الرياض',
      password: 'example-password',
    );
    expect(profile, isNotNull);
    expect(profile!.phone, '+966501234567');
    expect(profile.governorateCode, 'SA:الرياض');
    expect('$profile', isNot(contains('example-password')));
  });
  test(
    'display formatting never rounds exact cash cents or large integers',
    () {
      expect(displayPounds('30000.00'), '30,000');
      expect(displayPounds('30000.50'), '30,000.50');
      expect(displayPounds('90071992547409.93'), '90,071,992,547,409.93');
      expect(displayPounds('-1250.01'), '−1,250.01');
      expect(displayPounds('1500000.25', compact: true), '1.5 مليون');
      expect(displayPounds('1500000.25'), '1,500,000.25');
      expect(displayPounds('0.01'), '0.01');
      expect(displayPounds('—'), '—');
    },
  );
}

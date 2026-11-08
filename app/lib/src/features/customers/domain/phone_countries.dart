import 'customer_rules.dart';

final class PhoneCountry {
  const PhoneCountry(this.nameAr, this.dial, this.lengths, {this.mobilePrefix});

  final String nameAr;
  final String dial;
  final Set<int> lengths;
  final String? mobilePrefix;

  bool prefixOk(String national) =>
      mobilePrefix == null || RegExp('^(?:$mobilePrefix)').hasMatch(national);
}

const egypt = PhoneCountry('مصر', '20', {10}, mobilePrefix: '1[0125]');

const phoneCountries = <PhoneCountry>[
  egypt,
  PhoneCountry('السعودية', '966', {9}, mobilePrefix: '5'),
  PhoneCountry('الإمارات', '971', {9}, mobilePrefix: '5'),
  PhoneCountry('الكويت', '965', {8}),
  PhoneCountry('قطر', '974', {8}),
  PhoneCountry('البحرين', '973', {8}),
  PhoneCountry('عُمان', '968', {8}),
  PhoneCountry('الأردن', '962', {9}, mobilePrefix: '7'),
  PhoneCountry('العراق', '964', {10}, mobilePrefix: '7'),
  PhoneCountry('ليبيا', '218', {9}),
  PhoneCountry('السودان', '249', {9}),
  PhoneCountry('فلسطين', '970', {9}),
  PhoneCountry('سوريا', '963', {9}),
  PhoneCountry('اليمن', '967', {9}),
  PhoneCountry('لبنان', '961', {7, 8}),
  PhoneCountry('تونس', '216', {8}),
  PhoneCountry('الجزائر', '213', {9}),
  PhoneCountry('المغرب', '212', {9}),
  PhoneCountry('تركيا', '90', {10}),
  PhoneCountry('المملكة المتحدة', '44', {10}),
  PhoneCountry('الولايات المتحدة وكندا', '1', {10}),
  PhoneCountry('ألمانيا', '49', {10, 11}),
  PhoneCountry('إيطاليا', '39', {9, 10}),
  PhoneCountry('فرنسا', '33', {9}),
];

sealed class PhoneCheck {
  const PhoneCheck();
}

final class PhoneAccepted extends PhoneCheck {
  const PhoneAccepted(this.e164);
  final String e164;
}

final class PhoneRejected extends PhoneCheck {
  const PhoneRejected(this.message);
  final String message;
}

PhoneCountry? countryForDial(String international) {
  PhoneCountry? match;
  for (final country in phoneCountries) {
    if (!international.startsWith(country.dial)) continue;
    if (match == null || country.dial.length > match.dial.length) {
      match = country;
    }
  }
  return match;
}

PhoneCheck checkCustomerPhone(PhoneCountry country, String national) {
  var digits = foldCustomerDigits(national).replaceAll(RegExp(r'[\s-]'), '');
  if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
  if (digits.startsWith('+')) {
    final body = digits.substring(1);
    final detected = countryForDial(body);
    if (detected == null) {
      return PhoneRejected('تحقق من رقم ${country.nameAr}.');
    }
    final rest = body.substring(detected.dial.length);
    return _checkNational(
      detected,
      rest.startsWith('0') ? rest.substring(1) : rest,
    );
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  return _checkNational(country, digits);
}

PhoneCheck _checkNational(PhoneCountry country, String national) {
  if (national.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(national)) {
    return PhoneRejected('تحقق من رقم ${country.nameAr}.');
  }
  final shortest = country.lengths.reduce((a, b) => a < b ? a : b);
  final longest = country.lengths.reduce((a, b) => a > b ? a : b);
  if (national.length < shortest) {
    final missing = shortest - national.length;
    return PhoneRejected(
      'الرقم ناقص $missing ${missing == 1 ? 'رقم' : 'أرقام'}.',
    );
  }
  if (national.length > longest) {
    return PhoneRejected('الرقم أطول من المعتاد في ${country.nameAr}.');
  }
  if (!country.lengths.contains(national.length) ||
      !country.prefixOk(national)) {
    return country.dial == egypt.dial
        ? const PhoneRejected(
            'رقم الموبايل المصري يبدأ بـ 010 أو 011 أو 012 أو 015.',
          )
        : PhoneRejected('تحقق من رقم ${country.nameAr}.');
  }
  return PhoneAccepted('+${country.dial}$national');
}

({PhoneCountry country, String national}) splitCustomerPhone(String raw) {
  var digits = foldCustomerDigits(raw).replaceAll(RegExp(r'[\s()-]'), '');
  if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
  if (digits.startsWith('+')) {
    final body = digits.substring(1);
    final detected = countryForDial(body);
    if (detected != null) {
      final rest = body.substring(detected.dial.length);
      return (
        country: detected,
        national: rest.startsWith('0') ? rest.substring(1) : rest,
      );
    }
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  return (country: egypt, national: digits.startsWith('+') ? '' : digits);
}

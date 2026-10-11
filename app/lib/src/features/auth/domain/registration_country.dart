import 'account_identifiers.dart';
import 'egyptian_governorates.dart';

/// Registration location and telephone prefix, independent of presentation.
class RegistrationCountry {
  const RegistrationCountry(this.code, this.nameAr, this.dialCode, this.flag);
  final String code;
  final String nameAr;
  final String dialCode;
  final String flag;

  static const all = [
    RegistrationCountry('EG', 'مصر', '20', '🇪🇬'),
    RegistrationCountry('SA', 'السعودية', '966', '🇸🇦'),
    RegistrationCountry('AE', 'الإمارات', '971', '🇦🇪'),
    RegistrationCountry('MA', 'المغرب', '212', '🇲🇦'),
    RegistrationCountry('LY', 'ليبيا', '218', '🇱🇾'),
    RegistrationCountry('YE', 'اليمن', '967', '🇾🇪'),
    RegistrationCountry('JO', 'الأردن', '962', '🇯🇴'),
    RegistrationCountry('KW', 'الكويت', '965', '🇰🇼'),
    RegistrationCountry('QA', 'قطر', '974', '🇶🇦'),
    RegistrationCountry('BH', 'البحرين', '973', '🇧🇭'),
    RegistrationCountry('OM', 'عُمان', '968', '🇴🇲'),
    RegistrationCountry('IQ', 'العراق', '964', '🇮🇶'),
    RegistrationCountry('LB', 'لبنان', '961', '🇱🇧'),
    RegistrationCountry('PS', 'فلسطين', '970', '🇵🇸'),
    RegistrationCountry('SY', 'سوريا', '963', '🇸🇾'),
    RegistrationCountry('DZ', 'الجزائر', '213', '🇩🇿'),
    RegistrationCountry('TN', 'تونس', '216', '🇹🇳'),
    RegistrationCountry('SD', 'السودان', '249', '🇸🇩'),
    RegistrationCountry('MR', 'موريتانيا', '222', '🇲🇷'),
    RegistrationCountry('SO', 'الصومال', '252', '🇸🇴'),
    RegistrationCountry('DJ', 'جيبوتي', '253', '🇩🇯'),
    RegistrationCountry('KM', 'جزر القمر', '269', '🇰🇲'),
  ];

  static RegistrationCountry? byCode(String code) {
    for (final country in all) {
      if (country.code == code) return country;
    }
    return null;
  }

  String? canonicalPhone(String input) {
    if (code == 'EG') return EgyptianPhone.tryCanonical(input);
    if (RegExp(r'[^0-9+ \-()]').hasMatch(input)) return null;
    var value = input.replaceAll(RegExp(r'[ \-()]'), '');
    if (value.startsWith('00')) value = '+${value.substring(2)}';
    if (value.startsWith('+')) {
      if (!value.startsWith('+$dialCode')) return null;
      value = value.substring(dialCode.length + 1);
    } else if (value.startsWith('0')) {
      value = value.substring(1);
    }
    if (!RegExp(r'^[1-9][0-9]{6,11}$').hasMatch(value)) return null;
    final result = '+$dialCode$value';
    return result.length <= 16 ? result : null;
  }

  /// Egypt requires a catalog ISO governorate code. Other supported countries
  /// require a non-empty city/region label stored as `CC:label`.
  String? regionCode(String input) {
    if (code == 'EG') {
      final catalog = input.trim().toUpperCase();
      return EgyptianGovernorates.isValid(catalog) ? catalog : null;
    }
    final region = AccountName.tryCanonical(input);
    return region == null ? null : '$code:$region';
  }

  static bool validRegion(String value) {
    if (EgyptianGovernorates.isValid(value)) return true;
    if (value.length < 4 || value[2] != ':') return false;
    if (value.substring(0, 2) == 'EG') return false;
    final country = byCode(value.substring(0, 2));
    return country != null && country.regionCode(value.substring(3)) == value;
  }

  /// Catalog ISO codes accept harmless case and surrounding space. Stored
  /// `CC:label` values stay exact so historical empty or malformed regions
  /// cannot be introduced as new registrations.
  static String? canonicalRegion(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final catalog = trimmed.toUpperCase();
    if (EgyptianGovernorates.isValid(catalog)) return catalog;
    return validRegion(trimmed) ? trimmed : null;
  }

  static String? internationalPhone(String input) {
    final egypt = EgyptianPhone.tryCanonical(input);
    if (egypt != null) return egypt;
    final stripped = input.replaceAll(RegExp(r'[ \-()]'), '');
    if (!stripped.startsWith('+') && !stripped.startsWith('00')) return null;
    for (final country in all) {
      final canonical = country.canonicalPhone(input);
      if (canonical != null) return canonical;
    }
    return null;
  }
}

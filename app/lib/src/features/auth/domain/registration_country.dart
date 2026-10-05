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

  /// Egypt keeps its existing ISO region code. Other countries use a namespaced
  /// region label until a maintained region catalog is available.
  String? regionCode(String input) {
    if (code == 'EG' && EgyptianGovernorates.isValid(input)) return input;
    final region = AccountName.tryCanonical(input);
    return region == null ? null : '$code:$region';
  }

  static bool validRegion(String value) {
    if (EgyptianGovernorates.isValid(value)) return true;
    if (value.length < 4 || value[2] != ':') return false;
    final country = byCode(value.substring(0, 2));
    return country != null && country.regionCode(value.substring(3)) == value;
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

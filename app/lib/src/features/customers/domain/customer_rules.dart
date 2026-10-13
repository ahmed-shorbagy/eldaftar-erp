String foldCustomerDigits(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
  }
  return value;
}

String? normalizeCustomerPhone(String raw) {
  if (raw.isEmpty ||
      raw.length > 32 ||
      raw != raw.trim() ||
      RegExp(r'[^0-9٠-٩۰-۹+ ().-]').hasMatch(raw)) {
    return null;
  }
  var value = foldCustomerDigits(raw).replaceAll(RegExp(r'[ ().-]'), '');
  if (value.startsWith('00')) value = '+${value.substring(2)}';
  if (value.startsWith('0')) value = '+20${value.substring(1)}';
  if (!RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(value)) return null;
  if (value.startsWith('+20') &&
      !RegExp(r'^\+201[0125][0-9]{8}$').hasMatch(value) &&
      !RegExp(r'^\+20[2-9][0-9]{7,8}$').hasMatch(value)) {
    return null;
  }
  return value;
}

bool validCustomerName(String value) =>
    value == value.trim() &&
    value.isNotEmpty &&
    value.runes.length <= 200 &&
    RegExp(r'[ء-ي]').hasMatch(value) &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
bool validCustomerNote(String value) =>
    value == value.trim() &&
    value.isNotEmpty &&
    value.runes.length <= 1000 &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value);

class CustomerPhone {
  const CustomerPhone({required this.number, required this.primary});
  final String number;
  final bool primary;
  Map<String, Object?> toWire() => {'number': number, 'is_primary': primary};
}

String? customerPhoneIssue(List<CustomerPhone> phones) {
  if (phones.length > 10) return 'invalid_input';
  final seen = <String>{};
  var primary = 0;
  for (final phone in phones) {
    final norm = normalizeCustomerPhone(phone.number);
    if (norm == null) return 'invalid_phone';
    if (!seen.add(norm)) return 'duplicate_phone';
    if (phone.primary) primary++;
  }
  if (phones.isNotEmpty && primary == 0) return 'primary_required';
  if (primary > 1) return 'duplicate_primary';
  return null;
}

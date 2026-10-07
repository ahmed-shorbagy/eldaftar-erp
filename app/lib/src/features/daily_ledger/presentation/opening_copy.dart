import '../domain/opening_catalog.dart';

const openingStorageCopy =
    'تعذر قراءة أو حفظ الطلب على هذا الجهاز. لم يُرسل طلب جديد.';

bool openingAccessDenied(String? code) =>
    code == 'forbidden' ||
    code == 'shop_unavailable' ||
    code == 'session_expired' ||
    code == 'unauthenticated';

String openingFailureCopy(String? code) => switch (code) {
  'unauthenticated' => 'يلزم تسجيل الدخول',
  'session_expired' => 'انتهت الجلسة',
  'forbidden' => 'غير مسموح',
  'shop_unavailable' => 'بيانات المحل غير متاحة',
  'shop_not_active' => 'الاشتراك غير نشط',
  'invalid_input' => 'البيانات المدخلة غير صالحة',
  'negative_amount' => 'لا يُقبل مبلغ سالب',
  'overflow' => 'القيمة خارج الحد المسموح',
  'unsupported_category_karat' => 'العيار أو الصنف غير مدعوم',
  'duplicate_bucket' => 'تكرار نفس الصنف والعيار',
  'opening_already_confirmed' => 'تم تأكيد الأرصدة الافتتاحية من قبل',
  'payload_mismatch' => 'بيانات الطلب تختلف عن العملية المحفوظة',
  _ => 'تعذر إتمام العملية. حاول مجددًا.',
};

String cashMethodLabel(CashMethod method) => switch (method) {
  CashMethod.cash => 'نقدي',
  CashMethod.instantTransfer => 'انستا',
  CashMethod.wallet => 'محفظة',
  CashMethod.card => 'فيزا',
};

String stockCategoryLabel(StockCategory category) => switch (category) {
  StockCategory.workedJewelry => 'مشغولات',
  StockCategory.bullion => 'سبائك',
  StockCategory.coin => 'جنيهات',
};

const openingCategoryChoices = <StockCategory>[
  StockCategory.workedJewelry,
  StockCategory.bullion,
  StockCategory.coin,
];

const scrapKaratChoices = <int>[14, 18, 21, 22, 24];

const _arabicMonths = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// Renders a server `YYYY-MM-DD` in Arabic without shifting the calendar day.
String formatServerDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate.replaceAll('T', ' ');
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null || month < 1 || month > 12) {
    return isoDate.replaceAll('T', ' ');
  }
  return '$day ${_arabicMonths[month - 1]} ${parts[0]}';
}

/// Renders the server Cairo timestamp. The `T` separator is not shown.
String formatServerCairoTimestamp(String value) {
  final pieces = value.split('T');
  if (pieces.length != 2) return value.replaceAll('T', ' ');
  return '${formatServerDate(pieces[0])}، ${pieces[1]}';
}

/// Short preview only; detail views keep the complete server timestamp.
String formatCompactServerTimestamp(String value) {
  final pieces = value.split('T');
  if (pieces.length != 2) return formatServerCairoTimestamp(value);
  final time = RegExp(r'^\d{2}:\d{2}').firstMatch(pieces[1])?.group(0);
  if (time == null) return formatServerCairoTimestamp(value);
  final date = formatServerDate(pieces[0]).replaceFirst(RegExp(r' \d{4}$'), '');
  return '$date · $time';
}

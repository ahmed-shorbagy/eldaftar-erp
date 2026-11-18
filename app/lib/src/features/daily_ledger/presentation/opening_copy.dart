import '../../../theme/shop_clock.dart';
import '../domain/opening_catalog.dart';
import '../domain/payment_method_catalog.dart';

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
  'opening_already_confirmed' => 'الدفتر مفتوح من قبل',
  'payload_mismatch' => 'بيانات الطلب تختلف عن العملية المحفوظة',
  _ => 'تعذر إتمام العملية. حاول مجددًا.',
};

String cashMethodLabel(CashMethod method) => PaymentMethodCatalog.label(method);

/// A stock row that has a karat and no item name: «سبائك عيار 24», «كسر عيار
/// 21». Jewelry carries no kind word and reads «عيار 21» alone, as the old
/// app's figures do (FB-003). [kindLabel] is used for every other kind.
String karatRowLabel(
  String kindLabel,
  Object? category,
  Object? karat, {
  String separator = ' ',
}) => category == 'worked_jewelry'
    ? 'عيار $karat'
    : '$kindLabel$separator'
          'عيار $karat';

/// The kind word for headings and choice lists. Jewelry is «أصناف»; the word
/// the owner rejected is never shown.
String stockCategoryLabel(StockCategory category) => switch (category) {
  StockCategory.workedJewelry => 'أصناف',
  StockCategory.bullion => 'سبائك',
  StockCategory.coin => 'جنيهات',
};

const openingCategoryChoices = <StockCategory>[
  StockCategory.workedJewelry,
  StockCategory.bullion,
  StockCategory.coin,
];

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

const _arabicWeekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// Weekday plus calendar date, for example «الأحد 8 نوفمبر 2026».
String formatLedgerHeading(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return formatServerDate(isoDate);
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return formatServerDate(isoDate);
  }
  final weekday = DateTime.utc(year, month, day).weekday;
  return '${_arabicWeekdays[weekday - 1]} ${formatServerDate(isoDate)}';
}

/// Month and year, for example «نوفمبر 2026».
String formatLedgerMonth(String isoDate) {
  final parts = isoDate.split('-');
  final month = parts.length == 3 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return isoDate;
  return '${_arabicMonths[month - 1]} ${parts[0]}';
}

/// Renders a shop wall time as «17 نوفمبر 2026، 5:49 م».
///
/// The ordinary clock everywhere (owner rule, 2026-11-17): see `shop_clock`.
String formatServerCairoTimestamp(String value) => shopDateTime(value);

/// Short preview: «17 نوفمبر · 5:49 م», without the year.
String formatCompactServerTimestamp(String value) {
  final clock = shopClockOf(value);
  if (clock == null) return shopDateTime(value);
  final date = shopDate(value).replaceFirst(RegExp(r' \d{4}$'), '');
  return '$date · $clock';
}

/// Shop-local 12-hour time with Arabic ص/م and no calendar day.
///
/// [value] is a persisted shop-zone wall time (`YYYY-MM-DDTHH:MM:SS`), already
/// converted from the server UTC instant.
String formatShopTwelveHourTime(String value) =>
    shopClockOf(value) ?? shopDateTime(value);

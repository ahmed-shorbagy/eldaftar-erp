import '../domain/shop_image.dart';

abstract final class ShopImageCopy {
  static const title = 'لوجو المحل';
  static const body = 'يظهر لوجو المحل أعلى الدفتر اليومي وعلى الفواتير.';
  static const pick = 'اختيار اللوجو';
  static const change = 'تغيير اللوجو';
  static const clear = 'إزالة اللوجو';
  static const save = 'حفظ اللوجو';
  static const preparing = 'جاري تجهيز اللوجو…';
  static const saving = 'جاري الحفظ…';
  static const clearing = 'جاري الإزالة…';
  static const success = 'تم حفظ لوجو المحل.';
  static const cleared = 'تمت إزالة لوجو المحل.';
  static const empty = 'لا يوجد لوجو للمحل بعد. يظهر لوجو الدفتر بدلاً منه.';
  static const signupHint = 'لوجو المحل (اختياري)';
  static const signupHelp =
      'التقط صورة للوجو بالكاميرا أو اختره من المعرض. يظهر على الفواتير وأعلى الدفتر اليومي.';
  static const pickSheetTitle = 'مصدر لوجو المحل';
  static const pickCamera = 'الكاميرا';
  static const pickGallery = 'معرض الصور';
  static const rejected = 'تعذّر استخدام هذه الصورة كلوجو. جرّب صورة أخرى.';
  static const tooLarge = 'حجم الصورة أكبر من الحد المسموح.';
  static const unavailable = 'تعذّر حفظ لوجو المحل. أعد المحاولة.';
  static const loadFailed = 'تعذّر تحميل لوجو المحل. اختر اللوجو مجدداً لحفظه.';
  static const unauthorized = 'انتهت الجلسة. سجّل الدخول ثم أعد المحاولة.';

  static String messageFor(ShopImageFailure failure) => switch (failure) {
    ShopImageFailure.rejected => rejected,
    ShopImageFailure.tooLarge => tooLarge,
    ShopImageFailure.unauthorized => unauthorized,
    ShopImageFailure.unavailable ||
    ShopImageFailure.unknownOutcome => unavailable,
  };
}

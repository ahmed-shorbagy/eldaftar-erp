import '../domain/shop_image.dart';

abstract final class ShopImageCopy {
  static const title = 'صورة المتجر';
  static const body = 'تظهر صورة المتجر في رأس الدفتر اليومي بجانب اسم المتجر.';
  static const pick = 'اختيار صورة';
  static const change = 'تغيير الصورة';
  static const clear = 'إزالة الصورة';
  static const save = 'حفظ الصورة';
  static const saving = 'جاري الحفظ…';
  static const clearing = 'جاري الإزالة…';
  static const success = 'تم حفظ صورة المتجر.';
  static const cleared = 'تمت إزالة صورة المتجر.';
  static const empty = 'لا توجد صورة للمتجر بعد. يظهر شعار الدفتر بدلاً منها.';
  static const signupHint = 'صورة المتجر (اختياري)';
  static const signupHelp =
      'التقط صورة بالكاميرا أو اختر من المعرض. الصور الكبيرة تُصغَّر تلقائياً، ويمكن إضافتها لاحقاً من المزيد.';
  static const pickSheetTitle = 'مصدر صورة المتجر';
  static const pickCamera = 'الكاميرا';
  static const pickGallery = 'معرض الصور';
  static const rejected =
      'تعذّر استخدام هذه الصورة. جرّب صورة أخرى من الكاميرا أو المعرض.';
  static const tooLarge = 'حجم الصورة أكبر من الحد المسموح.';
  static const unavailable = 'تعذّر حفظ صورة المتجر. أعد المحاولة.';
  static const unauthorized = 'انتهت الجلسة. سجّل الدخول ثم أعد المحاولة.';

  static String messageFor(ShopImageFailure failure) => switch (failure) {
    ShopImageFailure.rejected => rejected,
    ShopImageFailure.tooLarge => tooLarge,
    ShopImageFailure.unauthorized => unauthorized,
    ShopImageFailure.unavailable ||
    ShopImageFailure.unknownOutcome => unavailable,
  };
}

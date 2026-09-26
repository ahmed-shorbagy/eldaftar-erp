/// Arabic user-facing copy for the starter shell.
abstract final class ShellCopy {
  static const appTitle = 'الدفتر';
  static const prototypeLabel = 'نموذج أولي';
  static const prototypeBody =
      'هذه واجهة البداية فقط. الإعداد التفاعلي وشاشات العمل غير متاحة بعد.';

  static const missingTitle = 'إعداد Supabase غير مكتمل';
  static const missingBody =
      'لم يُمرَّر عنوان المشروع والمفتاح العام معًا، لذلك لم تُهيأ مكتبة Supabase.';
  static const missingHint =
      'مرّر القيمتين معًا عند التشغيل أو البناء. المطلوب هو المفتاح العام فقط، ولا يُوضع مفتاح الخدمة داخل التطبيق.';
  static const defineExample =
      '--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_PUBLISHABLE_KEY=...';

  static const readyTitle = 'تمت تهيئة Supabase';
  static const readyBody =
      'وُجد العنوان والمفتاح العام، وتم إنشاء العميل. الإعداد التفاعلي وشاشات العمل غير متاحة بعد.';

  static const failedTitle = 'تعذرت تهيئة Supabase';
  static const failedBody =
      'وُجدت القيمتان، لكن إنشاء العميل فشل. راجع العنوان والمفتاح العام ثم أعد تشغيل التطبيق.';

  static const toggleToDark = 'التبديل إلى الوضع الداكن';
  static const toggleToLight = 'التبديل إلى الوضع الفاتح';
}

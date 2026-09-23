/** Arabic user-facing copy for the administration starter shell. */
export const shellCopy = {
  appTitle: 'الدفتر',
  prototypeLabel: 'نموذج أولي',
  prototypeBody:
    'هذه واجهة إدارة البداية فقط. تسجيل الدخول وشاشات الإدارة غير متاحة بعد.',
  missingTitle: 'إعداد Supabase غير مكتمل',
  missingBody:
    'لم يُضبط عنوان المشروع والمفتاح العام معًا، لذلك لم يُنشأ عميل Supabase.',
  missingHint:
    'ضع القيمتين معًا في ملف البيئة المحلي. المطلوب هو المفتاح العام فقط، ولا يُوضع مفتاح الخدمة أو أسرار التخزين داخل المتصفح.',
  defineExample: 'VITE_SUPABASE_URL=...\nVITE_SUPABASE_PUBLISHABLE_KEY=...',
  readyTitle: 'تمت تهيئة Supabase',
  readyBody:
    'وُجد العنوان والمفتاح العام، وتم إنشاء العميل. تسجيل الدخول وشاشات الإدارة غير متاحة بعد.',
  failedTitle: 'تعذرت تهيئة Supabase',
  failedBody:
    'وُجدت القيمتان، لكن إنشاء العميل فشل. راجع العنوان والمفتاح العام ثم أعد تحميل الصفحة.',
  toggleToDark: 'التبديل إلى الوضع الداكن',
  toggleToLight: 'التبديل إلى الوضع الفاتح',
} as const

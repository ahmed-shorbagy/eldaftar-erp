# الدفتر — تطبيق Flutter

نموذج أولي لواجهة عربية من اليمين إلى اليسار بمظهر Material 3، مع تبديل الوضع الفاتح والداكن. لا توجد في هذا الإصدار شاشات لتسجيل الدخول أو الإعداد التفاعلي أو العمل اليومي.

أُنشئ المجلد من جذر المستودع بالأمر:

```text
flutter create --platforms=android,ios,windows --project-name eldafttar app
```

نفّذ أوامر التشغيل والبناء والفحص من داخل مجلد `app`.

## تهيئة Supabase

القيمتان عامتان وتُمرَّران وقت الترجمة عبر `--dart-define`:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

تُستدعى `Supabase.initialize` فقط عندما تكون القيمتان غير فارغتين بعد حذف المسافات الزائدة. إذا غابت إحداهما تظهر رسالة إعداد عربية ولا يُنشأ العميل.

ضع عنوان المشروع والمفتاح العام من إعدادات واجهة Supabase مكان العنصرين `https://YOUR_PROJECT_REF.supabase.co` و`YOUR_PUBLISHABLE_KEY`. المفتاح العام هو مفتاح `sb_publishable`، لا مفتاح anon القديم ولا مفتاح الخدمة.

اختيار المظهر يُحفظ محليًا في المفتاح `theme_mode` بالقيمة `light` أو `dark`. قبل أول اختيار يتبع التطبيق مظهر النظام.

## التشغيل

بدون تهيئة Supabase:

```text
flutter run -d windows
```

```text
flutter run -d android
```

```text
flutter run -d ios
```

مع التهيئة، والقيمتان معًا:

```text
flutter run -d windows --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

```text
flutter run -d android --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

```text
flutter run -d ios --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

تشغيل iOS يتطلب macOS مع Xcode.

## البناء

بدون تهيئة Supabase:

```text
flutter build windows
```

```text
flutter build apk
```

```text
flutter build ios
```

مع التهيئة، والقيمتان معًا:

```text
flutter build windows --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

```text
flutter build apk --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

```text
flutter build ios --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

## الفحص

```text
flutter pub get
```

```text
dart format .
```

```text
flutter analyze
```

```text
flutter test
```

# الدفتر — تطبيق Flutter

نموذج أولي لواجهة عربية من اليمين إلى اليسار بمظهر Material 3، مع تبديل الوضع الفاتح والداكن. لا توجد في هذا الإصدار شاشات لتسجيل الدخول أو الإعداد التفاعلي أو العمل اليومي.

أُنشئ المجلد من جذر المستودع بالأمر:

```text
flutter create --platforms=android,ios,windows --project-name eldafttar app
```

نفّذ أوامر التشغيل والبناء والفحص من داخل مجلد `app`.

## تهيئة Supabase

القيمتان عامتان وتُمرَّران وقت الترجمة عبر `--dart-define-from-file`:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

تُستدعى `Supabase.initialize` فقط عندما تكون القيمتان غير فارغتين بعد حذف المسافات الزائدة. إذا غابت إحداهما تظهر رسالة إعداد عربية ولا يُنشأ العميل.

مصدر القيم هو `supabase/.env.local` في جذر المستودع. أمر البناء ينسخ العنوان والمفتاح العام فقط إلى `app/config/local.json`، وهو ملف متجاهَل. مفاتيح التخزين تبقى في ملف البيئة ولا تدخل التطبيق. المفتاح العام هو مفتاح `sb_publishable`، لا مفتاح الخدمة.

اختيار المظهر يُحفظ محليًا في المفتاح `theme_mode` بالقيمة `light` أو `dark`. قبل أول اختيار يتبع التطبيق مظهر النظام.

## التشغيل والبناء

من جذر المستودع. الأمر يقرأ `supabase/.env.local` ثم يشغّل Flutter:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 run-android
```

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 run-windows
```

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 apk
```

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 windows
```

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 ios
```

تشغيل وبناء iOS يتطلبان macOS مع Xcode. ملف `app/config/local.example.json` يوضّح شكل ملف الإعداد فقط.

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

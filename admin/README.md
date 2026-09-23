# الدفتر — لوحة الإدارة

نموذج أولي لواجهة إدارة عربية من اليمين إلى اليسار بمكتبة Material UI، مع تبديل الوضع الفاتح والداكن. لا توجد في هذا الإصدار شاشات لتسجيل الدخول أو صفحات الإدارة.

أُنشئ المجلد من جذر المستودع بالأمر:

```text
npm create vite@latest admin -- --template react-ts
```

نفّذ أوامر التشغيل والبناء والفحص من داخل مجلد `admin`.

## تهيئة Supabase

القيمتان عامتان وتُقرآن من متغيرات البيئة التي تبدأ بـ `VITE_`:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

يُستدعى `createClient` من `@supabase/supabase-js` فقط عندما تكون القيمتان غير فارغتين بعد حذف المسافات الزائدة. إذا غابت إحداهما تظهر رسالة إعداد عربية ولا يُنشأ العميل.

انسخ `.env.example` إلى `.env.local` وضع عنوان المشروع والمفتاح العام مكان `https://YOUR_PROJECT_REF.supabase.co` و`YOUR_PUBLISHABLE_KEY`. المفتاح العام هو مفتاح `sb_publishable`، لا مفتاح الخدمة. لا تضع أسرار التخزين في أي متغير يصل إلى المتصفح.

اختيار المظهر يُحفظ في المتصفح تحت المفتاح `theme_mode` بالقيمة `light` أو `dark`. قبل أول اختيار يتبع المظهر إعداد النظام.

## التشغيل

```text
npm install
```

```text
npm run dev
```

## البناء والفحص

```text
npm run build
```

```text
npm run lint
```

```text
npm test
```

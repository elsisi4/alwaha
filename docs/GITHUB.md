# البناء السحابي على GitHub

عند كل رفع (push) إلى فرع `main` يبني GitHub تطبيقي المندوب والإدارة تلقائيًا، وينشرهما في صفحة **Releases** باسم `v1.0.N` (حيث N رقم التشغيل)، وتصبح التطبيقات المثبتة قادرة على تحديث نفسها.

## ما يفعله `build_apk.yml`
1. يفحص وجود `env.json` (رابط Supabase والمفتاح العام) ويمرره للبناء. **بدونه يظهر في التطبيق: «أضف رابط Supabase ومفتاح anon».**
2. يفحص الكود (`flutter analyze`)، فإن وُجد خطأ توقف البناء.
3. يبني الملفين ويرقّم الإصدار تلقائيًا: اسم الإصدار `1.0.N` ورقم البناء `N`.
4. ينشئ Release ويرفع الملفين `app-admin-release.apk` و`app-distributor-release.apk`.
5. إن وُجد السر `SUPABASE_SERVICE_ROLE_KEY` سجّل الإصدار في Supabase، فتظهر نافذة «يتوفر تحديث» في التطبيقات المثبتة. بدونه سجّله يدويًا من تطبيق الإدارة ← الإعدادات ← إصدارات التطبيق (الصق رابط الملف من صفحة Release).

## مرة واحدة: مفتاح التوقيع (مهم جدًا)
كل تشغيل على GitHub يبدأ بجهاز جديد، فلو لم نثبّت مفتاح التوقيع لخرج كل إصدار بتوقيع مختلف ويرفض الأندرويد تحديثه فوق السابق («تعارض مع حزمة موجودة»).

1. أنشئ المفتاح على جهازك (غيّر المسار إن كان Android Studio في مكان آخر؛ شغّل `flutter doctor -v` لترى مكان Java):
   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore alwaha-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias alwaha
   ```
   اختر كلمة مرور واحفظها، **واحتفظ بالملف `alwaha-release.jks` وكلمة المرور في مكان آمن خارج المشروع**. ضياعهما يعني عدم القدرة على تحديث التطبيق مرة أخرى.
2. حوّل الملف إلى نص وانسخه:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("alwaha-release.jks")) | Set-Clipboard
   ```
3. في GitHub: المستودع ← Settings ← Secrets and variables ← Actions ← New repository secret، وأنشئ:

   | الاسم | القيمة |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | النص الذي نسخته |
   | `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور الملف |
   | `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح (نفسها غالبًا) |
   | `ANDROID_KEY_ALIAS` | `alwaha` |
   | `SUPABASE_SERVICE_ROLE_KEY` | (اختياري) من Supabase ← Settings ← API Keys، لتسجيل الإصدار تلقائيًا |

   مفتاح `service_role` قوي جدًا: يوضع في GitHub Secrets فقط، ولا يوضع في الكود أو `env.json` أو التطبيق أبدًا.

## دورة العمل اليومية
1. عدّل الكود وارفعه إلى `main`.
2. انتظر اكتمال التشغيل في تبويب **Actions** (حوالي 10 دقائق).
3. حمّل الملفين من **Releases**. أول تثبيت يدوي؛ بعده تظهر نافذة التحديث تلقائيًا.

أول مرة بعد ضبط المفتاح: احذف النسخ القديمة من الهاتف ثم ثبّت الجديدة، لأن توقيعها مختلف عن التوقيع المؤقت السابق.

## اختبارات قاعدة البيانات
`database-tests.yml` يشغّل `supabase start` ثم `supabase test db` عند تغيير ملفات `supabase/`، لتعرف هل ملفات pgTAP تنجح فعلًا. لا يمنع هذا نشر التطبيق.

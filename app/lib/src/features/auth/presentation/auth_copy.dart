import '../domain/auth_gateway.dart';

/// Arabic copy for owner login and signup. Identifiers are not described as
/// verified or as proof of ownership.
abstract final class AuthCopy {
  static const signInTitle = 'تسجيل الدخول';
  static const signUpTitle = 'إنشاء حساب المالك';
  static const signInBody =
      'أدخل البريد الإلكتروني أو رقم الهاتف، ثم كلمة المرور.';
  static const signInAssurance = 'نجاح الدخول لا يثبت ملكية البريد أو الهاتف.';
  static const signUpBody =
      'عرّفنا بك وبمتجرك. نتعرف على البريد والهاتف من طريقة الكتابة.';
  static const ownerSection = 'المالك والنشاط';
  static const contactSection = 'البريد والهاتف';
  static const contactGuide = 'اكتب كل واحد في حقل، بأي ترتيب.';
  static const contactLabel = 'البريد أو رقم الهاتف';
  static const contactHint = 'name@mail.com\n01012345678';
  static const contactInvalid =
      'أدخل بريدًا إلكترونيًا أو رقم هاتف مصريًا صحيحًا';
  static const detectedEmail = 'تعرّفنا عليه كبريد إلكتروني';
  static const detectedPhone = 'تعرّفنا عليه كرقم هاتف';
  static const duplicateContact =
      'البريد والهاتف مطلوبان معًا، كل واحد في حقل.';
  static const credentialsSection = 'بيانات الدخول';
  static const backToSignIn = 'رجوع إلى تسجيل الدخول';
  static const showPassword = 'إظهار كلمة المرور';
  static const hidePassword = 'إخفاء كلمة المرور';
  static const passwordHelper = 'اختر كلمة مرور طويلة يسهل عليك تذكّرها.';
  static const emailHint = 'name@example.com';
  static const phoneHint = '01012345678';
  static const emailLabel = 'البريد الإلكتروني';
  static const phoneLabel = 'رقم الهاتف المصري';
  static const passwordLabel = 'كلمة المرور';
  static const ownerLabel = 'اسم المالك';
  static const businessLabel = 'اسم النشاط';
  static const governorateLabel = 'المحافظة';
  static const modeSignIn = 'دخول';
  static const modeSignUp = 'حساب جديد';
  static const signInAction = 'دخول';
  static const signInBusy = 'جارٍ تسجيل الدخول…';
  static const signUpAction = 'إنشاء الحساب';
  static const signUpBusy = 'جارٍ إرسال طلب التسجيل…';
  static const retryAction = 'إعادة المحاولة';
  static const emailInvalid = 'أدخل بريدًا إلكترونيًا صحيحًا';
  static const phoneInvalid = 'أدخل رقم هاتف مصري صحيحًا';
  static const ownerInvalid = 'أدخل اسم المالك من ١ إلى ١٢٠ حرفًا';
  static const businessInvalid = 'أدخل اسم النشاط من ١ إلى ١٢٠ حرفًا';
  static const governorateInvalid = 'اختر محافظة مصرية';
  static const governorateHint = 'اختر المحافظة';
  static const passwordInvalid = 'أدخل كلمة مرور صالحة من ٨ إلى ٧٢ بايتًا';
  static const signInFailed =
      'تعذر تسجيل الدخول. تحقق من البريد أو الهاتف وكلمة المرور ثم حاول مجددًا.';
  static const signInUnavailable = 'خدمة تسجيل الدخول غير متاحة الآن.';
  static const unavailable = 'خدمة تسجيل الدخول غير متاحة الآن.';
  static const governorateLoading = 'جارٍ تحميل المحافظات…';
  static const governorateFailed =
      'تعذر تحميل المحافظات. أعد المحاولة قبل إكمال التسجيل.';
  static const governorateRetry = 'إعادة تحميل المحافظات';
  static const signupUnknown =
      'لم نتأكد من حفظ الحساب. لا تعتبر الطلب مكتملًا. أعد المحاولة بنفس البيانات دون تغييرها.';
  static const signupInvalidInput =
      'تعذر قبول البيانات. راجع الحقول وحاول مجددًا.';
  static const signupIdentifierTaken =
      'هذا البريد أو الهاتف مرتبط بحساب موجود. سجّل الدخول بالحساب نفسه.';
  static const signupKeyReused =
      'هذا الطلب استُخدم ببيانات مختلفة. أعد المحاولة بنفس البيانات أو سجّل الدخول.';
  static const signupIdentityMismatch =
      'تعذر ربط الجلسة بالحساب بعد التسجيل. لم يُفتح المتجر.';
  static const signupUnavailable = 'خدمة التسجيل غير متاحة الآن. حاول مجددًا.';
  static const signupCredentials =
      'تعذر الدخول بكلمة المرور بعد التسجيل. أعد المحاولة بنفس البيانات.';

  static String registrationFailure(RegistrationFailure failure) {
    return switch (failure) {
      RegistrationFailure.invalidInput => signupInvalidInput,
      RegistrationFailure.identifierTaken => signupIdentifierTaken,
      RegistrationFailure.requestKeyReused => signupKeyReused,
      RegistrationFailure.registrationIdentityMismatch =>
        signupIdentityMismatch,
      RegistrationFailure.unavailable => signupUnavailable,
      RegistrationFailure.invalidCredentials => signupCredentials,
      RegistrationFailure.unknownOutcome => signupUnknown,
    };
  }
}

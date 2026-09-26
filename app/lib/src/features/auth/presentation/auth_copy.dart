import '../domain/auth_gateway.dart';

/// Arabic copy for owner login and signup. Identifiers are not described as
/// verified or as proof of ownership.
abstract final class AuthCopy {
  static const signInTitle = 'تسجيل الدخول';
  static const signUpTitle = 'إنشاء حساب المالك';
  static const signInBody =
      'ادخل بالبريد الإلكتروني أو رقم الهاتف المصري مع كلمة المرور. نجاح الدخول لا يثبت ملكية البريد أو الهاتف.';
  static const signUpBody =
      'التسجيل يطلب اسم المالك واسم النشاط والبريد ورقم الهاتف المصري والمحافظة وكلمة المرور. كلمة المرور لا تُحفظ في التطبيق، ولا يُعتبر الطلب محفوظًا قبل تأكيد الخادم.';
  static const emailLabel = 'البريد الإلكتروني';
  static const phoneLabel = 'رقم الهاتف المصري';
  static const passwordLabel = 'كلمة المرور';
  static const ownerLabel = 'اسم المالك';
  static const businessLabel = 'اسم النشاط';
  static const governorateLabel = 'المحافظة';
  static const emailKind = 'البريد الإلكتروني';
  static const phoneKind = 'الهاتف المصري';
  static const signInAction = 'دخول';
  static const signInBusy = 'جارٍ تسجيل الدخول…';
  static const signUpAction = 'إنشاء الحساب';
  static const signUpBusy = 'جارٍ إرسال طلب التسجيل…';
  static const retryAction = 'إعادة المحاولة';
  static const showSignUp = 'إنشاء حساب مالك';
  static const showSignIn = 'لديك حساب؟ تسجيل الدخول';
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

import '../domain/password_recovery.dart';

/// Arabic copy for email recovery. The mailbox is not described as verified.
abstract final class RecoveryCopy {
  static const forgotPassword = 'نسيت كلمة المرور؟';
  static const requestTitle = 'استعادة كلمة المرور';
  static const requestBody =
      'أدخل البريد الإلكتروني المرتبط بالحساب. لا نرسل رسالة إلى رقم الهاتف، ووصول الرسالة لا يثبت ملكية البريد.';
  static const requestAction = 'إرسال رابط الاستعادة';
  static const requestBusy = 'جارٍ إرسال رابط الاستعادة…';
  static const requestSuccess =
      'إذا كان هذا البريد مرتبطًا بحساب، فستصله رسالة فيها رابط لتعيين كلمة مرور جديدة. افتح الرابط على هذا الجهاز نفسه.';
  static const requestUnavailable =
      'تعذر إرسال رسالة الاستعادة الآن. حاول مجددًا بعد قليل.';
  static const emailInvalid = 'أدخل بريدًا إلكترونيًا صحيحًا';
  static const resetTitle = 'تعيين كلمة مرور جديدة';
  static const resetBody =
      'اختر كلمة مرور جديدة. لن يُفتح المتجر قبل حفظها وإنهاء رابط الاستعادة.';
  static const confirmLabel = 'تأكيد كلمة المرور';
  static const mismatch = 'كلمتا المرور غير متطابقتين';
  static const resetAction = 'حفظ كلمة المرور';
  static const resetBusy = 'جارٍ حفظ كلمة المرور…';
  static const resetSuccess =
      'تم تعيين كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.';
  static const resetExpired =
      'رابط الاستعادة غير صالح أو انتهت صلاحيته. اطلب رابطًا جديدًا.';
  static const resetMissing = 'لا توجد جلسة استعادة صالحة. اطلب رابطًا جديدًا.';
  static const resetRejected =
      'تعذر قبول كلمة المرور. اختر كلمة مرور من ٨ إلى ٧٢ بايتًا.';
  static const resetInterrupted =
      'لم يُغلق رابط الاستعادة بعد. المتجر ما زال مغلقًا. أعد المحاولة لإكمال الإغلاق.';
  static const resetUnavailable = 'تعذر حفظ كلمة المرور الآن. حاول مجددًا.';
  static const abandon = 'إلغاء والعودة لتسجيل الدخول';
  static const backToSignIn = 'رجوع إلى تسجيل الدخول';

  static String messageFor(RecoveryFailure failure) {
    return switch (failure) {
      RecoveryFailure.invalidEmail => emailInvalid,
      RecoveryFailure.unavailable => requestUnavailable,
      RecoveryFailure.expiredOrInvalidLink => resetExpired,
      RecoveryFailure.missingRecoverySession => resetMissing,
      RecoveryFailure.rejectedPassword => resetRejected,
      RecoveryFailure.resetInterrupted => resetInterrupted,
      RecoveryFailure.untrustedCallback => resetExpired,
    };
  }

  static String resetMessageFor(RecoveryFailure failure) {
    return switch (failure) {
      RecoveryFailure.unavailable => resetUnavailable,
      _ => messageFor(failure),
    };
  }
}

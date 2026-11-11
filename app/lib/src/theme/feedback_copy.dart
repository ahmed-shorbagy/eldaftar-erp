/// Shared Arabic copy for app-wide feedback (M1). Feature-specific wording
/// stays next to its feature; anything repeated across features lives here.
///
/// Rules: name the object and the result; a failure says what did not happen
/// and what to do next; no exclamation marks, English or technical terms.
abstract final class FeedbackCopy {
  static const retry = 'إعادة المحاولة';

  // Ledger outcomes that return to the ledger without their own outcome page.
  static const dayClosed = 'تم إقفال يوم العمل';
  static const cashTransferred = 'تم تحويل النقدية';
  static const scrapToStock = 'تمت إضافة الكسر إلى المخزون';

  // Device-only preferences: the choice still applies in this session.
  static const devicePreferenceFailed = 'تعذر الحفظ على هذا الجهاز';
  static const devicePreferenceBody = 'يسري اختيارك في هذه الجلسة فقط.';

  // Generic failures.
  static const unexpected = 'حدث خطأ غير متوقع. لم يُحفظ شيء.';
  static const notSavedRetry = 'تعذر حفظ التغيير. لم يُحفظ شيء.';
  static const unknownOutcome = 'لم يصل رد الخادم';
  static const unknownOutcomeBody =
      'لا تكرر العملية. أعد المحاولة بنفس الطلب للتحقق من حفظه.';
}

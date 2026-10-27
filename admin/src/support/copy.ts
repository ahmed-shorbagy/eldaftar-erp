import { formatServerInstant } from '../subscribers/subscriptionFormat.ts'
import type { SupportCategory, SupportInquiryAdminRow, SupportStatus } from './SupportGateway.ts'

export const supportCopy = {
  navLabel: 'الدعم الفني',
  title: 'صندوق دعم أصحاب المتاجر',
  intro:
    'استعرض استفسارات أصحاب المتاجر وصنّفها. تُظهر القائمة معرّف المتجر واسمه وتاريخ تسجيله فقط — بلا بيانات تواصل أو مالية.',
  statusFilter: 'تصفية الحالة',
  searchLabel: 'بحث بمعرّف المتجر (UUID كامل)',
  searchApply: 'بحث',
  searchHint: 'الصق معرّف المتجر الكامل؛ أي نص آخر لا يُرجع نتائج.',
  refresh: 'تحديث',
  retry: 'إعادة المحاولة',
  empty: 'لا توجد استفسارات مطابقة.',
  loadError: 'تعذر تحميل استفسارات الدعم. حاول مجددًا.',
  snapshot: 'آخر تحديث',
  loadMore: 'تحميل المزيد',
  loadingMore: 'جارٍ تحميل المزيد…',
  listFailed: 'تعذر تحميل الصفحة. حاول مجددًا.',
  shopLabel: 'المتجر',
  registered: 'تاريخ التسجيل',
  categoryLabel: 'التصنيف',
  bodyLabel: 'نص الاستفسار',
  replyLabel: 'رد الدعم',
  noReply: 'لم يُرسل رد بعد.',
  categoryNone: 'بدون تصنيف',
  startTriage: 'بدء المعالجة',
  answerTitle: 'الرد على الاستفسار',
  replyField: 'نص الرد (10–1000 حرف)',
  sendReply: 'إرسال الرد وإعلامه',
  closeInquiry: 'إغلاق الاستفسار',
  triageSaving: 'جارٍ الحفظ…',
  triageSaved: 'حُدّثت حالة الاستفسار.',
  triageReplayed: 'تأكدنا أن هذا التحديث محفوظ من قبل.',
  invalidReply: 'الرد مطلوب بين 10 و1000 حرف بعد إزالة المسافات الطرفية، ولا يقبل محارف تحكم.',
  invalidTransition: 'لا يمكن تنفيذ هذا الانتقال؛ حدّث الصندوق ثم أعد المحاولة.',
  notFound: 'لم يُعثر على الاستفسار؛ ربما حُذف أو مُرّر لآخر. حدّث الصندوق.',
  staleList: 'تغيّرت القائمة المُرصودة. حدّث الصندوق ثم أعد المحاولة.',
  triageError: 'تعذر تنفيذ التحديث. حاول مجددًا.',
  invalidSearch: 'أدخل معرّف متجر كاملًا ليصبح البحث مفعّلًا.',
  accessLost: 'انتهت صلاحية الوصول الإداري.',
  limitNote: 'لدى كل متجر حدّ عشرة استفسارات غير مغلقة.',
} as const

export const supportStatusLabel: Record<SupportStatus, string> = {
  new: 'جديدة',
  in_progress: 'قيد المعالجة',
  answered: 'تم الرد',
  closed: 'مغلقة',
}

export const supportFilterLabel: Record<SupportInquiryAdminRow['status'] | 'all', string> = {
  all: 'الكل',
  new: 'جديدة',
  in_progress: 'قيد المعالجة',
  answered: 'تم الرد',
  closed: 'مغلقة',
}

export const supportCategoryLabel: Record<SupportCategory, string> = {
  subscription: 'اتصال بالاشتراك',
  technical: 'مشكلة تقنية',
  financial_question: 'سؤال بعد النقد',
  other: 'أخرى',
}

/** Shop-local wall-clock rendering for an inquiry row, matching the owner's
 * view of the same instant. */
export function supportRowDate(isoUtc: string, timeZone: string): string {
  return formatServerInstant(isoUtc, timeZone)
}

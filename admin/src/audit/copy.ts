import { supportStatusLabel } from '../support/copy.ts'
import type { AuditAction, AuditDetails, AuditFamilyFilter } from './AuditGateway.ts'

/** Arabic copy for the platform-admin action history (ADR 0046). */
export const auditCopy = {
  navLabel: 'سجل الإدارة',
  title: 'سجل الإدارة',
  intro: 'كل ما نفّذه مسؤولو المنصة، الأحدث أولًا: رموز الاشتراك، وعرض بيانات التواصل، والدعم الفني، وتحديث التطبيق، والمساعدة، والإعلان. السجل للقراءة فقط ولا يمكن تعديله.',
  familyGroup: 'نوع العملية',
  actorLabel: 'المسؤول',
  actorAll: 'كل المسؤولين',
  snapshot: 'البيانات حتى',
  refresh: 'تحديث',
  loading: 'جارٍ تحميل السجل…',
  loadError: 'تعذّر تحميل السجل. حاول مرة أخرى.',
  retry: 'إعادة المحاولة',
  empty: 'لا توجد عمليات مطابقة.',
  loadMore: 'تحميل المزيد',
  loadingMore: 'جارٍ التحميل…',
  pageError: 'تعذّر تحميل الصفحة التالية.',
  staleReset: 'تغيّر السجل أثناء التصفح، فأُعيد تحميله من البداية.',
  unknownActor: 'غير معروف',
  shopLabel: 'المتجر',
  openShop: (name: string) => `فتح اشتراك ${name}`,
  listLabel: 'العمليات',
} as const

export const auditFamilyLabel: Record<AuditFamilyFilter, string> = {
  all: 'الكل',
  codes: 'رموز الاشتراك',
  contact: 'بيانات التواصل',
  support: 'الدعم الفني',
  app_version: 'تحديث التطبيق',
  help: 'المساعدة',
  announcement: 'الإعلان',
}

export const auditActionLabel: Record<AuditAction, string> = {
  subscription_code_issued: 'إصدار رمز اشتراك',
  subscriber_contact_revealed: 'عرض رقم الهاتف والموقع',
  support_status_changed: 'تغيير حالة استفسار',
  app_version_set: 'ضبط الحد الأدنى للإصدار',
  app_version_cleared: 'إلغاء إلزام التحديث',
  help_topic_created: 'إضافة موضوع مساعدة',
  help_topic_updated: 'تعديل موضوع مساعدة',
  help_topic_deleted: 'حذف موضوع مساعدة',
  help_article_created: 'إضافة مقال مساعدة',
  help_article_updated: 'تعديل مقال مساعدة',
  help_article_deleted: 'حذف مقال مساعدة',
  announcement_published: 'نشر إعلان المنصة',
  announcement_updated: 'تعديل إعلان المنصة',
  announcement_cleared: 'إلغاء إعلان المنصة',
}

const platformLabel: Record<string, string> = {
  android: 'أندرويد',
  ios: 'آيفون',
  windows: 'ويندوز',
}

function statusLabel(status: string | undefined): string {
  return status !== undefined && status in supportStatusLabel
    ? supportStatusLabel[status as keyof typeof supportStatusLabel]
    : '—'
}

/** One Arabic sentence built only from the safe summary fields. */
export function auditSummary(action: AuditAction, details: AuditDetails): string | null {
  switch (action) {
    case 'subscription_code_issued':
      return details.durationDays === undefined ? null : `مدة الاشتراك ${details.durationDays} يومًا`
    case 'subscriber_contact_revealed':
      return null
    case 'support_status_changed':
      return `من «${statusLabel(details.fromStatus)}» إلى «${statusLabel(details.toStatus)}»`
    case 'app_version_set': {
      const platform = platformLabel[details.platform ?? ''] ?? details.platform ?? ''
      const previous = details.previousMinVersion ? ` (كان ${details.previousMinVersion})` : ''
      return `${platform}: الحد الأدنى ${details.minVersion ?? ''}${previous}`
    }
    case 'app_version_cleared': {
      const platform = platformLabel[details.platform ?? ''] ?? details.platform ?? ''
      return details.previousMinVersion ? `${platform} (كان ${details.previousMinVersion})` : platform
    }
    case 'help_topic_created':
    case 'help_topic_updated':
    case 'help_topic_deleted':
    case 'help_article_created':
    case 'help_article_updated':
    case 'help_article_deleted': {
      if (details.titleAr === undefined) return null
      const state = details.published === undefined ? '' : details.published ? ' — منشور' : ' — غير منشور'
      return `«${details.titleAr}»${state}`
    }
    case 'announcement_published':
    case 'announcement_updated':
      return details.titleAr ? `«${details.titleAr}»` : null
    case 'announcement_cleared':
      return null
  }
}

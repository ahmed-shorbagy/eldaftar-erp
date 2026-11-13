import { expect, test } from 'vitest'
import { AuditError, parseAuditPage } from './AuditGateway.ts'
import { auditSummary } from './copy.ts'
import { mapAuditError } from './SupabaseAuditGateway.ts'

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    event_key: 'code:a7000000-0000-4000-8000-000000000001',
    occurred_at: '2026-11-10T10:00:00.000Z',
    family: 'codes',
    action: 'subscription_code_issued',
    actor_user_id: 'a7000000-0000-4000-8000-0000000000a1',
    actor_email: 'admin@example.test',
    shop_id: 'a7100000-0000-4000-8000-000000000001',
    shop_name: 'متجر',
    details: { duration_days: 30, code_expires_at: '2030-01-01T00:00:00Z', issued_via: 'platform_admin' },
    ...overrides,
  }
}

function page(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    snapshot_at: '2026-11-10T10:00:00.000Z',
    page_size: 25,
    rows: [row()],
    next_cursor: null,
    admins: [{ user_id: 'a7000000-0000-4000-8000-0000000000a1', email: 'admin@example.test' }],
    ...overrides,
  }
}

test('parses events, keeping only known safe summary fields', () => {
  const parsed = parseAuditPage(page({
    rows: [row({ details: { duration_days: 30, issued_via: 'platform_admin', body_ar: 'لا يُقرأ' } })],
  }))
  expect(parsed.rows[0]).toMatchObject({
    family: 'codes',
    action: 'subscription_code_issued',
    actorEmail: 'admin@example.test',
    shopName: 'متجر',
    details: { durationDays: 30, issuedVia: 'platform_admin' },
  })
  expect(JSON.stringify(parsed.rows[0].details)).not.toContain('لا يُقرأ')
  expect(parsed.admins).toEqual([{ userId: 'a7000000-0000-4000-8000-0000000000a1', email: 'admin@example.test' }])
})

test.each([
  ['an unknown action', page({ rows: [row({ action: 'shop_deleted' })] })],
  ['a family that does not match the action', page({ rows: [row({ family: 'help' })] })],
  ['an extra row key', page({ rows: [row({ phone: '+20100' })] })],
  ['an extra page key', page({ total: '1' })],
  ['a malformed event key', page({ rows: [row({ event_key: 'shop:1' })] })],
  ['more rows than the page size', page({ page_size: 0 })],
  ['a malformed cursor', page({ next_cursor: 'abc' })],
  ['a bad timestamp', page({ rows: [row({ occurred_at: 'soon' })] })],
])('rejects %s', (_label, payload) => {
  expect(() => parseAuditPage(payload)).toThrow(AuditError)
})

test('summaries are Arabic sentences built from safe fields', () => {
  expect(auditSummary('subscription_code_issued', { durationDays: 90 })).toBe('مدة الاشتراك 90 يومًا')
  expect(auditSummary('support_status_changed', { fromStatus: 'new', toStatus: 'in_progress' }))
    .toBe('من «جديدة» إلى «قيد المعالجة»')
  expect(auditSummary('app_version_set', { platform: 'android', minVersion: '2.0.0', previousMinVersion: '1.2.0' }))
    .toBe('أندرويد: الحد الأدنى 2.0.0 (كان 1.2.0)')
  expect(auditSummary('app_version_cleared', { platform: 'ios', previousMinVersion: null })).toBe('آيفون')
  expect(auditSummary('help_article_created', { titleAr: 'كيف أجدد؟', published: false }))
    .toBe('«كيف أجدد؟» — غير منشور')
  expect(auditSummary('subscriber_contact_revealed', {})).toBeNull()
})

test('maps refusals to access loss and a rejected cursor to a stale list', () => {
  expect(mapAuditError('forbidden').code).toBe('unauthorized')
  expect(mapAuditError('session_expired').code).toBe('unauthorized')
  expect(mapAuditError('invalid_cursor').code).toBe('stale')
  expect(mapAuditError('timeout').code).toBe('unavailable')
})

test('code revocations parse into the codes family with their reason', () => {
  const parsed = parseAuditPage(page({
    rows: [row({ action: 'subscription_code_revoked', details: { duration_days: 90, reason: 'رقم خطأ' } })],
  }))
  const event = parsed.rows[0]
  expect(event?.family).toBe('codes')
  expect(event?.details.reason).toBe('رقم خطأ')
  expect(event && auditSummary(event.action, event.details)).toBe('السبب: رقم خطأ')
  expect(() => parseAuditPage(page({ rows: [row({ family: 'help', action: 'subscription_code_revoked' })] })))
    .toThrow(AuditError)
})

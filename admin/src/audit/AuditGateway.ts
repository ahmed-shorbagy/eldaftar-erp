/** Platform-admin action history contract (ADR 0046). */

export type AuditFamily =
  | 'codes'
  | 'contact'
  | 'support'
  | 'app_version'
  | 'help'
  | 'announcement'
  | 'broadcast'
export type AuditFamilyFilter = 'all' | AuditFamily

export type AuditAction =
  | 'subscription_code_issued'
  | 'subscription_code_revoked'
  | 'subscriber_contact_revealed'
  | 'support_status_changed'
  | 'app_version_set'
  | 'app_version_cleared'
  | 'help_topic_created'
  | 'help_topic_updated'
  | 'help_topic_deleted'
  | 'help_article_created'
  | 'help_article_updated'
  | 'help_article_deleted'
  | 'announcement_published'
  | 'announcement_updated'
  | 'announcement_cleared'
  | 'broadcast_sent'
  | 'broadcast_withdrawn'

/** Safe summary fields; every field is optional and validated by type. */
export interface AuditDetails {
  durationDays?: number
  issuedVia?: string
  fromStatus?: string
  toStatus?: string
  platform?: string
  minVersion?: string | null
  previousMinVersion?: string | null
  titleAr?: string
  published?: boolean
  reason?: string
  recipientCount?: number
}

export interface AuditEvent {
  eventKey: string
  occurredAt: string
  family: AuditFamily
  action: AuditAction
  actorUserId: string | null
  actorEmail: string | null
  shopId: string | null
  shopName: string | null
  details: AuditDetails
}

export interface AuditPage {
  snapshotAt: string
  pageSize: number
  rows: AuditEvent[]
  nextCursor: string | null
  admins: Array<{ userId: string; email: string }>
}

export interface AuditQuery {
  family: AuditFamilyFilter
  actorUserId: string | null
  cursor: string | null
}

export interface AuditGateway {
  list(query: AuditQuery): Promise<AuditPage>
}

export type AuditErrorCode = 'unauthorized' | 'stale' | 'invalid' | 'unavailable'

export class AuditError extends Error {
  readonly code: AuditErrorCode

  constructor(code: AuditErrorCode) {
    super(code)
    this.name = 'AuditError'
    this.code = code
  }
}

export const auditFamilies: readonly AuditFamily[] = [
  'codes', 'contact', 'support', 'app_version', 'help', 'announcement', 'broadcast',
]

const actionFamily: Record<AuditAction, AuditFamily> = {
  subscription_code_issued: 'codes',
  subscription_code_revoked: 'codes',
  subscriber_contact_revealed: 'contact',
  support_status_changed: 'support',
  app_version_set: 'app_version',
  app_version_cleared: 'app_version',
  help_topic_created: 'help',
  help_topic_updated: 'help',
  help_topic_deleted: 'help',
  help_article_created: 'help',
  help_article_updated: 'help',
  help_article_deleted: 'help',
  announcement_published: 'announcement',
  announcement_updated: 'announcement',
  announcement_cleared: 'announcement',
  broadcast_sent: 'broadcast',
  broadcast_withdrawn: 'broadcast',
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const eventKeyPattern = /^(code|contact|support|platform):[0-9a-f-]{1,36}$/

function invalid(): never {
  throw new AuditError('invalid')
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) invalid()
  const actual = Object.keys(value).sort()
  const expected = [...keys].sort()
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) invalid()
  return value as Record<string, unknown>
}

function instant(value: unknown): string {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) invalid()
  return value
}

function nullableUuid(value: unknown): string | null {
  if (value === null) return null
  if (typeof value !== 'string' || !uuidPattern.test(value)) invalid()
  return value
}

function nullableText(value: unknown): string | null {
  if (value === null) return null
  if (typeof value !== 'string') invalid()
  return value
}

function parseDetails(value: unknown): AuditDetails {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) invalid()
  const raw = value as Record<string, unknown>
  const details: AuditDetails = {}
  if (typeof raw.duration_days === 'number' && Number.isInteger(raw.duration_days)) details.durationDays = raw.duration_days
  if (typeof raw.issued_via === 'string') details.issuedVia = raw.issued_via
  if (typeof raw.from_status === 'string') details.fromStatus = raw.from_status
  if (typeof raw.to_status === 'string') details.toStatus = raw.to_status
  if (typeof raw.platform === 'string') details.platform = raw.platform
  if (typeof raw.min_version === 'string' || raw.min_version === null) details.minVersion = raw.min_version as string | null
  if (typeof raw.previous_min_version === 'string' || raw.previous_min_version === null) {
    details.previousMinVersion = raw.previous_min_version as string | null
  }
  if (typeof raw.title_ar === 'string') details.titleAr = raw.title_ar
  if (typeof raw.published === 'boolean') details.published = raw.published
  if (typeof raw.reason === 'string') details.reason = raw.reason
  if (typeof raw.recipient_count === 'number' && Number.isInteger(raw.recipient_count)) {
    details.recipientCount = raw.recipient_count
  }
  return details
}

function parseEvent(value: unknown): AuditEvent {
  const row = exactRecord(value, [
    'event_key', 'occurred_at', 'family', 'action', 'actor_user_id',
    'actor_email', 'shop_id', 'shop_name', 'details',
  ])
  if (typeof row.event_key !== 'string' || !eventKeyPattern.test(row.event_key)) invalid()
  if (typeof row.action !== 'string' || !(row.action in actionFamily)) invalid()
  const action = row.action as AuditAction
  if (row.family !== actionFamily[action]) invalid()
  return {
    eventKey: row.event_key,
    occurredAt: instant(row.occurred_at),
    family: actionFamily[action],
    action,
    actorUserId: nullableUuid(row.actor_user_id),
    actorEmail: nullableText(row.actor_email),
    shopId: nullableUuid(row.shop_id),
    shopName: nullableText(row.shop_name),
    details: parseDetails(row.details),
  }
}

/** Strict page parser: unknown keys, families or actions are rejected. */
export function parseAuditPage(input: unknown): AuditPage {
  const page = exactRecord(input, ['snapshot_at', 'page_size', 'rows', 'next_cursor', 'admins'])
  if (typeof page.page_size !== 'number' || !Number.isInteger(page.page_size)) invalid()
  if (!Array.isArray(page.rows) || page.rows.length > page.page_size) invalid()
  if (page.next_cursor !== null && (typeof page.next_cursor !== 'string' || !page.next_cursor.startsWith('v1|'))) invalid()
  if (!Array.isArray(page.admins)) invalid()
  return {
    snapshotAt: instant(page.snapshot_at),
    pageSize: page.page_size,
    rows: page.rows.map(parseEvent),
    nextCursor: page.next_cursor as string | null,
    admins: page.admins.map((entry) => {
      const admin = exactRecord(entry, ['user_id', 'email'])
      const userId = nullableUuid(admin.user_id)
      if (userId === null || typeof admin.email !== 'string') invalid()
      return { userId, email: admin.email }
    }),
  }
}

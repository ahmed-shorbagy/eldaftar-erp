export const supportStatuses = ['new', 'in_progress', 'answered', 'closed'] as const
export type SupportStatus = (typeof supportStatuses)[number]

export type SupportStatusFilter = SupportStatus | 'all'

export const supportCategories = ['subscription', 'technical', 'financial_question', 'other'] as const
export type SupportCategory = (typeof supportCategories)[number]

export type SupportTriageTarget = 'in_progress' | 'answered' | 'closed'

/** One admin mailbox row: shop id/name and registration-date context only —
 * no owner identity, contact, location, financial or CRM fields (ADR 0036). */
export type SupportInquiryAdminRow = {
  id: string
  shopId: string
  shopName: string
  category: SupportCategory | null
  bodyAr: string
  status: SupportStatus
  replyAr: string | null
  createdAt: string
  updatedAt: string
  answeredAt: string | null
  closedAt: string | null
  shopCreatedAt: string
  shopTimeZone: string
}

export type SupportInquiryPage = {
  inquiries: SupportInquiryAdminRow[]
  nextCursorAt: string | null
  nextCursorId: string | null
  snapshotAt: string
}

export type SupportUpdateResult = {
  inquiryId: string
  status: SupportStatus
  replyAr: string | null
  saved: boolean
}

export type SupportListInput = {
  status: SupportStatusFilter
  search: string
  cursorAt: string | null
  cursorId: string | null
}

export type SupportUpdateInput = {
  inquiryId: string
  to: SupportTriageTarget
  replyAr: string | null
  idempotencyKey: string
}

export type SupportGateway = {
  list(input: SupportListInput): Promise<SupportInquiryPage>
  updateInquiryStatus(input: SupportUpdateInput): Promise<SupportUpdateResult>
}

export const supportPageSize = 20
export const supportMaxPageSize = 50

export class SupportError extends Error {
  readonly code:
    | 'access_lost'
    | 'invalid'
    | 'stale_cursor'
    | 'invalid_transition'
    | 'not_found'
    | 'unavailable'

  constructor(
    code: 'access_lost'
      | 'invalid'
      | 'stale_cursor'
      | 'invalid_transition'
      | 'not_found'
      | 'unavailable',
  ) {
    super(code)
    this.code = code
  }
}

const pageKeys = ['inquiries', 'next_cursor_at', 'next_cursor_id', 'snapshot_at'] as const

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function parseSupportPage(value: unknown): SupportInquiryPage {
  const record = objectWithKeys(value, pageKeys)
  if (!Array.isArray(record.inquiries) || typeof record.snapshot_at !== 'string') {
    throw new SupportError('unavailable')
  }
  const hasCursor = record.next_cursor_at !== null
  if (hasCursor !== (record.next_cursor_id !== null)) {
    throw new SupportError('unavailable')
  }
  const rows = record.inquiries.map((row) => {
    const admin = parseRowCore(row)
    if (typeof admin.shopName !== 'string' || admin.shopName.trim() === '') {
      throw new SupportError('unavailable')
    }
    const extra = requireRecord(row)
    return {
      ...admin,
      shopName: admin.shopName,
      shopCreatedAt: requireInstant(extra.shop_created_at),
      shopTimeZone: requireTimeZone(extra.shop_time_zone),
    }
  })
  return {
    inquiries: rows,
    nextCursorAt: record.next_cursor_at === null ? null : requireInstant(record.next_cursor_at),
    nextCursorId: record.next_cursor_id === null ? null : requireUuid(record.next_cursor_id),
    snapshotAt: requireInstant(record.snapshot_at),
  }
}

export function parseSupportUpdate(value: unknown): SupportUpdateResult {
  const record = requireRecord(value)
  if (record.result_status !== 'saved' && record.result_status !== 'replayed') {
    throw new SupportError('unavailable')
  }
  const core = parseRowCore(record)
  return {
    inquiryId: core.id,
    status: core.status,
    replyAr: core.replyAr,
    saved: record.result_status === 'saved',
  }
}

function parseRowCore(input: unknown) {
  const record = requireRecord(input)
  if (
    typeof record.body_ar !== 'string'
    || record.body_ar.trim() === ''
    || !supportStatuses.includes(record.status as SupportStatus)
    || typeof record.id !== 'string'
    || !uuidPattern.test(record.id)
    || typeof record.shop_id !== 'string'
    || !uuidPattern.test(record.shop_id)
    || (record.shop_name !== null && typeof record.shop_name !== 'string')
    || (record.reply_ar !== null && typeof record.reply_ar !== 'string')
  ) {
    throw new SupportError('unavailable')
  }
  let category: SupportCategory | null = null
  if (record.category !== null) {
    if (
      typeof record.category !== 'string'
      || !supportCategories.includes(record.category as SupportCategory)
    ) {
      throw new SupportError('unavailable')
    }
    category = record.category as SupportCategory
  }
  return {
    id: record.id,
    shopId: record.shop_id,
    shopName: record.shop_name as string | null,
    category,
    bodyAr: record.body_ar,
    status: record.status as SupportStatus,
    replyAr: record.reply_ar as string | null,
    createdAt: requireInstant(record.created_at),
    updatedAt: requireInstant(record.updated_at),
    answeredAt: record.answered_at === null ? null : requireInstant(record.answered_at),
    closedAt: record.closed_at === null ? null : requireInstant(record.closed_at),
  }
}

function requireRecord(input: unknown): Record<string, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new SupportError('unavailable')
  }
  return input as Record<string, unknown>
}

function objectWithKeys<Key extends string>(
  input: unknown,
  keys: readonly Key[],
): Record<Key, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new SupportError('unavailable')
  }
  const record = input as Record<string, unknown>
  const actual = Object.keys(record)
  if (actual.length !== keys.length || keys.some((key) => !Object.hasOwn(record, key))) {
    throw new SupportError('unavailable')
  }
  return record as Record<Key, unknown>
}

function requireUuid(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value)) {
    throw new SupportError('unavailable')
  }
  return value
}

function requireInstant(value: unknown): string {
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) {
    throw new SupportError('unavailable')
  }
  return value
}

function requireTimeZone(value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new SupportError('unavailable')
  }
  return value
}

export function isExactShopIdentifier(value: string): boolean {
  return uuidPattern.test(value.trim())
}

/** Mirrors the server reply rule (ADR 0036): newline is the only accepted
 * control character, trimming removes ASCII spaces, length 10–1000. */
export function normalizeSupportReply(draft: string): string | null {
  for (const ch of draft) {
    const code = ch.codePointAt(0) ?? 0
    const isControl =
      (code < 0x20 && code !== 0x0a) || code === 0x7f || (code >= 0x80 && code <= 0x9f)
    if (isControl) return null
  }
  const trimmed = draft.replace(/^ +/u, '').replace(/ +$/u, '')
  const length = Array.from(trimmed).length
  if (length < 10 || length > 1000) return null
  return trimmed
}

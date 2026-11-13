/** Subscriber broadcast contract (ADR 0048, ADM-06). */

export type BroadcastSegment = 'all' | 'active' | 'pending' | 'expired' | 'expiring' | 'shop'
export type BroadcastState = 'scheduled' | 'active' | 'ended' | 'withdrawn'

export const broadcastSegments: readonly BroadcastSegment[] = [
  'all', 'active', 'pending', 'expired', 'expiring', 'shop',
]

export const titleMax = 80
export const bodyMax = 1000
export const reasonMin = 3
export const reasonMax = 200
export const expiringDaysMin = 1
export const expiringDaysMax = 90
export const scheduleMaxDays = 90
export const windowMaxDays = 365
export const defaultWindowDays = 30
export const broadcastPageSize = 20

export interface AudienceInput {
  segment: BroadcastSegment
  days: number | null
  shopId: string | null
}

export interface BroadcastDraft extends AudienceInput {
  titleAr: string
  bodyAr: string
  linkUrl: string | null
  /** ISO instant, or null for "send now". */
  startsAt: string | null
  /** ISO instant, or null for the 30-day default. */
  endsAt: string | null
}

export interface SendInput extends BroadcastDraft {
  requestKey: string
  expectedCount: number
}

export interface AudiencePreview {
  snapshotAt: string
  recipientCount: string
}

export interface SendResult {
  status: 'sent' | 'replayed'
  broadcastId: string
  recipientCount: string
  startsAt: string
  endsAt: string
}

export interface WithdrawResult {
  status: 'withdrawn' | 'already_withdrawn'
  broadcastId: string
  withdrawnAt: string
}

export interface BroadcastRow {
  id: string
  createdAt: string
  createdByEmail: string | null
  segment: BroadcastSegment
  segmentDays: number | null
  segmentShopId: string | null
  segmentShopName: string | null
  titleAr: string
  bodyAr: string
  linkUrl: string | null
  startsAt: string
  endsAt: string
  state: BroadcastState
  recipientCount: string
  deliveredCount: string
  readCount: string
  withdrawnAt: string | null
  withdrawReason: string | null
}

export interface BroadcastPage {
  snapshotAt: string
  pageSize: number
  rows: BroadcastRow[]
  nextCursor: string | null
}

export interface BroadcastGateway {
  preview(input: AudienceInput): Promise<AudiencePreview>
  send(input: SendInput): Promise<SendResult>
  withdraw(broadcastId: string, reason: string): Promise<WithdrawResult>
  list(cursor: string | null): Promise<BroadcastPage>
}

export type BroadcastErrorCode =
  | 'unauthorized'
  | 'invalid'
  | 'not_found'
  | 'audience_changed'
  | 'empty_audience'
  | 'request_conflict'
  | 'stale'
  | 'timeout'
  | 'unavailable'

export class BroadcastError extends Error {
  readonly code: BroadcastErrorCode

  constructor(code: BroadcastErrorCode) {
    super(code)
    this.name = 'BroadcastError'
    this.code = code
  }
}

export function mapBroadcastError(message: string | undefined): BroadcastError {
  const text = (message ?? '').toLowerCase()
  if (/(forbidden|unauthenticated|unauthorized|session_expired|permission denied|42501)/.test(text)) {
    return new BroadcastError('unauthorized')
  }
  if (text.includes('audience_changed')) return new BroadcastError('audience_changed')
  if (text.includes('empty_audience')) return new BroadcastError('empty_audience')
  if (text.includes('request_key_reused')) return new BroadcastError('request_conflict')
  if (text.includes('stale_cursor') || text.includes('invalid_cursor')) return new BroadcastError('stale')
  if (/\bnot_found\b/.test(text)) return new BroadcastError('not_found')
  if (text.includes('invalid_input') || text.includes('invalid_page_size')) return new BroadcastError('invalid')
  return new BroadcastError('unavailable')
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const countPattern = /^(0|[1-9][0-9]*)$/
const states: readonly BroadcastState[] = ['scheduled', 'active', 'ended', 'withdrawn']

function invalid(): never {
  throw new BroadcastError('unavailable')
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) invalid()
  const actual = Object.keys(value).sort()
  const expected = [...keys].sort()
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) invalid()
  return value as Record<string, unknown>
}

function uuid(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value)) invalid()
  return value.toLowerCase()
}

function nullableUuid(value: unknown): string | null {
  return value === null ? null : uuid(value)
}

function instant(value: unknown): string {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) invalid()
  return value
}

function nullableInstant(value: unknown): string | null {
  return value === null ? null : instant(value)
}

function count(value: unknown): string {
  if (typeof value !== 'string' || !countPattern.test(value)) invalid()
  return value
}

function text(value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') invalid()
  return value
}

function nullableText(value: unknown): string | null {
  return value === null ? null : text(value)
}

export function parsePreview(input: unknown): AudiencePreview {
  const record = exactRecord(input, ['snapshot_at', 'recipient_count'])
  return { snapshotAt: instant(record.snapshot_at), recipientCount: count(record.recipient_count) }
}

export function parseSendResult(input: unknown): SendResult {
  const record = exactRecord(input, ['status', 'broadcast_id', 'recipient_count', 'starts_at', 'ends_at'])
  if (record.status !== 'sent' && record.status !== 'replayed') invalid()
  const startsAt = instant(record.starts_at)
  const endsAt = instant(record.ends_at)
  if (Date.parse(endsAt) <= Date.parse(startsAt)) invalid()
  const recipientCount = count(record.recipient_count)
  if (recipientCount === '0') invalid()
  return {
    status: record.status,
    broadcastId: uuid(record.broadcast_id),
    recipientCount,
    startsAt,
    endsAt,
  }
}

export function parseWithdrawResult(input: unknown, expectedId: string): WithdrawResult {
  const record = exactRecord(input, ['status', 'broadcast_id', 'withdrawn_at'])
  if (record.status !== 'withdrawn' && record.status !== 'already_withdrawn') invalid()
  const broadcastId = uuid(record.broadcast_id)
  if (broadcastId !== expectedId.toLowerCase()) invalid()
  return { status: record.status, broadcastId, withdrawnAt: instant(record.withdrawn_at) }
}

const rowKeys = [
  'id', 'created_at', 'created_by_email', 'segment', 'segment_days', 'segment_shop_id',
  'segment_shop_name', 'title_ar', 'body_ar', 'link_url', 'starts_at', 'ends_at', 'state',
  'recipient_count', 'delivered_count', 'read_count', 'withdrawn_at', 'withdraw_reason',
] as const

function parseRow(input: unknown): BroadcastRow {
  const record = exactRecord(input, rowKeys)
  if (!broadcastSegments.includes(record.segment as BroadcastSegment)) invalid()
  if (!states.includes(record.state as BroadcastState)) invalid()
  const segment = record.segment as BroadcastSegment
  const segmentDays = record.segment_days
  if (segment === 'expiring') {
    if (typeof segmentDays !== 'number' || !Number.isInteger(segmentDays)) invalid()
  } else if (segmentDays !== null) {
    invalid()
  }
  const segmentShopId = nullableUuid(record.segment_shop_id)
  if ((segment === 'shop') !== (segmentShopId !== null)) invalid()
  const withdrawnAt = nullableInstant(record.withdrawn_at)
  const withdrawReason = nullableText(record.withdraw_reason)
  const state = record.state as BroadcastState
  if ((withdrawnAt !== null) !== (withdrawReason !== null)) invalid()
  if ((state === 'withdrawn') !== (withdrawnAt !== null)) invalid()
  const recipientCount = count(record.recipient_count)
  const deliveredCount = count(record.delivered_count)
  const readCount = count(record.read_count)
  if (BigInt(readCount) > BigInt(deliveredCount) || BigInt(deliveredCount) > BigInt(recipientCount)) invalid()
  if (record.created_by_email !== null && typeof record.created_by_email !== 'string') invalid()
  if (record.segment_shop_name !== null && typeof record.segment_shop_name !== 'string') invalid()
  return {
    id: uuid(record.id),
    createdAt: instant(record.created_at),
    createdByEmail: record.created_by_email as string | null,
    segment,
    segmentDays: segmentDays as number | null,
    segmentShopId,
    segmentShopName: record.segment_shop_name as string | null,
    titleAr: text(record.title_ar),
    bodyAr: text(record.body_ar),
    linkUrl: nullableText(record.link_url),
    startsAt: instant(record.starts_at),
    endsAt: instant(record.ends_at),
    state,
    recipientCount,
    deliveredCount,
    readCount,
    withdrawnAt,
    withdrawReason,
  }
}

export function parseBroadcastPage(input: unknown, expectedPageSize: number): BroadcastPage {
  const record = exactRecord(input, ['snapshot_at', 'page_size', 'rows', 'next_cursor'])
  if (record.page_size !== expectedPageSize) invalid()
  if (!Array.isArray(record.rows) || record.rows.length > expectedPageSize) invalid()
  const rows = record.rows.map(parseRow)
  if (new Set(rows.map((row) => row.id)).size !== rows.length) invalid()
  const nextCursor = record.next_cursor
  if (nextCursor !== null && (typeof nextCursor !== 'string' || !nextCursor.startsWith('v1|') || nextCursor.length !== 66)) {
    invalid()
  }
  return { snapshotAt: instant(record.snapshot_at), pageSize: expectedPageSize, rows, nextCursor }
}

/** Client-side validation that mirrors the server rules; returns field errors. */
export interface DraftErrors {
  title?: true
  body?: true
  link?: true
  days?: true
  shopId?: true
  startsAt?: true
  endsAt?: true
}

// eslint-disable-next-line no-control-regex
const controlPattern = /[\u0000-\u001f\u007f]/
// eslint-disable-next-line no-control-regex
const bodyControlPattern = /[\u0000-\u0009\u000b-\u001f\u007f]/

export function validateDraft(draft: BroadcastDraft, now: Date = new Date()): DraftErrors {
  const errors: DraftErrors = {}
  const title = draft.titleAr.trim()
  if (title.length < 1 || title.length > titleMax || controlPattern.test(title)) errors.title = true
  const body = draft.bodyAr.replace(/\r\n/g, '\n').trim()
  if (body.length < 1 || body.length > bodyMax || bodyControlPattern.test(body)) errors.body = true
  if (draft.linkUrl !== null) {
    const link = draft.linkUrl.trim()
    if (link.length < 12 || link.length > 2048 || !/^https:\/\//i.test(link) || /\s/.test(link)) errors.link = true
  }
  if (draft.segment === 'expiring') {
    if (draft.days === null || !Number.isInteger(draft.days) || draft.days < expiringDaysMin || draft.days > expiringDaysMax) {
      errors.days = true
    }
  }
  if (draft.segment === 'shop' && (draft.shopId === null || !uuidPattern.test(draft.shopId))) errors.shopId = true
  const day = 24 * 60 * 60 * 1000
  const start = draft.startsAt === null ? now.getTime() : Date.parse(draft.startsAt)
  if (Number.isNaN(start) || start > now.getTime() + scheduleMaxDays * day) errors.startsAt = true
  if (draft.endsAt !== null) {
    const end = Date.parse(draft.endsAt)
    const effectiveStart = Math.max(start, now.getTime())
    if (Number.isNaN(end) || end <= effectiveStart || end > effectiveStart + windowMaxDays * day) errors.endsAt = true
  }
  return errors
}

export function normalizeDraft(draft: BroadcastDraft): BroadcastDraft {
  const link = draft.linkUrl?.trim() ?? ''
  return {
    ...draft,
    titleAr: draft.titleAr.trim(),
    bodyAr: draft.bodyAr.replace(/\r\n/g, '\n').trim(),
    linkUrl: link === '' ? null : link,
    days: draft.segment === 'expiring' ? draft.days : null,
    shopId: draft.segment === 'shop' ? draft.shopId?.trim().toLowerCase() ?? null : null,
  }
}

import { SubscriptionCodeError, subscriptionCodePageSize } from './SubscriberDirectoryGateway.ts'
import { formatServerInstant } from './subscriptionFormat.ts'

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const uuidV4Pattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const hexCodePattern = /^[A-F0-9]{32}$/
const integerPattern = /^(0|[1-9][0-9]*)$/
const historyCursorPattern =
  /^v1\|\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

export const durationDaysMin = 1
export const durationDaysMax = 3660
export const codeTtlDaysMin = 1
export const codeTtlDaysMax = 365
export const defaultCodeTtlDays = 30

export type SubscriptionCodeStatus = 'unused' | 'expired' | 'redeemed'
export type IssuedVia = 'platform_admin' | 'service_role'
export type IssueStatus = 'issued' | 'replayed'

export interface IssuedSubscriptionCode {
  status: IssueStatus
  code: string | null
  shopId: string
  durationDays: number
  codeExpiresAt: string
  requestKey: string
  issuedVia: IssuedVia
}

export interface IssueParseExpected {
  shopId: string
  requestKey: string
  durationDays: number
}

export interface HistoryParseExpected {
  shopId: string
  pageSize: number
  cursor: string | null
}

export interface SubscriptionCodeRow {
  id: string
  issuedAt: string
  durationDays: number
  codeTtlDays: number
  codeExpiresAt: string
  issuedVia: IssuedVia
  codeStatus: SubscriptionCodeStatus
  redeemedAt: string | null
}

export interface SubscriptionCodePage {
  snapshotAt: string
  shopId: string
  shopName: string
  rowCount: string
  pageSize: number
  rows: SubscriptionCodeRow[]
  nextCursor: string | null
}

const issueKeys = [
  'code',
  'shop_id',
  'owner_user_id',
  'duration_days',
  'code_expires_at',
  'status',
  'request_key',
  'issued_via',
] as const

const historyKeys = [
  'snapshot_at',
  'shop_id',
  'shop_name',
  'row_count',
  'page_size',
  'rows',
  'next_cursor',
] as const

const historyRowKeys = [
  'id',
  'issued_at',
  'duration_days',
  'code_ttl_days',
  'code_expires_at',
  'issued_via',
  'code_status',
  'redeemed_at',
] as const

const codeStatuses: SubscriptionCodeStatus[] = ['unused', 'expired', 'redeemed']
const issuedViaValues: IssuedVia[] = ['platform_admin', 'service_role']

export function parseIntegerDays(value: string, min: number, max: number): number {
  const trimmed = value.trim()
  if (!integerPattern.test(trimmed)) {
    throw new SubscriptionCodeError('invalid_range')
  }
  const parsed = Number(trimmed)
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new SubscriptionCodeError('invalid_range')
  }
  return parsed
}

export function createIssueRequestKey(): string {
  const key = crypto.randomUUID().toLowerCase()
  if (!uuidV4Pattern.test(key)) {
    throw new SubscriptionCodeError('unavailable')
  }
  return key
}

export function estimateCodeExpiry(ttlDays: number, from = new Date()): Date {
  return new Date(from.getTime() + ttlDays * 24 * 60 * 60 * 1000)
}

export function formatEstimatedExpiry(ttlDays: number, from = new Date()): string {
  return formatServerInstant(estimateCodeExpiry(ttlDays, from).toISOString())
}

export function isCanonicalHistoryCursor(value: string): boolean {
  return value.length === 66 && historyCursorPattern.test(value)
}

export function parseIssuedSubscriptionCode(
  input: unknown,
  expected: IssueParseExpected,
): IssuedSubscriptionCode {
  const record = objectWithKeys(singleRow(input), issueKeys)
  if (
    record.status !== 'issued' && record.status !== 'replayed'
    || (record.issued_via !== 'platform_admin' && record.issued_via !== 'service_role')
    || typeof record.duration_days !== 'number'
    || !Number.isInteger(record.duration_days)
    || record.duration_days < durationDaysMin
    || record.duration_days > durationDaysMax
  ) {
    throw new SubscriptionCodeError('invalid_response')
  }
  requireUuid(record.owner_user_id)
  const shopId = requireUuid(record.shop_id)
  const requestKey = requireUuidV4(record.request_key)
  if (
    shopId !== expected.shopId
    || requestKey !== expected.requestKey.toLowerCase()
    || record.duration_days !== expected.durationDays
  ) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const code = record.code
  if (record.status === 'issued') {
    if (typeof code !== 'string' || !hexCodePattern.test(code)) {
      throw new SubscriptionCodeError('invalid_response')
    }
  } else if (code !== null) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return {
    status: record.status,
    code,
    shopId,
    durationDays: record.duration_days,
    codeExpiresAt: requireInstant(record.code_expires_at),
    requestKey,
    issuedVia: record.issued_via,
  }
}

export function parseSubscriptionCodePage(
  input: unknown,
  expected: HistoryParseExpected,
): SubscriptionCodePage {
  if (expected.cursor !== null && !isCanonicalHistoryCursor(expected.cursor)) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const record = objectWithKeys(input, historyKeys)
  const rows = Array.isArray(record.rows) ? record.rows.map(parseHistoryRow) : null
  const pageSize = record.page_size
  if (
    rows === null
    || typeof pageSize !== 'number'
    || !Number.isInteger(pageSize)
    || pageSize < 1
    || pageSize > 25
    || pageSize !== expected.pageSize
    || rows.length > pageSize
    || (record.next_cursor !== null && typeof record.next_cursor !== 'string')
    || typeof record.shop_name !== 'string'
    || record.shop_name.trim() === ''
    || typeof record.row_count !== 'string'
    || !integerPattern.test(record.row_count)
  ) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const shopId = requireUuid(record.shop_id)
  if (shopId !== expected.shopId) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const ids = new Set(rows.map((row) => row.id))
  if (ids.size !== rows.length) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const instants: ExactInstant[] = []
  for (const row of rows) {
    const instant = parseExactInstant(row.issuedAt)
    if (instant === null) {
      throw new SubscriptionCodeError('invalid_response')
    }
    instants.push(instant)
  }
  for (let index = 1; index < rows.length; index += 1) {
    const previous = rows[index - 1]
    const current = rows[index]
    const previousTime = instants[index - 1]
    const currentTime = instants[index]
    if (
      previous === undefined
      || current === undefined
      || previousTime === undefined
      || currentTime === undefined
      || compareKeyset(previousTime, previous.id, currentTime, current.id) <= 0
    ) {
      throw new SubscriptionCodeError('invalid_response')
    }
  }
  if (expected.cursor !== null && rows.length > 0) {
    const cursorKey = parseHistoryCursor(expected.cursor)
    const first = rows[0]
    const firstTime = instants[0]
    if (
      cursorKey === null
      || first === undefined
      || firstTime === undefined
      || compareKeyset(firstTime, first.id, cursorKey.issuedAt, cursorKey.id) >= 0
    ) {
      throw new SubscriptionCodeError('invalid_response')
    }
  }
  for (const row of rows) {
    if (row.codeStatus === 'redeemed') {
      if (row.redeemedAt === null) throw new SubscriptionCodeError('invalid_response')
    } else if (row.redeemedAt !== null) {
      throw new SubscriptionCodeError('invalid_response')
    }
  }
  if (BigInt(record.row_count) < BigInt(rows.length)) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const nextCursor = record.next_cursor
  if (nextCursor !== null) {
    if (!isCanonicalHistoryCursor(nextCursor) || rows.length !== pageSize) {
      throw new SubscriptionCodeError('invalid_response')
    }
    const last = rows[rows.length - 1]
    const lastTime = instants[instants.length - 1]
    const cursorKey = parseHistoryCursor(nextCursor)
    if (
      last === undefined
      || lastTime === undefined
      || cursorKey === null
      || last.id.toLowerCase() !== cursorKey.id
      || compareInstants(lastTime, cursorKey.issuedAt) !== 0
    ) {
      throw new SubscriptionCodeError('invalid_response')
    }
  }
  return {
    snapshotAt: requireInstant(record.snapshot_at),
    shopId,
    shopName: record.shop_name,
    rowCount: record.row_count,
    pageSize,
    rows,
    nextCursor,
  }
}

export { subscriptionCodePageSize }

function singleRow(input: unknown): unknown {
  if (Array.isArray(input)) {
    if (input.length !== 1) {
      throw new SubscriptionCodeError('invalid_response')
    }
    return input[0]
  }
  return input
}

function parseHistoryRow(input: unknown): SubscriptionCodeRow {
  const record = objectWithKeys(input, historyRowKeys)
  if (
    typeof record.duration_days !== 'number'
    || !Number.isInteger(record.duration_days)
    || record.duration_days < durationDaysMin
    || record.duration_days > durationDaysMax
    || typeof record.code_ttl_days !== 'number'
    || !Number.isInteger(record.code_ttl_days)
    || record.code_ttl_days < codeTtlDaysMin
    || record.code_ttl_days > codeTtlDaysMax
    || !codeStatuses.includes(record.code_status as SubscriptionCodeStatus)
    || !issuedViaValues.includes(record.issued_via as IssuedVia)
  ) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return {
    id: requireUuid(record.id),
    issuedAt: requireInstant(record.issued_at),
    durationDays: record.duration_days,
    codeTtlDays: record.code_ttl_days,
    codeExpiresAt: requireInstant(record.code_expires_at),
    issuedVia: record.issued_via as IssuedVia,
    codeStatus: record.code_status as SubscriptionCodeStatus,
    redeemedAt: requireOptionalInstant(record.redeemed_at),
  }
}

function objectWithKeys<Key extends string>(
  input: unknown,
  keys: readonly Key[],
): Record<Key, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new SubscriptionCodeError('invalid_response')
  }
  const record = input as Record<string, unknown>
  const actual = Object.keys(record)
  if (actual.length !== keys.length || keys.some((key) => !Object.hasOwn(record, key))) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return record as Record<Key, unknown>
}

function requireUuid(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value)) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return value
}

function requireUuidV4(value: unknown): string {
  if (typeof value !== 'string' || !uuidV4Pattern.test(value.toLowerCase())) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return value.toLowerCase()
}

function requireInstant(value: unknown): string {
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) {
    throw new SubscriptionCodeError('invalid_response')
  }
  return value
}

function requireOptionalInstant(value: unknown): string | null {
  if (value === null) return null
  return requireInstant(value)
}

interface ExactInstant {
  seconds: bigint
  fraction: string
}

interface HistoryCursorKey {
  issuedAt: ExactInstant
  id: string
}

function parseHistoryCursor(value: string): HistoryCursorKey | null {
  if (!isCanonicalHistoryCursor(value)) return null
  const issuedAt = parseExactInstant(`${value.slice(3, 29).replace(' ', 'T')}Z`)
  if (issuedAt === null) return null
  return {
    issuedAt,
    id: value.slice(-36).toLowerCase(),
  }
}

function parseExactInstant(value: string): ExactInstant | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(?:Z|([+-])(\d{2}):?(\d{2}))?$/.exec(
    value.trim(),
  )
  if (match === null) return null
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const hour = Number(match[4])
  const minute = Number(match[5])
  const second = Number(match[6])
  const utcMs = Date.UTC(year, month - 1, day, hour, minute, second)
  if (
    Number.isNaN(utcMs)
    || new Date(utcMs).getUTCFullYear() !== year
    || new Date(utcMs).getUTCMonth() !== month - 1
    || new Date(utcMs).getUTCDate() !== day
    || new Date(utcMs).getUTCHours() !== hour
    || new Date(utcMs).getUTCMinutes() !== minute
    || new Date(utcMs).getUTCSeconds() !== second
  ) {
    return null
  }
  let offsetSeconds = 0
  if (match[8] !== undefined && match[9] !== undefined && match[10] !== undefined) {
    offsetSeconds = (Number(match[9]) * 60 + Number(match[10])) * 60 * (match[8] === '-' ? -1 : 1)
  }
  return {
    seconds: BigInt(utcMs / 1000) - BigInt(offsetSeconds),
    fraction: match[7] ?? '',
  }
}

function compareInstants(left: ExactInstant, right: ExactInstant): number {
  if (left.seconds < right.seconds) return -1
  if (left.seconds > right.seconds) return 1
  const size = Math.max(left.fraction.length, right.fraction.length)
  const leftFraction = left.fraction.padEnd(size, '0')
  const rightFraction = right.fraction.padEnd(size, '0')
  if (leftFraction < rightFraction) return -1
  if (leftFraction > rightFraction) return 1
  return 0
}

function compareKeyset(
  leftTime: ExactInstant,
  leftId: string,
  rightTime: ExactInstant,
  rightId: string,
): number {
  const time = compareInstants(leftTime, rightTime)
  if (time !== 0) return time
  const left = leftId.toLowerCase()
  const right = rightId.toLowerCase()
  if (left < right) return -1
  if (left > right) return 1
  return 0
}

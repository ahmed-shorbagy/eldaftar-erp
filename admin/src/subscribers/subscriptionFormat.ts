import { SubscriberDirectoryError } from './SubscriberDirectoryGateway.ts'

const exactCountPattern = /^(0|[1-9][0-9]*)$/
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const statuses = ['pending', 'active', 'expired'] as const

export type SubscriptionStatus = (typeof statuses)[number]

export interface SubscriberCounts {
  all: string
  active: string
  pending: string
  expired: string
}

export interface SubscriberRow {
  shopId: string
  shopName: string
  registeredAt: string
  entitlementStartsAt: string | null
  entitlementExpiresAt: string | null
  subscriptionStatus: SubscriptionStatus
}

export interface SubscriberPage {
  snapshotAt: string
  counts: SubscriberCounts
  filteredCount: string
  pageSize: number
  rows: SubscriberRow[]
  nextCursor: string | null
}

export interface SubscriberDetail extends SubscriberRow {
  snapshotAt: string
}

const pageKeys = [
  'snapshot_at',
  'counts',
  'filtered_count',
  'page_size',
  'rows',
  'next_cursor',
] as const
const countKeys = ['all', 'active', 'pending', 'expired'] as const
const rowKeys = [
  'shop_id',
  'shop_name',
  'registered_at',
  'entitlement_starts_at',
  'entitlement_expires_at',
  'subscription_status',
] as const
const detailKeys = ['snapshot_at', ...rowKeys] as const

export function parseExactCount(value: string): bigint {
  if (!exactCountPattern.test(value)) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return BigInt(value)
}

export function formatExactCount(value: string): string {
  const digits = parseExactCount(value).toString()
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

const instantFormat: Intl.DateTimeFormatOptions = {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
  numberingSystem: 'latn',
  timeZoneName: 'long',
}

export function browserDisplayTimeZone(): string {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  return typeof zone === 'string' && zone.length > 0 ? zone : 'UTC'
}

export function formatServerInstant(value: string, timeZone = browserDisplayTimeZone()): string {
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return 'تاريخ غير صالح'
  try {
    return new Intl.DateTimeFormat('ar-EG', { ...instantFormat, timeZone }).format(parsed)
  } catch {
    return 'تاريخ غير صالح'
  }
}

export function parseSubscriberPage(input: unknown): SubscriberPage {
  const record = objectWithKeys(input, pageKeys)
  const counts = objectWithKeys(record.counts, countKeys)
  const rows = Array.isArray(record.rows) ? record.rows.map(parseRow) : null
  const pageSize = record.page_size
  if (
    rows === null
    || typeof pageSize !== 'number'
    || !Number.isInteger(pageSize)
    || pageSize < 1
    || pageSize > 25
    || rows.length > pageSize
    || (record.next_cursor !== null && typeof record.next_cursor !== 'string')
  ) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  const parsedCounts = {
    all: requireCount(counts.all),
    active: requireCount(counts.active),
    pending: requireCount(counts.pending),
    expired: requireCount(counts.expired),
  }
  const filteredCount = requireCount(record.filtered_count)
  if (
    parseExactCount(parsedCounts.active)
      + parseExactCount(parsedCounts.pending)
      + parseExactCount(parsedCounts.expired)
      !== parseExactCount(parsedCounts.all)
    || parseExactCount(filteredCount) > parseExactCount(parsedCounts.all)
  ) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return {
    snapshotAt: requireInstant(record.snapshot_at),
    counts: parsedCounts,
    filteredCount,
    pageSize,
    rows,
    nextCursor: record.next_cursor,
  }
}

export function parseSubscriberDetail(input: unknown): SubscriberDetail {
  const record = objectWithKeys(input, detailKeys)
  const { snapshot_at: snapshotAt, ...row } = record
  return {
    snapshotAt: requireInstant(snapshotAt),
    ...parseRow(row),
  }
}

function parseRow(input: unknown): SubscriberRow {
  const record = objectWithKeys(input, rowKeys)
  if (
    typeof record.shop_name !== 'string'
    || record.shop_name.trim() === ''
    || !statuses.includes(record.subscription_status as SubscriptionStatus)
  ) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return {
    shopId: requireUuid(record.shop_id),
    shopName: record.shop_name,
    registeredAt: requireInstant(record.registered_at),
    entitlementStartsAt: requireOptionalInstant(record.entitlement_starts_at),
    entitlementExpiresAt: requireOptionalInstant(record.entitlement_expires_at),
    subscriptionStatus: record.subscription_status as SubscriptionStatus,
  }
}

function objectWithKeys<Key extends string>(
  input: unknown,
  keys: readonly Key[],
): Record<Key, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  const record = input as Record<string, unknown>
  const actual = Object.keys(record)
  if (actual.length !== keys.length || keys.some((key) => !Object.hasOwn(record, key))) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return record as Record<Key, unknown>
}

function requireCount(value: unknown): string {
  if (typeof value !== 'string') throw new SubscriberDirectoryError('invalid_response')
  parseExactCount(value)
  return value
}

function requireUuid(value: unknown): string {
  if (typeof value !== 'string' || !uuidPattern.test(value)) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return value
}

function requireInstant(value: unknown): string {
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) {
    throw new SubscriberDirectoryError('invalid_response')
  }
  return value
}

function requireOptionalInstant(value: unknown): string | null {
  if (value === null) return null
  return requireInstant(value)
}

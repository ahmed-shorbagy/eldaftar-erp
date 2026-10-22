import { expect, test, vi } from 'vitest'
import { SubscriberDirectoryError } from './SubscriberDirectoryGateway.ts'
import {
  formatExactCount,
  formatServerInstant,
  parseExactCount,
  parseSubscriberDetail,
  parseSubscriberPage,
} from './subscriptionFormat.ts'

const row = {
  shop_id: 'a1100000-0000-4000-8000-000000000001',
  shop_name: 'متجر ألف',
  registered_at: '2026-10-22T00:30:00.000Z',
  entitlement_starts_at: null,
  entitlement_expires_at: null,
  subscription_status: 'pending',
}

const page = {
  snapshot_at: '2026-10-22T00:30:00.000Z',
  counts: { all: '2', active: '0', pending: '2', expired: '0' },
  filtered_count: '1',
  page_size: 20,
  rows: [row],
  next_cursor: null,
}

test('exact counts reject binary-looking and non-integer text', () => {
  expect(parseExactCount('9007199254740993')).toBe(9007199254740993n)
  expect(formatExactCount('9007199254740993')).toBe('9,007,199,254,740,993')
  expect(formatExactCount('0')).toBe('0')
  for (const value of ['01', '1.5', '1e2', '-1', '', '١٢']) {
    expect(() => parseExactCount(value)).toThrow(SubscriberDirectoryError)
  }
})

const crossingInstant = '2026-10-21T22:30:00.000Z'

function instantParts(value: string, timeZone: string) {
  return new Intl.DateTimeFormat('ar-EG', {
    timeZone,
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
    numberingSystem: 'latn',
    timeZoneName: 'long',
  }).formatToParts(new Date(value))
}

function part(parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes): string {
  return parts.find((item) => item.type === type)?.value ?? ''
}

test('UTC and Cairo dates cross local midnight and name the zone', () => {
  const utcParts = instantParts(crossingInstant, 'UTC')
  const cairoParts = instantParts(crossingInstant, 'Africa/Cairo')
  const utc = formatServerInstant(crossingInstant, 'UTC')
  const cairo = formatServerInstant(crossingInstant, 'Africa/Cairo')
  expect(part(utcParts, 'day')).toBe('21')
  expect(part(cairoParts, 'day')).toBe('22')
  expect(part(utcParts, 'hour')).not.toBe(part(cairoParts, 'hour'))
  expect(utc).toContain(part(utcParts, 'day'))
  expect(utc).toContain(part(utcParts, 'hour'))
  expect(utc).toContain(part(utcParts, 'timeZoneName'))
  expect(cairo).toContain(part(cairoParts, 'day'))
  expect(cairo).toContain(part(cairoParts, 'hour'))
  expect(cairo).toContain(part(cairoParts, 'timeZoneName'))
  expect(utc).not.toContain(part(cairoParts, 'timeZoneName'))
  expect(utc).not.toBe(cairo)
  expect(utc).not.toMatch(/[٠-٩]/)
  expect(cairo).not.toMatch(/[٠-٩]/)
  expect(formatServerInstant('not-a-date')).toBe('تاريخ غير صالح')
  expect(formatServerInstant('not-a-date', 'Africa/Cairo')).toBe('تاريخ غير صالح')
})

test('the default display zone follows the browser zone', () => {
  const original = Intl.DateTimeFormat.prototype.resolvedOptions
  const spy = vi.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions').mockImplementation(function mockZone(this: Intl.DateTimeFormat) {
    const resolved = original.call(this)
    if (resolved.timeZoneName === undefined) return { ...resolved, timeZone: 'Pacific/Auckland' }
    return resolved
  })
  try {
    const formatted = formatServerInstant(crossingInstant)
    expect(formatted).toBe(formatServerInstant(crossingInstant, 'Pacific/Auckland'))
    expect(formatted).not.toBe(formatServerInstant(crossingInstant, 'UTC'))
    expect(formatted).toContain('توقيت')
  } finally {
    spy.mockRestore()
  }
})

test('directory payload keeps only the subscription allowlist and exact count strings', () => {
  const parsed = parseSubscriberPage(page)
  expect(parsed.counts.all).toBe('2')
  expect(parsed.filteredCount).toBe('1')
  expect(parsed.rows[0]?.shopName).toBe('متجر ألف')
  expect(parsed.rows[0]?.entitlementStartsAt).toBeNull()

  expect(() => parseSubscriberPage({
    ...page,
    counts: { all: 2, active: 0, pending: 2, expired: 0 },
  })).toThrow(SubscriberDirectoryError)
  expect(() => parseSubscriberPage({ ...page, phone: '+201000000000' })).toThrow(SubscriberDirectoryError)
  expect(() => parseSubscriberPage({
    ...page,
    rows: [{ ...row, owner_display_name: 'سري' }],
  })).toThrow(SubscriberDirectoryError)
  expect(() => parseSubscriberPage({
    ...page,
    counts: { all: '1', active: '1', pending: '1', expired: '0' },
  })).toThrow(SubscriberDirectoryError)
})

test('detail payload uses the same shop fields', () => {
  const parsed = parseSubscriberDetail({ ...row, snapshot_at: page.snapshot_at })
  expect(parsed.subscriptionStatus).toBe('pending')
  expect(() => parseSubscriberDetail({ ...row, snapshot_at: page.snapshot_at, email: 'a@b.c' })).toThrow(
    SubscriberDirectoryError,
  )
})

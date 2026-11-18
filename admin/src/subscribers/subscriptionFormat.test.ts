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
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    numberingSystem: 'latn',
  }).formatToParts(new Date(value))
}

function part(parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes): string {
  return parts.find((item) => item.type === type)?.value ?? ''
}

test('UTC and Cairo dates cross local midnight', () => {
  const utcParts = instantParts(crossingInstant, 'UTC')
  const cairoParts = instantParts(crossingInstant, 'Africa/Cairo')
  const utc = formatServerInstant(crossingInstant, 'UTC')
  const cairo = formatServerInstant(crossingInstant, 'Africa/Cairo')
  expect(part(utcParts, 'day')).toBe('21')
  expect(part(cairoParts, 'day')).toBe('22')
  expect(utc).toContain(part(utcParts, 'day'))
  expect(cairo).toContain(part(cairoParts, 'day'))
  expect(utc).not.toBe(cairo)
  expect(utc).not.toMatch(/[٠-٩]/)
  expect(cairo).not.toMatch(/[٠-٩]/)
  expect(formatServerInstant('not-a-date')).toBe('تاريخ غير صالح')
  expect(formatServerInstant('not-a-date', 'Africa/Cairo')).toBe('تاريخ غير صالح')
})

// Owner rule of 2026-11-17: «الساعة ٢ تبقى الساعة ٢», and no zone name.
test('times use the twelve-hour clock with ص/م and never name a time zone', () => {
  const afternoon = formatServerInstant('2026-11-17T12:05:00.000Z', 'Africa/Cairo')
  expect(afternoon).toContain('2:05')
  expect(afternoon).toContain('م')
  expect(afternoon).not.toContain('14')
  const morning = formatServerInstant('2026-11-17T07:30:00.000Z', 'Africa/Cairo')
  expect(morning).toContain('9:30')
  expect(morning).toContain('ص')
  const midnight = formatServerInstant('2026-11-17T22:00:00.000Z', 'Africa/Cairo')
  expect(midnight).toContain('12:00')
  expect(midnight).toContain('ص')
  const noon = formatServerInstant('2026-11-17T10:00:00.000Z', 'Africa/Cairo')
  expect(noon).toContain('12:00')
  expect(noon).toContain('م')
  for (const text of [afternoon, morning, midnight, noon, formatServerInstant(crossingInstant, 'UTC')]) {
    expect(text).not.toContain('توقيت')
    expect(text).not.toContain('أوروبا')
    expect(text).not.toMatch(/UTC|GMT/)
    expect(text).not.toMatch(/:\d{2}:\d{2}/)
  }
})

test('the default display zone follows the browser zone', () => {
  const original = Intl.DateTimeFormat.prototype.resolvedOptions
  const spy = vi.spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions').mockImplementation(function mockZone(this: Intl.DateTimeFormat) {
    const resolved = original.call(this)
    if (resolved.hour === undefined) return { ...resolved, timeZone: 'Pacific/Auckland' }
    return resolved
  })
  try {
    const formatted = formatServerInstant(crossingInstant)
    expect(formatted).toBe(formatServerInstant(crossingInstant, 'Pacific/Auckland'))
    expect(formatted).not.toBe(formatServerInstant(crossingInstant, 'UTC'))
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

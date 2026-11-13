import { expect, test } from 'vitest'
import { formatAdminPath, parseAdminPath } from '../navigation/adminRoutes.ts'
import {
  BroadcastError,
  mapBroadcastError,
  normalizeDraft,
  parseBroadcastPage,
  parsePreview,
  parseSendResult,
  parseWithdrawResult,
  validateDraft,
  type BroadcastDraft,
} from './BroadcastGateway.ts'

const id = 'b1000000-0000-4000-8000-000000000001'
const shopId = 'b1100000-0000-4000-8000-000000000001'

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    created_at: '2026-11-13T10:00:00.000Z',
    created_by_email: 'admin@example.test',
    segment: 'all',
    segment_days: null,
    segment_shop_id: null,
    segment_shop_name: null,
    title_ar: 'تجديد الاشتراك',
    body_ar: 'نص',
    link_url: null,
    starts_at: '2026-11-13T10:00:00.000Z',
    ends_at: '2026-12-13T10:00:00.000Z',
    state: 'active',
    recipient_count: '12',
    delivered_count: '5',
    read_count: '2',
    withdrawn_at: null,
    withdraw_reason: null,
    ...overrides,
  }
}

function page(rows: unknown[], nextCursor: string | null = null): Record<string, unknown> {
  return { snapshot_at: '2026-11-13T10:00:00.000Z', page_size: 20, rows, next_cursor: nextCursor }
}

const draft: BroadcastDraft = {
  segment: 'all',
  days: null,
  shopId: null,
  titleAr: 'عنوان',
  bodyAr: 'نص الرسالة',
  linkUrl: null,
  startsAt: null,
  endsAt: null,
}

test('history rows parse with exact keys, consistent segment, state and counts', () => {
  const parsed = parseBroadcastPage(page([row(), row({
    id: 'b1000000-0000-4000-8000-000000000002',
    segment: 'shop',
    segment_shop_id: shopId,
    segment_shop_name: 'متجر',
    state: 'withdrawn',
    withdrawn_at: '2026-11-14T00:00:00.000Z',
    withdraw_reason: 'خطأ',
  })]), 20)
  expect(parsed.rows).toHaveLength(2)
  expect(parsed.rows[1]?.segmentShopName).toBe('متجر')

  const bad = [
    row({ extra: true }),
    row({ segment: 'everyone' }),
    row({ segment: 'expiring', segment_days: null }),
    row({ segment: 'shop', segment_shop_id: null }),
    row({ state: 'withdrawn' }),
    row({ withdrawn_at: '2026-11-14T00:00:00.000Z', withdraw_reason: 'سبب' }),
    row({ read_count: '6' }),
    row({ delivered_count: '13' }),
    row({ recipient_count: '-1' }),
    row({ title_ar: ' ' }),
  ]
  for (const candidate of bad) {
    expect(() => parseBroadcastPage(page([candidate]), 20)).toThrow(BroadcastError)
  }
  expect(() => parseBroadcastPage(page([row(), row()]), 20)).toThrow(BroadcastError)
  expect(() => parseBroadcastPage(page([], 'nope'), 20)).toThrow(BroadcastError)
  expect(() => parseBroadcastPage({ ...page([]), page_size: 10 }, 20)).toThrow(BroadcastError)
})

test('preview, send and withdraw results are strict', () => {
  expect(parsePreview({ snapshot_at: '2026-11-13T10:00:00Z', recipient_count: '0' }).recipientCount).toBe('0')
  expect(() => parsePreview({ snapshot_at: '2026-11-13T10:00:00Z', recipient_count: 3 })).toThrow(BroadcastError)

  const sent = {
    status: 'sent',
    broadcast_id: id,
    recipient_count: '3',
    starts_at: '2026-11-13T10:00:00Z',
    ends_at: '2026-12-13T10:00:00Z',
  }
  expect(parseSendResult(sent).status).toBe('sent')
  expect(parseSendResult({ ...sent, status: 'replayed' }).status).toBe('replayed')
  expect(() => parseSendResult({ ...sent, status: 'queued' })).toThrow(BroadcastError)
  expect(() => parseSendResult({ ...sent, recipient_count: '0' })).toThrow(BroadcastError)
  expect(() => parseSendResult({ ...sent, ends_at: sent.starts_at })).toThrow(BroadcastError)

  const withdrawn = { status: 'withdrawn', broadcast_id: id, withdrawn_at: '2026-11-14T00:00:00Z' }
  expect(parseWithdrawResult(withdrawn, id).status).toBe('withdrawn')
  expect(() => parseWithdrawResult(withdrawn, 'b1000000-0000-4000-8000-000000000009')).toThrow(BroadcastError)
})

test('server errors map to typed codes', () => {
  expect(mapBroadcastError('forbidden').code).toBe('unauthorized')
  expect(mapBroadcastError('unauthorized').code).toBe('unauthorized')
  expect(mapBroadcastError('audience_changed').code).toBe('audience_changed')
  expect(mapBroadcastError('empty_audience').code).toBe('empty_audience')
  expect(mapBroadcastError('request_key_reused').code).toBe('request_conflict')
  expect(mapBroadcastError('stale_cursor').code).toBe('stale')
  expect(mapBroadcastError('not_found').code).toBe('not_found')
  expect(mapBroadcastError('invalid_input').code).toBe('invalid')
  expect(mapBroadcastError('boom').code).toBe('unavailable')
})

test('draft validation mirrors the server limits', () => {
  const now = new Date('2026-11-13T10:00:00Z')
  expect(validateDraft(draft, now)).toEqual({})
  expect(validateDraft({ ...draft, titleAr: 'ع'.repeat(81) }, now).title).toBe(true)
  expect(validateDraft({ ...draft, titleAr: `سطر${String.fromCharCode(10)}ثانٍ` }, now).title).toBe(true)
  expect(validateDraft({ ...draft, bodyAr: `سطر${String.fromCharCode(10)}ثانٍ` }, now)).toEqual({})
  expect(validateDraft({ ...draft, bodyAr: `نص${String.fromCharCode(9)}` + 'x' }, now).body).toBe(true)
  expect(validateDraft({ ...draft, bodyAr: 'ن'.repeat(1001) }, now).body).toBe(true)
  expect(validateDraft({ ...draft, linkUrl: 'http://example.test' }, now).link).toBe(true)
  expect(validateDraft({ ...draft, linkUrl: 'https://example.test/x' }, now)).toEqual({})
  expect(validateDraft({ ...draft, segment: 'expiring', days: 91 }, now).days).toBe(true)
  expect(validateDraft({ ...draft, segment: 'expiring', days: 7 }, now)).toEqual({})
  expect(validateDraft({ ...draft, segment: 'shop', shopId: 'abc' }, now).shopId).toBe(true)
  expect(validateDraft({ ...draft, startsAt: '2027-03-01T00:00:00Z' }, now).startsAt).toBe(true)
  expect(validateDraft({ ...draft, startsAt: 'invalid' }, now).startsAt).toBe(true)
  expect(validateDraft({ ...draft, endsAt: '2026-11-13T09:00:00Z' }, now).endsAt).toBe(true)
  expect(validateDraft({ ...draft, endsAt: '2027-12-01T00:00:00Z' }, now).endsAt).toBe(true)
  expect(validateDraft({ ...draft, endsAt: '2026-11-20T00:00:00Z' }, now)).toEqual({})
})

test('normalizing trims text and drops parameters of other segments', () => {
  expect(normalizeDraft({
    ...draft,
    segment: 'all',
    days: 7,
    shopId: shopId,
    titleAr: '  عنوان ',
    linkUrl: '  ',
  })).toMatchObject({ titleAr: 'عنوان', days: null, shopId: null, linkUrl: null })
  expect(normalizeDraft({ ...draft, segment: 'shop', shopId: ` ${shopId.toUpperCase()} ` }).shopId).toBe(shopId)
})

test('the broadcasts route carries an optional shop for the composer', () => {
  expect(parseAdminPath('/broadcasts')).toEqual({ area: 'broadcasts', shopId: null })
  expect(parseAdminPath('/broadcasts', `?shop=${shopId.toUpperCase()}`)).toEqual({ area: 'broadcasts', shopId })
  expect(parseAdminPath('/broadcasts', '?shop=nope')).toEqual({ area: 'broadcasts', shopId: null })
  expect(parseAdminPath('/broadcasts/x')).toBeNull()
  expect(formatAdminPath({ area: 'broadcasts', shopId })).toBe(`/broadcasts?shop=${shopId}`)
  expect(formatAdminPath({ area: 'broadcasts', shopId: null })).toBe('/broadcasts')
})

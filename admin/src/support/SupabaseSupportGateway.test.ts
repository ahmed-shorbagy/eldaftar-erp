import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SupabaseSupportGateway } from './SupabaseSupportGateway.ts'
import {
  SupportError,
  parseSupportPage,
  parseSupportUpdate,
  supportPageSize,
} from './SupportGateway.ts'

const row = {
  id: 'e1100000-0000-4000-8000-000000000001',
  shop_id: 'a1100000-0000-4000-8000-000000000001',
  shop_name: 'متجر الدعم',
  category: 'technical',
  body_ar: 'سؤال عن تجديد الاشتراك والميزانية',
  status: 'new',
  reply_ar: null,
  created_at: '2026-10-27T09:00:00.000Z',
  updated_at: '2026-10-27T09:00:00.000Z',
  answered_at: null,
  closed_at: null,
}

const adminRow = {
  ...row,
  shop_created_at: '2026-01-01T00:00:00.000Z',
  shop_time_zone: 'Africa/Cairo',
}

const payload = {
  inquiries: [adminRow],
  next_cursor_at: '2026-10-26T09:00:00.000Z',
  next_cursor_id: 'e1100000-0000-4000-8000-000000000000',
  snapshot_at: '2026-10-27T09:30:00.000Z',
}

function sessionOf(user: string | null) {
  return user === null ? null : { user: { id: user } }
}

function client(result: { data: unknown; error: { message: string } | null } = {
  data: payload,
  error: null,
}) {
  const rpc = vi.fn().mockResolvedValue(result)
  const sessionData = sessionOf('admin-a')
  return {
    client: {
      auth: { getSession: vi.fn().mockResolvedValue({ data: { session: sessionData }, error: null }) },
      rpc,
    } as unknown as SupabaseClient,
    rpc,
    session: { data: { session: sessionData } },
  }
}

test('list sends the bounded page and parses admin rows', async () => {
  const { client: supabase, rpc } = client()
  const gateway = new SupabaseSupportGateway(supabase)
  const page = await gateway.list({ status: 'all', search: '  ', cursorAt: null, cursorId: null })
  expect(rpc).toHaveBeenCalledWith('admin_list_support_inquiries_v1', {
    p_status: null,
    p_search: null,
    p_cursor_at: null,
    p_cursor_id: null,
    p_page_size: supportPageSize,
  })
  const row = page.inquiries[0]!
  expect(row.shopName).toBe('متجر الدعم')
  expect(row.status).toBe('new')
  expect(row.category).toBe('technical')
  expect(row.shopCreatedAt).toBe('2026-01-01T00:00:00.000Z')
  expect(row.shopTimeZone).toBe('Africa/Cairo')
  expect(page.nextCursorAt).toBe('2026-10-26T09:00:00.000Z')
})

test('a status filter and exact search travel to the rpc', async () => {
  const { client: supabase, rpc } = client()
  const gateway = new SupabaseSupportGateway(supabase)
  await gateway.list({
    status: 'answered',
    search: 'a1100000-0000-4000-8000-000000000001',
    cursorAt: '2026-10-26T09:00:00.000Z',
    cursorId: 'e1100000-0000-4000-8000-000000000000',
  })
  expect(rpc).toHaveBeenCalledWith('admin_list_support_inquiries_v1', {
    p_status: 'answered',
    p_search: 'a1100000-0000-4000-8000-000000000001',
    p_cursor_at: '2026-10-26T09:00:00.000Z',
    p_cursor_id: 'e1100000-0000-4000-8000-000000000000',
    p_page_size: supportPageSize,
  })
})

test('a cursor pair is required together', async () => {
  const { client: supabase, rpc } = client()
  const gateway = new SupabaseSupportGateway(supabase)
  await expect(
    gateway.list({ status: 'all', search: '', cursorAt: null, cursorId: 'e1' }),
  ).rejects.toMatchObject({ code: 'invalid' })
  expect(rpc).not.toHaveBeenCalled()
})

test('update sends the triage write and parses the saved result', async () => {
  const { client: supabase, rpc } = client({
    data: { ...row, result_status: 'saved' },
    error: null,
  })
  const gateway = new SupabaseSupportGateway(supabase)
  const result = await gateway.updateInquiryStatus({
    inquiryId: row.id,
    to: 'in_progress',
    replyAr: null,
    idempotencyKey: 'f2300000-0000-4000-8000-000000000001',
  })
  expect(rpc).toHaveBeenCalledWith('admin_update_support_inquiry_status_v1', {
    p_id: row.id,
    p_to_status: 'in_progress',
    p_reply_ar: null,
    p_idempotency_key: 'f2300000-0000-4000-8000-000000000001',
  })
  expect(result).toMatchObject({ inquiryId: row.id, status: 'new', saved: true })
})

test('a replayed triage write reports replayed', async () => {
  const { client: supabase } = client({
    data: { ...row, result_status: 'replayed' },
    error: null,
  })
  const gateway = new SupabaseSupportGateway(supabase)
  const result = await gateway.updateInquiryStatus({
    inquiryId: row.id,
    to: 'in_progress',
    replyAr: null,
    idempotencyKey: 'f2300000-0000-4000-8000-000000000001',
  })
  expect(result.saved).toBe(false)
})

test.each([
  ['forbidden', 'access_lost'],
  ['unauthenticated', 'access_lost'],
  ['session_expired', 'access_lost'],
  ['invalid_input', 'invalid'],
  ['22023', 'invalid'],
  ['stale_cursor', 'stale_cursor'],
  ['invalid_transition', 'invalid_transition'],
  ['not_found', 'not_found'],
  ['payload_mismatch', 'invalid'],
  ['connection reset', 'unavailable'],
] as const)('%s maps to %s', async (message, code) => {
  const { client: supabase } = client({ data: null, error: { message } })
  const gateway = new SupabaseSupportGateway(supabase)
  await expect(gateway.list({ status: 'all', search: '', cursorAt: null, cursorId: null })).rejects
    .toMatchObject({ code })
})

test('a missing session is refused before the rpc', async () => {
  const rpc = vi.fn()
  const supabase = {
    auth: { getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }) },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseSupportGateway(supabase)
  await expect(
    gateway.list({ status: 'all', search: '', cursorAt: null, cursorId: null }),
  ).rejects.toMatchObject({ code: 'access_lost' })
  expect(rpc).not.toHaveBeenCalled()
})

test('a session replaced after the reply discards it', async () => {
  let session = sessionOf('admin-a')
  const rpc = vi.fn().mockResolvedValue({ data: payload, error: null })
  const supabase = {
    auth: { getSession: vi.fn(async () => ({ data: { session }, error: null })) },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseSupportGateway(supabase)
  const promise = gateway.list({ status: 'all', search: '', cursorAt: null, cursorId: null })
  session = sessionOf('admin-b')
  await expect(promise).rejects.toMatchObject({ code: 'access_lost' })
})

test('a session lookup failure is unavailable and skips the rpc', async () => {
  const rpc = vi.fn()
  const supabase = {
    auth: { getSession: vi.fn().mockRejectedValue(new Error('offline')) },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseSupportGateway(supabase)
  await expect(
    gateway.list({ status: 'all', search: '', cursorAt: null, cursorId: null }),
  ).rejects.toMatchObject({ code: 'unavailable' })
  expect(rpc).not.toHaveBeenCalled()
})

test('parsers reject malformed payloads', () => {
  expect(() => parseSupportPage({ ...payload, inquiries: 'x' })).toThrow(SupportError)
  expect(() => parseSupportPage({ ...payload, next_cursor_id: null })).toThrow(SupportError)
  expect(() =>
    parseSupportPage({ ...payload, inquiries: [{ ...adminRow, shop_time_zone: '' }] }),
  ).toThrow(SupportError)
  expect(() =>
    parseSupportPage({
      ...payload,
      inquiries: [{ ...adminRow, category: 'unknown' }],
    }),
  ).toThrow(SupportError)
  expect(() => parseSupportUpdate({ ...row, result_status: 'other' })).toThrow(SupportError)
  expect(() => parseSupportUpdate({ ...row })).toThrow(SupportError)
  expect(() => parseSupportPage(null)).toThrow(SupportError)
})

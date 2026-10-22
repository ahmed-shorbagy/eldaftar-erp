import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SubscriberDirectoryError, subscriberPageSize } from './SubscriberDirectoryGateway.ts'
import { SupabaseSubscriberDirectoryGateway } from './SupabaseSubscriberDirectoryGateway.ts'

const payload = {
  snapshot_at: '2026-10-22T00:30:00.000Z',
  counts: { all: '1', active: '1', pending: '0', expired: '0' },
  filtered_count: '1',
  page_size: 20,
  rows: [{
    shop_id: 'a1100000-0000-4000-8000-000000000001',
    shop_name: 'متجر',
    registered_at: '2020-01-01T00:00:00.000Z',
    entitlement_starts_at: '2020-01-01T00:00:00.000Z',
    entitlement_expires_at: '2027-01-01T00:00:00.000Z',
    subscription_status: 'active',
  }],
  next_cursor: null,
}

function accessToken(sessionId: string, mark: string): string {
  const json = JSON.stringify({
    session_id: sessionId,
    user_metadata: { is_platform_admin: true },
  })
  const segment = btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
  return `eyJhbGciOiJub25lIn0.${segment}.${mark}`
}

function directorySession(userId: string, sessionId: string, mark: string) {
  return {
    access_token: accessToken(sessionId, mark),
    user: { id: userId },
  }
}

function client(result: { data: unknown; error: { message: string } | null }) {
  const rpc = vi.fn().mockResolvedValue(result)
  const session = directorySession('user-a', 'session-a', 'stable')
  return {
    client: {
      auth: { getSession: vi.fn().mockResolvedValue({ data: { session }, error: null }) },
      rpc,
    } as unknown as SupabaseClient,
    rpc,
  }
}

function deferredClient(initial = directorySession('user-a', 'session-a', '1')) {
  let session: ReturnType<typeof directorySession> | null = initial
  const pending: Array<(value: { data: unknown; error: { message: string } | null }) => void> = []
  const rpc = vi.fn(() => new Promise((resolve) => {
    pending.push(resolve)
  }))
  const supabase = {
    auth: {
      getSession: vi.fn(async () => ({ data: { session }, error: null })),
    },
    rpc,
  } as unknown as SupabaseClient
  return {
    client: supabase,
    rpc,
    pending,
    setSession(next: typeof session) {
      session = next
    },
  }
}

const detailPayload = {
  snapshot_at: payload.snapshot_at,
  ...payload.rows[0],
}

function startRead(gateway: SupabaseSubscriberDirectoryGateway, method: 'list' | 'get') {
  if (method === 'list') {
    return gateway.list({ status: 'active', search: 'متجر', cursor: 'cursor-1' })
  }
  return gateway.get('a1100000-0000-4000-8000-000000000001')
}

test('list sends the bounded page and parses exact counts', async () => {
  const { client: supabase, rpc } = client({ data: payload, error: null })
  const gateway = new SupabaseSubscriberDirectoryGateway(supabase)
  const page = await gateway.list({ status: 'active', search: 'متجر', cursor: null })
  expect(rpc).toHaveBeenCalledWith('admin_list_subscribers_v1', {
    p_status: 'active',
    p_search: 'متجر',
    p_cursor: null,
    p_page_size: subscriberPageSize,
  })
  expect(page.filteredCount).toBe('1')
  expect(page.rows[0]?.subscriptionStatus).toBe('active')
})

test('auth and stale cursor failures stay distinct from ordinary errors', async () => {
  const denied = client({ data: null, error: { message: 'forbidden' } })
  const gateway = new SupabaseSubscriberDirectoryGateway(denied.client)
  await expect(gateway.list({ status: 'all', search: '', cursor: null })).rejects.toMatchObject({
    code: 'access_lost',
  })

  const stale = client({ data: null, error: { message: 'stale_cursor' } })
  await expect(
    new SupabaseSubscriberDirectoryGateway(stale.client).get('a1100000-0000-4000-8000-000000000001'),
  ).rejects.toBeInstanceOf(SubscriberDirectoryError)
  await expect(
    new SupabaseSubscriberDirectoryGateway(stale.client).list({ status: 'all', search: '', cursor: 'bad' }),
  ).rejects.toMatchObject({ code: 'stale_cursor' })

  const missing = client({ data: null, error: { message: 'not_found' } })
  await expect(
    new SupabaseSubscriberDirectoryGateway(missing.client).get('a1100000-0000-4000-8000-000000000001'),
  ).rejects.toMatchObject({ code: 'not_found' })
})

test('a session lookup failure does not call the directory', async () => {
  const rpc = vi.fn()
  const supabase = {
    auth: { getSession: vi.fn().mockRejectedValue(new Error('offline')) },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseSubscriberDirectoryGateway(supabase)
  await expect(gateway.list({ status: 'all', search: 'متجر', cursor: null })).rejects.toMatchObject({
    code: 'unavailable',
  })
  expect(rpc).not.toHaveBeenCalled()
})

test('a session lookup failure after the reply discards it', async () => {
  const session = directorySession('user-a', 'session-a', '1')
  const getSession = vi.fn()
    .mockResolvedValueOnce({ data: { session }, error: null })
    .mockRejectedValueOnce(new Error('offline'))
  const rpc = vi.fn().mockResolvedValue({ data: payload, error: null })
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: { getSession },
    rpc,
  } as unknown as SupabaseClient)
  await expect(gateway.list({ status: 'active', search: 'متجر', cursor: null })).rejects.toMatchObject({
    code: 'unavailable',
  })
})

test.each(['list', 'get'] as const)(
  '%s discards a deferred reply when the account changes',
  async (method) => {
    const harness = deferredClient()
    const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
    const promise = startRead(gateway, method)
    await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
    harness.setSession(directorySession('user-b', 'session-b', '2'))
    harness.pending[0]?.({ data: method === 'list' ? payload : detailPayload, error: null })
    await expect(promise).rejects.toMatchObject({ code: 'access_lost' })
    expect(harness.rpc).toHaveBeenCalledTimes(1)
  },
)

test.each(['list', 'get'] as const)(
  '%s discards a deferred reply on sign-out even when metadata claims admin',
  async (method) => {
    const harness = deferredClient()
    const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
    const promise = startRead(gateway, method)
    await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
    harness.setSession(null)
    harness.pending[0]?.({ data: method === 'list' ? payload : detailPayload, error: null })
    await expect(promise).rejects.toMatchObject({ code: 'access_lost' })
    expect(harness.rpc).toHaveBeenCalledTimes(1)
  },
)

test.each(['list', 'get'] as const)(
  '%s discards a deferred reply when the same user replaces the session',
  async (method) => {
    const harness = deferredClient()
    const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
    const promise = startRead(gateway, method)
    await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
    harness.setSession(directorySession('user-a', 'session-b', '2'))
    harness.pending[0]?.({ data: method === 'list' ? payload : detailPayload, error: null })
    await expect(promise).rejects.toMatchObject({ code: 'access_lost' })
    expect(harness.rpc).toHaveBeenCalledTimes(1)
  },
)

test('a same-user token refresh retries the list with the same search and drops the first payload', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const promise = gateway.list({ status: 'active', search: 'ذهب', cursor: 'cursor-1' })
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.setSession(directorySession('user-a', 'session-a', '2'))
  harness.pending[0]?.({ data: payload, error: null })
  await vi.waitFor(() => expect(harness.pending).toHaveLength(2))
  const refreshed = {
    ...payload,
    rows: [{ ...payload.rows[0], shop_name: 'بعد التجديد' }],
  }
  harness.pending[1]?.({ data: refreshed, error: null })
  const page = await promise
  expect(page.rows[0]?.shopName).toBe('بعد التجديد')
  expect(page.filteredCount).toBe('1')
  const args = { p_status: 'active', p_search: 'ذهب', p_cursor: 'cursor-1', p_page_size: subscriberPageSize }
  expect(harness.rpc).toHaveBeenNthCalledWith(1, 'admin_list_subscribers_v1', args)
  expect(harness.rpc).toHaveBeenNthCalledWith(2, 'admin_list_subscribers_v1', args)
})

test('a same-user token refresh retries the detail and drops the first payload', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const promise = gateway.get('a1100000-0000-4000-8000-000000000001')
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.setSession(directorySession('user-a', 'session-a', '2'))
  harness.pending[0]?.({ data: detailPayload, error: null })
  await vi.waitFor(() => expect(harness.pending).toHaveLength(2))
  harness.pending[1]?.({
    data: { ...detailPayload, shop_name: 'بعد التجديد' },
    error: null,
  })
  const detail = await promise
  expect(detail.shopName).toBe('بعد التجديد')
  expect(harness.rpc).toHaveBeenNthCalledWith(1, 'admin_get_subscriber_v1', {
    p_shop_id: 'a1100000-0000-4000-8000-000000000001',
  })
  expect(harness.rpc).toHaveBeenNthCalledWith(2, 'admin_get_subscriber_v1', {
    p_shop_id: 'a1100000-0000-4000-8000-000000000001',
  })
})

test('a second token change during the fresh retry is retryable and keeps no stale page', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const promise = gateway.list({ status: 'expired', search: 'ذهب', cursor: null })
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.setSession(directorySession('user-a', 'session-a', '2'))
  harness.pending[0]?.({ data: payload, error: null })
  await vi.waitFor(() => expect(harness.pending).toHaveLength(2))
  harness.setSession(directorySession('user-a', 'session-a', '3'))
  harness.pending[1]?.({
    data: { ...payload, rows: [{ ...payload.rows[0], shop_name: 'لا يُقبل' }] },
    error: null,
  })
  await expect(promise).rejects.toMatchObject({ code: 'unavailable' })
  expect(harness.rpc).toHaveBeenCalledTimes(2)
  expect(harness.rpc).toHaveBeenNthCalledWith(2, 'admin_list_subscribers_v1', {
    p_status: 'expired',
    p_search: 'ذهب',
    p_cursor: null,
    p_page_size: subscriberPageSize,
  })
})

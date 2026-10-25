import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import {
  SubscriberDirectoryError,
  SubscriptionCodeError,
  subscriberPageSize,
  subscriptionCodePageSize,
} from './SubscriberDirectoryGateway.ts'
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

function directorySession(
  userId: string,
  sessionId: string,
  mark: string,
  expiresAt: number | null = Math.floor(Date.now() / 1000) + 3600,
) {
  return {
    access_token: accessToken(sessionId, mark),
    user: { id: userId },
    ...(expiresAt === null ? {} : { expires_at: expiresAt }),
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

const issueRow = {
  code: 'ABCDEFABCDEFABCDEFABCDEFABCDEFAB',
  shop_id: 'a1100000-0000-4000-8000-000000000001',
  owner_user_id: 'c2000000-0000-4000-8000-0000000000b1',
  duration_days: 30,
  code_expires_at: '2026-11-21T00:00:00.000Z',
  status: 'issued',
  request_key: 'c2300000-0000-4000-8000-000000000011',
  issued_via: 'platform_admin',
}

const issueInput = {
  shopId: 'a1100000-0000-4000-8000-000000000001',
  durationDays: 30,
  codeTtlDays: 30,
  requestKey: 'c2300000-0000-4000-8000-000000000011',
}

test('issue does not retry a write after a same-user token refresh and still accepts the secret', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const binding = await gateway.bindSelectedShopSession()
  const promise = gateway.issueSubscriptionCode(issueInput, binding)
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.setSession(directorySession('user-a', 'session-a', '2'))
  harness.pending[0]?.({ data: [issueRow], error: null })
  const result = await promise
  expect(result.code).toBe(issueRow.code)
  expect(harness.rpc).toHaveBeenCalledTimes(1)
})

test('issue discards a late secret when the session is replaced', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const binding = await gateway.bindSelectedShopSession()
  const promise = gateway.issueSubscriptionCode(issueInput, binding)
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.setSession(directorySession('user-b', 'session-b', '2'))
  harness.pending[0]?.({ data: [issueRow], error: null })
  await expect(promise).rejects.toMatchObject({ code: 'access_lost' })
  expect(harness.rpc).toHaveBeenCalledTimes(1)
})

test('issue maps unauthorized to access loss', async () => {
  const { client: supabase } = client({ data: null, error: { message: 'unauthorized' } })
  const gateway = new SupabaseSubscriberDirectoryGateway(supabase)
  const binding = await gateway.bindSelectedShopSession()
  await expect(gateway.issueSubscriptionCode(issueInput, binding)).rejects.toBeInstanceOf(SubscriptionCodeError)
  await expect(gateway.issueSubscriptionCode(issueInput, binding)).rejects.toMatchObject({ code: 'access_lost' })
})

test('issue refuses a replacement session when no auth event arrives', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const binding = await gateway.bindSelectedShopSession()
  harness.setSession(directorySession('user-a', 'session-b', '2'))
  await expect(gateway.issueSubscriptionCode(issueInput, binding)).rejects.toMatchObject({ code: 'access_lost' })
  expect(harness.rpc).not.toHaveBeenCalled()
})

test('issue has no unbound production write route', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  await expect(
    (gateway.issueSubscriptionCode as unknown as (input: typeof issueInput) => Promise<unknown>)(issueInput),
  ).rejects.toMatchObject({ code: 'access_lost' })
  expect(harness.rpc).not.toHaveBeenCalled()
})

test('directory list still accepts a session without expires_at', async () => {
  const rpc = vi.fn().mockResolvedValue({ data: payload, error: null })
  const session = directorySession('user-a', 'session-a', 'stable', null)
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: { getSession: vi.fn().mockResolvedValue({ data: { session }, error: null }) },
    rpc,
  } as unknown as SupabaseClient)
  const page = await gateway.list({ status: 'all', search: '', cursor: null })
  expect(page.filteredCount).toBe('1')
  expect(rpc).toHaveBeenCalled()
})

test('issue rejects an expired session before calling the rpc', async () => {
  const rpc = vi.fn()
  const session = directorySession('user-a', 'session-a', 'stable', Math.floor(Date.now() / 1000) - 30)
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: { getSession: vi.fn().mockResolvedValue({ data: { session }, error: null }) },
    rpc,
  } as unknown as SupabaseClient)
  await expect(gateway.bindSelectedShopSession()).rejects.toMatchObject({ code: 'access_lost' })
  await expect(
    (gateway.issueSubscriptionCode as unknown as (input: typeof issueInput) => Promise<unknown>)(issueInput),
  ).rejects.toMatchObject({ code: 'access_lost' })
  expect(rpc).not.toHaveBeenCalled()
})

test('issue rejects a malformed session without a session id', async () => {
  const rpc = vi.fn()
  const json = JSON.stringify({ user_metadata: { is_platform_admin: true } })
  const segment = btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
  const session = {
    access_token: `eyJhbGciOiJub25lIn0.${segment}.mark`,
    user: { id: 'user-a' },
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  }
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: { getSession: vi.fn().mockResolvedValue({ data: { session }, error: null }) },
    rpc,
  } as unknown as SupabaseClient)
  await expect(gateway.bindSelectedShopSession()).rejects.toMatchObject({ code: 'access_lost' })
  expect(rpc).not.toHaveBeenCalled()
})

test('bind compares origin user and session and a replaced session cannot adopt the lease', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const binding = await gateway.bindSelectedShopSession()
  await gateway.assertBoundSession(binding)
  harness.setSession(directorySession('user-a', 'session-a', '2'))
  await gateway.assertBoundSession(binding)
  harness.setSession(directorySession('user-a', 'session-b', '3'))
  await expect(gateway.assertBoundSession(binding)).rejects.toMatchObject({ code: 'access_lost' })
  await expect(gateway.assertBoundSession(binding)).rejects.toMatchObject({ code: 'access_lost' })
})

test('watchBoundSession keeps a same-session refresh and disposes the listener', async () => {
  const listeners: Array<(event: string, session: unknown) => void> = []
  const unsubscribe = vi.fn()
  let session = directorySession('user-a', 'session-a', '1')
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: {
      getSession: vi.fn(async () => ({ data: { session }, error: null })),
      onAuthStateChange: vi.fn((listener: (event: string, session: unknown) => void) => {
        listeners.push(listener)
        return { data: { subscription: { unsubscribe } } }
      }),
    },
    rpc: vi.fn(),
  } as unknown as SupabaseClient)
  const binding = await gateway.bindSelectedShopSession()
  const onLost = vi.fn()
  const stop = gateway.watchBoundSession(binding, onLost)
  session = directorySession('user-a', 'session-a', '2')
  listeners[0]?.('TOKEN_REFRESHED', session)
  expect(onLost).not.toHaveBeenCalled()
  await gateway.assertBoundSession(binding)
  listeners[0]?.('SIGNED_OUT', null)
  expect(onLost).toHaveBeenCalledTimes(1)
  stop()
  expect(unsubscribe).toHaveBeenCalledTimes(1)
})

test('watchBoundSession invalidates at local expiry without another auth event', async () => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-10-22T00:00:00.000Z'))
  try {
    const expiresAt = Math.floor(Date.now() / 1000) + 30
    let session = directorySession('user-a', 'session-a', '1', expiresAt)
    const unsubscribe = vi.fn()
    const gateway = new SupabaseSubscriberDirectoryGateway({
      auth: {
        getSession: vi.fn(async () => ({ data: { session }, error: null })),
        onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe } } })),
      },
      rpc: vi.fn(),
    } as unknown as SupabaseClient)
    const binding = await gateway.bindSelectedShopSession()
    const onLost = vi.fn()
    gateway.watchBoundSession(binding, onLost)
    expect(onLost).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(29_000)
    expect(onLost).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1_000)
    expect(onLost).toHaveBeenCalledTimes(1)
    await expect(gateway.assertBoundSession(binding)).rejects.toMatchObject({ code: 'access_lost' })
  } finally {
    vi.useRealTimers()
  }
})

test('watchBoundSession rearms on refresh and an old timer cannot clear the new lease', async () => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-10-22T00:00:00.000Z'))
  try {
    const listeners: Array<(event: string, session: unknown) => void> = []
    let session = directorySession('user-a', 'session-a', '1', Math.floor(Date.now() / 1000) + 30)
    const gateway = new SupabaseSubscriberDirectoryGateway({
      auth: {
        getSession: vi.fn(async () => ({ data: { session }, error: null })),
        onAuthStateChange: vi.fn((listener: (event: string, session: unknown) => void) => {
          listeners.push(listener)
          return { data: { subscription: { unsubscribe: vi.fn() } } }
        }),
      },
      rpc: vi.fn(),
    } as unknown as SupabaseClient)
    const binding = await gateway.bindSelectedShopSession()
    const onLost = vi.fn()
    gateway.watchBoundSession(binding, onLost)
    session = directorySession('user-a', 'session-a', '2', Math.floor(Date.now() / 1000) + 120)
    listeners[0]?.('TOKEN_REFRESHED', session)
    await vi.advanceTimersByTimeAsync(30_000)
    expect(onLost).not.toHaveBeenCalled()
    await gateway.assertBoundSession(binding)
    await vi.advanceTimersByTimeAsync(90_000)
    expect(onLost).toHaveBeenCalledTimes(1)
  } finally {
    vi.useRealTimers()
  }
})

test('watchBoundSession rearms after a refresh observed only by a session probe', async () => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-10-22T00:00:00.000Z'))
  try {
    let session = directorySession('user-a', 'session-a', '1', Date.now() / 1000 + 30)
    const gateway = new SupabaseSubscriberDirectoryGateway({
      auth: {
        getSession: vi.fn(async () => ({ data: { session }, error: null })),
        onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: vi.fn() } } })),
      },
      rpc: vi.fn(),
    } as unknown as SupabaseClient)
    const binding = await gateway.bindSelectedShopSession()
    const onLost = vi.fn()
    gateway.watchBoundSession(binding, onLost)
    session = directorySession('user-a', 'session-a', '2', Date.now() / 1000 + 120)
    await gateway.assertBoundSession(binding)
    await vi.advanceTimersByTimeAsync(30_000)
    expect(onLost).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(90_000)
    expect(onLost).toHaveBeenCalledTimes(1)
  } finally {
    vi.useRealTimers()
  }
})
test('watchBoundSession rejects NaN Infinity and missing expiry', async () => {
  const listeners: Array<(event: string, session: unknown) => void> = []
  let session = directorySession('user-a', 'session-a', '1')
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: {
      getSession: vi.fn(async () => ({ data: { session }, error: null })),
      onAuthStateChange: vi.fn((listener: (event: string, session: unknown) => void) => {
        listeners.push(listener)
        return { data: { subscription: { unsubscribe: vi.fn() } } }
      }),
    },
    rpc: vi.fn(),
  } as unknown as SupabaseClient)
  const binding = await gateway.bindSelectedShopSession()
  const onLost = vi.fn()
  gateway.watchBoundSession(binding, onLost)
  listeners[0]?.('TOKEN_REFRESHED', { ...session, expires_at: Number.NaN })
  expect(onLost).toHaveBeenCalledTimes(1)

  session = directorySession('user-a', 'session-a', '1')
  const second = await gateway.bindSelectedShopSession()
  const onLostInfinity = vi.fn()
  gateway.watchBoundSession(second, onLostInfinity)
  listeners[1]?.('TOKEN_REFRESHED', { ...session, expires_at: Number.POSITIVE_INFINITY })
  expect(onLostInfinity).toHaveBeenCalledTimes(1)

  session = directorySession('user-a', 'session-a', '1')
  const third = await gateway.bindSelectedShopSession()
  const onLostMissing = vi.fn()
  gateway.watchBoundSession(third, onLostMissing)
  const { expires_at: _dropped, ...withoutExpiry } = session
  void _dropped
  listeners[2]?.('TOKEN_REFRESHED', withoutExpiry)
  expect(onLostMissing).toHaveBeenCalledTimes(1)
})

test('authorizeCopy performs a live subscriber read for the selected shop', async () => {
  const { client: supabase, rpc } = client({ data: detailPayload, error: null })
  const gateway = new SupabaseSubscriberDirectoryGateway(supabase)
  const binding = await gateway.bindSelectedShopSession()
  await gateway.authorizeCopy(binding, 'a1100000-0000-4000-8000-000000000001')
  expect(rpc).toHaveBeenCalledWith('admin_get_subscriber_v1', {
    p_shop_id: 'a1100000-0000-4000-8000-000000000001',
  })
})

test('authorizeCopy reasserts the origin lease after the live read', async () => {
  const origin = directorySession('user-a', 'session-a', '1')
  const replaced = directorySession('user-a', 'session-b', '2')
  let probes = 0
  const rpc = vi.fn().mockResolvedValue({ data: detailPayload, error: null })
  const gateway = new SupabaseSubscriberDirectoryGateway({
    auth: {
      getSession: vi.fn(async () => {
        probes += 1
        return { data: { session: probes >= 5 ? replaced : origin }, error: null }
      }),
    },
    rpc,
  } as unknown as SupabaseClient)
  const binding = await gateway.bindSelectedShopSession()
  await expect(
    gateway.authorizeCopy(binding, 'a1100000-0000-4000-8000-000000000001'),
  ).rejects.toMatchObject({ code: 'access_lost' })
  expect(rpc).toHaveBeenCalledWith('admin_get_subscriber_v1', {
    p_shop_id: 'a1100000-0000-4000-8000-000000000001',
  })
})

test('issue rejects a two-row payload without retrying the write', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseSubscriberDirectoryGateway(harness.client)
  const binding = await gateway.bindSelectedShopSession()
  const promise = gateway.issueSubscriptionCode(issueInput, binding)
  await vi.waitFor(() => expect(harness.pending).toHaveLength(1))
  harness.pending[0]?.({ data: [issueRow, issueRow], error: null })
  await expect(promise).rejects.toMatchObject({ code: 'invalid_response' })
  expect(harness.rpc).toHaveBeenCalledTimes(1)
})

test('history list sends the selected shop and page size', async () => {
  const history = {
    snapshot_at: '2026-10-22T00:30:00.000Z',
    shop_id: 'a1100000-0000-4000-8000-000000000001',
    shop_name: 'متجر',
    row_count: '0',
    page_size: 20,
    rows: [],
    next_cursor: null,
  }
  const { client: supabase, rpc } = client({ data: history, error: null })
  const gateway = new SupabaseSubscriberDirectoryGateway(supabase)
  const page = await gateway.listSubscriptionCodes('a1100000-0000-4000-8000-000000000001', null)
  expect(rpc).toHaveBeenCalledWith('admin_list_subscription_codes_v1', {
    p_shop_id: 'a1100000-0000-4000-8000-000000000001',
    p_cursor: null,
    p_page_size: subscriptionCodePageSize,
  })
  expect(page.rowCount).toBe('0')
})

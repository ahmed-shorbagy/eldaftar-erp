import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { AppVersionError } from './AppVersionGateway.ts'
import { SupabaseAppVersionGateway } from './SupabaseAppVersionGateway.ts'

const listPayload = [
  {
    platform: 'android',
    min_version: '1.0.0',
    message_ar: 'حدّث',
    update_url: 'https://example.com/a',
  },
  {
    platform: 'ios',
    min_version: null,
    message_ar: '',
    update_url: null,
  },
  {
    platform: 'windows',
    min_version: '2.0.0',
    message_ar: 'يلزم',
    update_url: null,
  },
]

function accessToken(sessionId: string, mark: string): string {
  const json = JSON.stringify({
    session_id: sessionId,
    user_metadata: { is_platform_admin: true },
  })
  const segment = btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
  return `eyJhbGciOiJub25lIn0.${segment}.${mark}`
}

function session(userId: string, sessionId: string, mark: string) {
  return {
    access_token: accessToken(sessionId, mark),
    user: { id: userId },
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  }
}

function client(result: { data: unknown; error: { message: string } | null }) {
  const rpc = vi.fn().mockResolvedValue(result)
  const current = session('user-a', 'session-a', 'stable')
  return {
    client: {
      auth: { getSession: vi.fn().mockResolvedValue({ data: { session: current }, error: null }) },
      rpc,
    } as unknown as SupabaseClient,
    rpc,
  }
}

function deferredClient(initial = session('user-a', 'session-a', '1')) {
  let current: ReturnType<typeof session> | null = initial
  const pending: Array<(value: { data: unknown; error: { message: string } | null }) => void> = []
  const rpc = vi.fn(
    () =>
      new Promise<{ data: unknown; error: { message: string } | null }>((resolve) => {
        pending.push(resolve)
      }),
  )
  const supabase = {
    auth: {
      getSession: vi.fn(async () => ({ data: { session: current }, error: null })),
    },
    rpc,
  } as unknown as SupabaseClient
  return {
    client: supabase,
    rpc,
    pending,
    setSession(next: typeof current) {
      current = next
    },
  }
}

test('list calls admin_get_app_version_policy_v1 and parses rows', async () => {
  const { client: supabase, rpc } = client({ data: listPayload, error: null })
  const gateway = new SupabaseAppVersionGateway(supabase)
  const rows = await gateway.list()
  expect(rpc).toHaveBeenCalledWith('admin_get_app_version_policy_v1')
  expect(rows).toEqual([
    {
      platform: 'android',
      minVersion: '1.0.0',
      messageAr: 'حدّث',
      updateUrl: 'https://example.com/a',
    },
    { platform: 'ios', minVersion: null, messageAr: '', updateUrl: null },
    {
      platform: 'windows',
      minVersion: '2.0.0',
      messageAr: 'يلزم',
      updateUrl: null,
    },
  ])
})

test('set sends platform fields to admin_set_app_version_policy_v1', async () => {
  const { client: supabase, rpc } = client({
    data: {
      platform: 'android',
      min_version: '1.2.0',
      message_ar: 'رسالة',
      update_url: null,
      status: 'saved',
    },
    error: null,
  })
  const gateway = new SupabaseAppVersionGateway(supabase)
  const result = await gateway.set({
    platform: 'android',
    minVersion: '1.2.0',
    messageAr: 'رسالة',
    updateUrl: null,
  })
  expect(rpc).toHaveBeenCalledWith('admin_set_app_version_policy_v1', {
    p_platform: 'android',
    p_min_version: '1.2.0',
    p_message_ar: 'رسالة',
    p_update_url: null,
  })
  expect(result.status).toBe('saved')
  expect(result.minVersion).toBe('1.2.0')
})

test('missing session before rpc is unauthorized', async () => {
  const supabase = {
    auth: { getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }) },
    rpc: vi.fn(),
  } as unknown as SupabaseClient
  await expect(new SupabaseAppVersionGateway(supabase).list()).rejects.toBeInstanceOf(
    AppVersionError,
  )
  expect(supabase.rpc).not.toHaveBeenCalled()
})

test('session replaced while list is in flight is unauthorized', async () => {
  const harness = deferredClient()
  const gateway = new SupabaseAppVersionGateway(harness.client)
  const pending = gateway.list()
  await vi.waitFor(() => expect(harness.pending.length).toBe(1))
  harness.setSession(session('user-b', 'session-b', 'replaced'))
  harness.pending[0]!({ data: listPayload, error: null })
  await expect(pending).rejects.toMatchObject({ code: 'unauthorized' })
})

test('forbidden rpc maps to unauthorized', async () => {
  const { client: supabase } = client({
    data: null,
    error: { message: 'forbidden' },
  })
  await expect(new SupabaseAppVersionGateway(supabase).list()).rejects.toMatchObject({
    code: 'unauthorized',
  })
})

test('invalid rpc maps to invalid', async () => {
  const { client: supabase } = client({
    data: null,
    error: { message: 'invalid_version' },
  })
  await expect(
    new SupabaseAppVersionGateway(supabase).set({
      platform: 'ios',
      minVersion: 'bad',
      messageAr: 'x',
      updateUrl: null,
    }),
  ).rejects.toMatchObject({ code: 'invalid' })
})

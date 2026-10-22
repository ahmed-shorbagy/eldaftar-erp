import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SupabaseAdminAuthGateway } from './SupabaseAdminAuthGateway.ts'

function liveSession(emailConfirmedAt: string | null = null, userId = 'admin-1') {
  return {
    expires_at: Math.floor(Date.now() / 1000) + 60 * 60,
    access_token: `token-${userId}`,
    user: { id: userId, email_confirmed_at: emailConfirmedAt },
  }
}

function clientFor(
  session: unknown,
  allowed: boolean,
  onChange: (listener: () => void) => void = () => {},
) {
  const rpc = vi.fn().mockResolvedValue({ data: allowed, error: null })
  const getSession = vi.fn().mockResolvedValue({ data: { session }, error: null })
  const client = {
    auth: {
      getSession,
      onAuthStateChange: (listener: () => void) => { onChange(listener) },
    },
    rpc,
  } as unknown as SupabaseClient
  return { client, rpc, getSession }
}

test('no session never calls the admin role RPC', async () => {
  const { client, rpc } = clientFor(null, true)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('signedOut')
  expect(rpc).not.toHaveBeenCalled()
})

test('a session with email_confirmed_at null still requires the platform-admin grant', async () => {
  const { client, rpc } = clientFor(liveSession(null), true)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('admin')
  expect(rpc).toHaveBeenCalledWith('is_platform_admin')
})

test('ordinary users are denied even when the backend session is live', async () => {
  const { client, rpc } = clientFor(liveSession(null), false)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('denied')
  expect(rpc).toHaveBeenCalledWith('is_platform_admin')
})

test('lost session closes an admin shell on refresh', async () => {
  let session: unknown = liveSession(null)
  let authChanged: (() => void) | undefined
  const rpc = vi.fn().mockResolvedValue({ data: true, error: null })
  const client = {
    auth: {
      getSession: vi.fn().mockImplementation(async () => ({ data: { session }, error: null })),
      onAuthStateChange: (listener: () => void) => { authChanged = listener },
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('admin')

  session = null
  authChanged?.()
  await vi.waitFor(() => expect(gateway.status).toBe('signedOut'))
})

test('an expired session closes access without asking for the admin grant', async () => {
  const session = {
    expires_at: Math.floor(Date.now() / 1000) - 60,
    user: { email_confirmed_at: null },
  }
  const { client, rpc } = clientFor(session, true)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('signedOut')
  expect(rpc).not.toHaveBeenCalled()
})

test('a session without an expiry closes access without asking for the admin grant', async () => {
  const session = { user: { email_confirmed_at: '2026-09-24T00:00:00Z' } }
  const { client, rpc } = clientFor(session, true)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('signedOut')
  expect(rpc).not.toHaveBeenCalled()
})

test('session lookup errors close admin access', async () => {
  const rpc = vi.fn()
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: liveSession() }, error: new Error('lookup failed') }),
      onAuthStateChange: () => {},
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('unavailable')
  expect(rpc).not.toHaveBeenCalled()
})

test('a thrown session lookup closes admin access', async () => {
  const rpc = vi.fn()
  const client = {
    auth: {
      getSession: vi.fn().mockRejectedValue(new Error('offline')),
      onAuthStateChange: () => {},
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('unavailable')
  expect(rpc).not.toHaveBeenCalled()
})

test('platform-admin RPC errors do not grant access', async () => {
  const rpc = vi.fn().mockResolvedValue({ data: null, error: new Error('rpc failed') })
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: liveSession(null) }, error: null }),
      onAuthStateChange: () => {},
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('unavailable')
  expect(rpc).toHaveBeenCalledWith('is_platform_admin')
})

test('password sign-in errors stay signed out and do not check the admin grant', async () => {
  const rpc = vi.fn()
  const signInWithPassword = vi.fn().mockResolvedValue({
    data: { session: null, user: null },
    error: new Error('invalid'),
  })
  const client = {
    auth: {
      getSession: vi.fn(),
      onAuthStateChange: () => {},
      signInWithPassword,
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await expect(gateway.signIn('  admin@example.com  ', 'secret')).rejects.toThrow('invalid')
  expect(signInWithPassword).toHaveBeenCalledWith({ email: 'admin@example.com', password: 'secret' })
  expect(gateway.status).toBe('signedOut')
  expect(rpc).not.toHaveBeenCalled()
})

test('a thrown password sign-in failure closes the attempt', async () => {
  const rpc = vi.fn()
  const client = {
    auth: {
      getSession: vi.fn(),
      onAuthStateChange: () => {},
      signInWithPassword: vi.fn().mockRejectedValue(new Error('network')),
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await expect(gateway.signIn('admin@example.com', 'secret')).rejects.toThrow('network')
  expect(gateway.status).toBe('signedOut')
  expect(rpc).not.toHaveBeenCalled()
})

test('revoking platform-admin closes an open admin session', async () => {
  let session: unknown = liveSession(null)
  let authChanged: (() => void) | undefined
  const rpc = vi.fn()
    .mockResolvedValueOnce({ data: true, error: null })
    .mockResolvedValue({ data: false, error: null })
  const client = {
    auth: {
      getSession: vi.fn().mockImplementation(async () => ({ data: { session }, error: null })),
      onAuthStateChange: (listener: () => void) => { authChanged = listener },
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('admin')

  authChanged?.()
  await vi.waitFor(() => expect(gateway.status).toBe('denied'))
  expect(rpc).toHaveBeenCalledWith('is_platform_admin')
  expect(session).not.toBeNull()
})

test('sign-out clears admin state and ignores an in-flight admin check', async () => {
  const resolvers: Array<(value: { data: boolean; error: null }) => void> = []
  const rpc = vi.fn(() => new Promise((resolve) => {
    resolvers.push(resolve)
  }))
  let resolveSignOut: (value: { error: null }) => void = () => {}
  const getSession = vi.fn().mockResolvedValue({ data: { session: liveSession() }, error: null })
  const client = {
    auth: {
      getSession,
      onAuthStateChange: () => {},
      signOut: vi.fn(() => new Promise((resolve) => {
        resolveSignOut = resolve
      })),
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  const pendingRefresh = gateway.refresh()
  await vi.waitFor(() => expect(resolvers).toHaveLength(1))
  const callsBeforeSignOut = getSession.mock.calls.length
  const pendingOut = gateway.signOut()
  expect(gateway.status).toBe('signedOut')
  resolvers[0]?.({ data: true, error: null })
  await pendingRefresh
  expect(gateway.status).toBe('signedOut')
  resolveSignOut({ error: null })
  await pendingOut
  expect(gateway.status).toBe('signedOut')
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(getSession.mock.calls.length).toBe(callsBeforeSignOut)
  expect(rpc).toHaveBeenCalledTimes(1)
})

test('an auth sign-out event clears admin state without waiting for refresh', async () => {
  let listener: (event: string, session: unknown) => void = () => {}
  const getSession = vi.fn().mockResolvedValue({ data: { session: liveSession() }, error: null })
  const rpc = vi.fn().mockResolvedValue({ data: true, error: null })
  const client = {
    auth: {
      getSession,
      onAuthStateChange: (next: (event: string, session: unknown) => void) => {
        listener = next
      },
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('admin')
  const calls = getSession.mock.calls.length
  listener('SIGNED_OUT', null)
  expect(gateway.status).toBe('signedOut')
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(gateway.status).toBe('signedOut')
  expect(getSession.mock.calls.length).toBe(calls)
})

test('an identity change removes admin state and ignores the previous admin check', async () => {
  let session = liveSession(null, 'user-a')
  const resolvers: Array<(value: { data: boolean; error: null }) => void> = []
  const rpc = vi.fn(() => new Promise((resolve) => {
    resolvers.push(resolve)
  }))
  let listener: (event: string, nextSession: unknown) => void = () => {}
  const client = {
    auth: {
      getSession: vi.fn(async () => ({ data: { session }, error: null })),
      onAuthStateChange: (next: (event: string, nextSession: unknown) => void) => {
        listener = next
      },
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  const first = gateway.refresh()
  await vi.waitFor(() => expect(resolvers).toHaveLength(1))
  resolvers[0]?.({ data: true, error: null })
  await first
  expect(gateway.status).toBe('admin')

  const second = gateway.refresh()
  await vi.waitFor(() => expect(resolvers).toHaveLength(2))
  session = liveSession(null, 'user-b')
  listener('SIGNED_IN', session)
  expect(gateway.status).toBe('checking')
  resolvers[1]?.({ data: true, error: null })
  await second
  expect(gateway.status).toBe('checking')
  await vi.waitFor(() => expect(resolvers).toHaveLength(3))
  resolvers[2]?.({ data: false, error: null })
  await vi.waitFor(() => expect(gateway.status).toBe('denied'))
})

test('a same-user token refresh does not drop admin state before the next check', async () => {
  let listener: (event: string, session: unknown) => void = () => {}
  const rpc = vi.fn().mockResolvedValue({ data: true, error: null })
  const session = liveSession(null, 'admin-1')
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session }, error: null }),
      onAuthStateChange: (next: (event: string, session: unknown) => void) => {
        listener = next
      },
    },
    rpc,
  } as unknown as SupabaseClient
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('admin')
  listener('TOKEN_REFRESHED', { ...session, access_token: 'token-admin-1-next' })
  expect(gateway.status).toBe('admin')
  await vi.waitFor(() => expect(rpc).toHaveBeenCalledTimes(2))
  expect(gateway.status).toBe('admin')
})

import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SupabaseAdminAuthGateway } from './SupabaseAdminAuthGateway.ts'

function liveSession(emailConfirmedAt: string | null = null) {
  return {
    expires_at: Math.floor(Date.now() / 1000) + 60 * 60,
    user: { email_confirmed_at: emailConfirmedAt },
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

import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SupabaseAdminAuthGateway } from './SupabaseAdminAuthGateway.ts'

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

test('verified session still needs a backend platform-admin grant', async () => {
  const session = { user: { email_confirmed_at: '2026-09-24T00:00:00Z' } }
  const { client, rpc } = clientFor(session, false)
  const gateway = new SupabaseAdminAuthGateway(client)
  await gateway.refresh()
  expect(gateway.status).toBe('denied')
  expect(rpc).toHaveBeenCalledWith('is_platform_admin')
})

test('lost session closes an admin shell on refresh', async () => {
  let session: unknown = { user: { email_confirmed_at: '2026-09-24T00:00:00Z' } }
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

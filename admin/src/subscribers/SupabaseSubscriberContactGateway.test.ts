import type { SupabaseClient } from '@supabase/supabase-js'
import { expect, test, vi } from 'vitest'
import { SubscriberContactError } from './SubscriberContactGateway.ts'
import { SupabaseSubscriberContactGateway } from './SupabaseSubscriberContactGateway.ts'

function session(userId: string) {
  return {
    access_token: 'token',
    user: { id: userId },
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  }
}

test('reveal calls admin_get_subscriber_contact_v1 and parses row', async () => {
  const rpc = vi.fn().mockResolvedValue({
    data: {
      shop_id: 'c3100000-0000-4000-8000-000000000001',
      phone: '+201099988877',
      country_code: 'EG',
      location_display_ar: 'الجيزة',
    },
    error: null,
  })
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: session('admin-a') }, error: null }),
    },
    rpc,
  } as unknown as SupabaseClient
  const row = await new SupabaseSubscriberContactGateway(client).reveal(
    'c3100000-0000-4000-8000-000000000001',
  )
  expect(rpc).toHaveBeenCalledWith('admin_get_subscriber_contact_v1', {
    p_shop_id: 'c3100000-0000-4000-8000-000000000001',
  })
  expect(row).toEqual({
    shopId: 'c3100000-0000-4000-8000-000000000001',
    phone: '+201099988877',
    countryCode: 'EG',
    locationDisplayAr: 'الجيزة',
  })
})

test('forbidden rpc maps to forbidden', async () => {
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: session('admin-a') }, error: null }),
    },
    rpc: vi.fn().mockResolvedValue({ data: null, error: { message: 'forbidden' } }),
  } as unknown as SupabaseClient
  await expect(
    new SupabaseSubscriberContactGateway(client).reveal('c3100000-0000-4000-8000-000000000001'),
  ).rejects.toMatchObject({ code: 'forbidden' })
})

test('missing session is unauthorized', async () => {
  const client = {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }),
    },
    rpc: vi.fn(),
  } as unknown as SupabaseClient
  await expect(
    new SupabaseSubscriberContactGateway(client).reveal('c3100000-0000-4000-8000-000000000001'),
  ).rejects.toBeInstanceOf(SubscriberContactError)
  expect(client.rpc).not.toHaveBeenCalled()
})

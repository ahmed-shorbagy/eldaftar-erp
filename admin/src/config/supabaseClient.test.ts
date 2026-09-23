import { createClient } from '@supabase/supabase-js'
import { beforeEach, expect, test, vi } from 'vitest'
import { prepareSupabase } from './supabaseStartup.ts'
import { getSupabaseClient, startSupabase } from './supabaseClient.ts'

vi.mock('@supabase/supabase-js', () => ({
  createClient: vi.fn(() => ({})),
}))

beforeEach(() => {
  vi.mocked(createClient).mockClear()
})

test('does not construct a client when configuration is missing', async () => {
  await expect(
    prepareSupabase(
      { url: 'https://example.supabase.co', publishableKey: ' ' },
      startSupabase,
    ),
  ).resolves.toBe('missingConfiguration')
  expect(createClient).not.toHaveBeenCalled()
})

test('constructs a client only with both trimmed public values', async () => {
  await expect(
    prepareSupabase(
      {
        url: ' https://example.supabase.co ',
        publishableKey: ' public-key ',
      },
      startSupabase,
    ),
  ).resolves.toBe('ready')
  expect(createClient).toHaveBeenCalledTimes(1)
  expect(createClient).toHaveBeenCalledWith(
    'https://example.supabase.co',
    'public-key',
  )
  expect(getSupabaseClient()).toEqual({})
})

test('rejects a direct start when either value is blank', async () => {
  await expect(startSupabase(' ', 'public-key')).rejects.toThrow(
    'Supabase public configuration is incomplete',
  )
  expect(createClient).not.toHaveBeenCalled()
})

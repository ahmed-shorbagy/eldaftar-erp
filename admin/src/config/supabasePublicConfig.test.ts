import { expect, test } from 'vitest'
import {
  isSupabaseConfigComplete,
  readSupabasePublicConfig,
  trimmedPublishableKey,
  trimmedUrl,
} from './supabasePublicConfig.ts'

test('both public values are required', () => {
  expect(
    isSupabaseConfigComplete({ url: '', publishableKey: '' }),
  ).toBe(false)
  expect(
    isSupabaseConfigComplete({
      url: 'https://example.supabase.co',
      publishableKey: '',
    }),
  ).toBe(false)
  expect(
    isSupabaseConfigComplete({ url: '', publishableKey: 'public-key' }),
  ).toBe(false)
  expect(
    isSupabaseConfigComplete({ url: '   ', publishableKey: '   ' }),
  ).toBe(false)
  expect(
    isSupabaseConfigComplete({
      url: ' https://example.supabase.co ',
      publishableKey: ' public-key ',
    }),
  ).toBe(true)
})

test('values are trimmed before use', () => {
  const config = {
    url: ' https://example.supabase.co ',
    publishableKey: ' public-key ',
  }

  expect(trimmedUrl(config)).toBe('https://example.supabase.co')
  expect(trimmedPublishableKey(config)).toBe('public-key')
})

test('reads only the two public vite variables', () => {
  expect(
    readSupabasePublicConfig({
      VITE_SUPABASE_URL: ' https://example.supabase.co ',
      VITE_SUPABASE_PUBLISHABLE_KEY: ' public-key ',
    }),
  ).toEqual({
    url: ' https://example.supabase.co ',
    publishableKey: ' public-key ',
  })
})

test('treats missing environment values as empty strings', () => {
  expect(
    readSupabasePublicConfig({
      VITE_SUPABASE_URL: undefined,
      VITE_SUPABASE_PUBLISHABLE_KEY: undefined,
    }),
  ).toEqual({ url: '', publishableKey: '' })
})

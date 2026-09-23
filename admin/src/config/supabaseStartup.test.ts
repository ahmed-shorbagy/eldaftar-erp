import { expect, test, vi } from 'vitest'
import { prepareSupabase } from './supabaseStartup.ts'

test('does not initialize when either public value is absent', async () => {
  const start = vi.fn<(url: string, publishableKey: string) => Promise<void>>()

  await expect(
    prepareSupabase({ url: '', publishableKey: '' }, start),
  ).resolves.toBe('missingConfiguration')
  await expect(
    prepareSupabase(
      { url: 'https://example.supabase.co', publishableKey: ' ' },
      start,
    ),
  ).resolves.toBe('missingConfiguration')
  await expect(
    prepareSupabase({ url: ' ', publishableKey: 'public-key' }, start),
  ).resolves.toBe('missingConfiguration')
  expect(start).not.toHaveBeenCalled()
})

test('initializes once with both trimmed public values', async () => {
  const start = vi.fn<(url: string, publishableKey: string) => Promise<void>>()

  await expect(
    prepareSupabase(
      {
        url: ' https://example.supabase.co ',
        publishableKey: ' public-key ',
      },
      start,
    ),
  ).resolves.toBe('ready')
  expect(start).toHaveBeenCalledTimes(1)
  expect(start).toHaveBeenCalledWith('https://example.supabase.co', 'public-key')
})

test('reports failure without exposing the initializer error', async () => {
  const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})

  try {
    await expect(
      prepareSupabase(
        { url: 'https://example.supabase.co', publishableKey: 'public-key' },
        () => {
          throw new Error('secret public-key')
        },
      ),
    ).resolves.toBe('failed')
    expect(consoleError).not.toHaveBeenCalled()
  } finally {
    consoleError.mockRestore()
  }
})

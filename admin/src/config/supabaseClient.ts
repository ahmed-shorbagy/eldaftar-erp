import type { SupabaseClient } from '@supabase/supabase-js'

let activeClient: SupabaseClient | null = null

export function getSupabaseClient(): SupabaseClient | null {
  return activeClient
}

/** Creates the public client. Blank values are rejected before the library runs. */
export async function startSupabase(
  url: string,
  publishableKey: string,
): Promise<void> {
  const nextUrl = url.trim()
  const nextKey = publishableKey.trim()
  if (nextUrl === '' || nextKey === '') {
    throw new Error('Supabase public configuration is incomplete')
  }

  const { createClient } = await import('@supabase/supabase-js')
  activeClient = createClient(nextUrl, nextKey)
}

import {
  isSupabaseConfigComplete,
  trimmedPublishableKey,
  trimmedUrl,
  type SupabasePublicConfig,
} from './supabasePublicConfig.ts'

export type SupabaseStartupStatus = 'missingConfiguration' | 'ready' | 'failed'

export type SupabaseStarter = (
  url: string,
  publishableKey: string,
) => Promise<void>

/** Initializes Supabase only when both public values are present. */
export async function prepareSupabase(
  config: SupabasePublicConfig,
  start: SupabaseStarter,
): Promise<SupabaseStartupStatus> {
  if (!isSupabaseConfigComplete(config)) {
    return 'missingConfiguration'
  }

  try {
    await start(trimmedUrl(config), trimmedPublishableKey(config))
    return 'ready'
  } catch {
    return 'failed'
  }
}

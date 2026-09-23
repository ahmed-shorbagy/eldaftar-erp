export interface SupabasePublicConfig {
  readonly url: string
  readonly publishableKey: string
}

export function trimmedUrl(config: SupabasePublicConfig): string {
  return config.url.trim()
}

export function trimmedPublishableKey(config: SupabasePublicConfig): string {
  return config.publishableKey.trim()
}

/** Both public values must be non-empty. Never pass a service-role key. */
export function isSupabaseConfigComplete(config: SupabasePublicConfig): boolean {
  return trimmedUrl(config) !== '' && trimmedPublishableKey(config) !== ''
}

function envString(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

export function readSupabasePublicConfig(
  env: {
    readonly VITE_SUPABASE_URL?: unknown
    readonly VITE_SUPABASE_PUBLISHABLE_KEY?: unknown
  } = import.meta.env,
): SupabasePublicConfig {
  return {
    url: envString(env.VITE_SUPABASE_URL),
    publishableKey: envString(env.VITE_SUPABASE_PUBLISHABLE_KEY),
  }
}

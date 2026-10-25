import type { SupabaseClient } from '@supabase/supabase-js'
import {
  AppVersionError,
  parseAppVersionPolicyList,
  parseAppVersionSetResult,
  type AppVersionGateway,
  type AppVersionSetInput,
  type AppVersionSetResult,
  type AppVersionPolicyRow,
} from './AppVersionGateway.ts'

export class SupabaseAppVersionGateway implements AppVersionGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async list(): Promise<AppVersionPolicyRow[]> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new AppVersionError('unauthorized')
    const { data, error } = await this.client.rpc('admin_get_app_version_policy_v1')
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) {
      throw new AppVersionError('unauthorized')
    }
    if (error) throw mapError(error.message)
    return parseAppVersionPolicyList(data)
  }

  async set(input: AppVersionSetInput): Promise<AppVersionSetResult> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new AppVersionError('unauthorized')
    const { data, error } = await this.client.rpc('admin_set_app_version_policy_v1', {
      p_platform: input.platform,
      p_min_version: input.minVersion,
      p_message_ar: input.messageAr,
      p_update_url: input.updateUrl,
    })
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) {
      throw new AppVersionError('unauthorized')
    }
    if (error) throw mapError(error.message)
    return parseAppVersionSetResult(data)
  }
}

function mapError(message: string | undefined): AppVersionError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('forbidden')
    || text.includes('unauthenticated')
    || text.includes('session_expired')
    || text.includes('42501')
  ) {
    return new AppVersionError('unauthorized')
  }
  if (text.includes('invalid') || text.includes('22023')) {
    return new AppVersionError('invalid')
  }
  return new AppVersionError('unavailable')
}

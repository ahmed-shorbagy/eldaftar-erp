import type { SupabaseClient } from '@supabase/supabase-js'
import {
  OverviewError,
  parseAdminOverview,
  type AdminOverview,
  type OverviewGateway,
} from './OverviewGateway.ts'

export class SupabaseOverviewGateway implements OverviewGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async get(): Promise<AdminOverview> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new OverviewError('unauthorized')
    const { data, error } = await this.client.rpc('admin_get_overview_v1')
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) throw new OverviewError('unauthorized')
    if (error) throw mapOverviewError(error.message)
    return parseAdminOverview(data)
  }
}

export function mapOverviewError(message: string | undefined): OverviewError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('forbidden')
    || text.includes('unauthenticated')
    || text.includes('session_expired')
    || text.includes('42501')
  ) {
    return new OverviewError('unauthorized')
  }
  return new OverviewError('unavailable')
}

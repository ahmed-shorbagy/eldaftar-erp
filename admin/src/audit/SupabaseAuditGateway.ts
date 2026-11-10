import type { SupabaseClient } from '@supabase/supabase-js'
import {
  AuditError,
  parseAuditPage,
  type AuditGateway,
  type AuditPage,
  type AuditQuery,
} from './AuditGateway.ts'

export class SupabaseAuditGateway implements AuditGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async list(query: AuditQuery): Promise<AuditPage> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new AuditError('unauthorized')
    const { data, error } = await this.client.rpc('admin_list_audit_events_v1', {
      p_family: query.family,
      p_actor: query.actorUserId,
      p_cursor: query.cursor,
      p_page_size: 25,
    })
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) throw new AuditError('unauthorized')
    if (error) throw mapAuditError(error.message)
    return parseAuditPage(data)
  }
}

export function mapAuditError(message: string | undefined): AuditError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('forbidden')
    || text.includes('unauthenticated')
    || text.includes('session_expired')
    || text.includes('42501')
  ) {
    return new AuditError('unauthorized')
  }
  if (text.includes('invalid_cursor')) return new AuditError('stale')
  return new AuditError('unavailable')
}

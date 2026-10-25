import type { SupabaseClient } from '@supabase/supabase-js'
import {
  parseSubscriberContact,
  SubscriberContactError,
  type SubscriberContactGateway,
  type SubscriberContactRow,
} from './SubscriberContactGateway.ts'

export class SupabaseSubscriberContactGateway implements SubscriberContactGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async reveal(shopId: string): Promise<SubscriberContactRow> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new SubscriberContactError('unauthorized')
    const { data, error } = await this.client.rpc('admin_get_subscriber_contact_v1', {
      p_shop_id: shopId,
    })
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) {
      throw new SubscriberContactError('unauthorized')
    }
    if (error) throw mapError(error.message)
    return parseSubscriberContact(data)
  }
}

function mapError(message: string | undefined): SubscriberContactError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('unauthenticated')
    || text.includes('session_expired')
  ) {
    return new SubscriberContactError('unauthorized')
  }
  if (text.includes('forbidden') || text.includes('42501')) {
    return new SubscriberContactError('forbidden')
  }
  if (text.includes('not_found') || text.includes('p0002')) {
    return new SubscriberContactError('not_found')
  }
  if (text.includes('invalid') || text.includes('22023')) {
    return new SubscriberContactError('invalid')
  }
  return new SubscriberContactError('unavailable')
}

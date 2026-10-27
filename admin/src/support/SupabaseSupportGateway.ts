import type { SupabaseClient } from '@supabase/supabase-js'
import {
  SupportError,
  parseSupportPage,
  parseSupportUpdate,
  supportPageSize,
  type SupportGateway,
  type SupportListInput,
  type SupportUpdateInput,
} from './SupportGateway.ts'

export class SupabaseSupportGateway implements SupportGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async list(input: SupportListInput) {
    const cursorAt = input.cursorAt
    const cursorId = input.cursorId
    if ((cursorId === null) !== (cursorAt === null)) {
      throw new SupportError('invalid')
    }
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_list_support_inquiries_v1', {
        p_status: statusValue(input.status),
        p_search: searchValue(input.search),
        p_cursor_at: cursorAt,
        p_cursor_id: cursorId,
        p_page_size: supportPageSize,
      })
      if (error) throw mapError(error.message)
      return parseSupportPage(data)
    })
  }

  async updateInquiryStatus(input: SupportUpdateInput) {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_update_support_inquiry_status_v1', {
        p_id: input.inquiryId,
        p_to_status: input.to,
        p_reply_ar: input.replyAr,
        p_idempotency_key: input.idempotencyKey,
      })
      if (error) throw mapError(error.message)
      return parseSupportUpdate(data)
    })
  }

  private async guarded<T>(run: () => Promise<T>): Promise<T> {
    const before = await this.safeSession()
    const userId = before?.user.id
    if (!userId) throw new SupportError('access_lost')
    const result = await run()
    const after = await this.safeSession()
    if (after?.user.id !== userId || after === null) {
      throw new SupportError('access_lost')
    }
    return result
  }

  private async safeSession() {
    try {
      const { data } = await this.client.auth.getSession()
      return data.session
    } catch {
      throw new SupportError('unavailable')
    }
  }
}

function statusValue(status: SupportListInput['status']): string | null {
  return status === 'all' ? null : status
}

function searchValue(search: string): string | null {
  const trimmed = search.trim()
  return trimmed === '' ? null : trimmed
}

function mapError(message: string | undefined): SupportError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('forbidden')
    || text.includes('unauthenticated')
    || text.includes('session_expired')
    || text.includes('unauthorized')
    || text.includes('42501')
  ) {
    return new SupportError('access_lost')
  }
  if (text.includes('stale_cursor')) return new SupportError('stale_cursor')
  if (text.includes('invalid_transition')) return new SupportError('invalid_transition')
  if (text.includes('not_found') || text.includes('p0002')) {
    return new SupportError('not_found')
  }
  if (text.includes('invalid_input') || text.includes('22023') || text.includes('payload_mismatch')) {
    return new SupportError('invalid')
  }
  return new SupportError('unavailable')
}

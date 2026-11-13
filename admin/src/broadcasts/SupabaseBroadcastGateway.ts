import type { SupabaseClient } from '@supabase/supabase-js'
import {
  BroadcastError,
  broadcastPageSize,
  mapBroadcastError,
  parseBroadcastPage,
  parsePreview,
  parseSendResult,
  parseWithdrawResult,
  type AudienceInput,
  type AudiencePreview,
  type BroadcastGateway,
  type BroadcastPage,
  type SendInput,
  type SendResult,
  type WithdrawResult,
} from './BroadcastGateway.ts'

export const broadcastWriteTimeoutMs = 15_000

interface RpcResult {
  data: unknown
  error: { message?: string } | null
}

/**
 * Calls run only while the same user stays signed in before and after the
 * request; a changed or missing session is reported as lost access.
 */
export class SupabaseBroadcastGateway implements BroadcastGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  preview(input: AudienceInput): Promise<AudiencePreview> {
    return this.call(
      () => this.client.rpc('admin_preview_broadcast_audience_v1', {
        p_segment: input.segment,
        p_days: input.days,
        p_shop_id: input.shopId,
      }),
      parsePreview,
    )
  }

  send(input: SendInput): Promise<SendResult> {
    return this.call(
      () => this.client.rpc('admin_send_broadcast_v1', {
        p_request_key: input.requestKey,
        p_segment: input.segment,
        p_days: input.days,
        p_shop_id: input.shopId,
        p_title_ar: input.titleAr,
        p_body_ar: input.bodyAr,
        p_link_url: input.linkUrl,
        p_starts_at: input.startsAt,
        p_ends_at: input.endsAt,
        p_expected_count: input.expectedCount,
      }),
      parseSendResult,
      true,
    )
  }

  withdraw(broadcastId: string, reason: string): Promise<WithdrawResult> {
    return this.call(
      () => this.client.rpc('admin_withdraw_broadcast_v1', {
        p_broadcast_id: broadcastId,
        p_reason: reason,
      }),
      (data) => parseWithdrawResult(data, broadcastId),
      true,
    )
  }

  list(cursor: string | null): Promise<BroadcastPage> {
    return this.call(
      () => this.client.rpc('admin_list_broadcasts_v1', {
        p_cursor: cursor,
        p_page_size: broadcastPageSize,
      }),
      (data) => parseBroadcastPage(data, broadcastPageSize),
    )
  }

  private async call<T>(
    rpc: () => PromiseLike<RpcResult>,
    parse: (data: unknown) => T,
    write = false,
  ): Promise<T> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new BroadcastError('unauthorized')
    const result = write ? await withTimeout(rpc(), broadcastWriteTimeoutMs) : await rpc()
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) throw new BroadcastError('unauthorized')
    if (result.error) throw mapBroadcastError(result.error.message)
    return parse(result.data)
  }
}

async function withTimeout(promise: PromiseLike<RpcResult>, ms: number): Promise<RpcResult> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    return await Promise.race([
      Promise.resolve(promise),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new BroadcastError('timeout')), ms)
      }),
    ])
  } finally {
    if (timer !== undefined) clearTimeout(timer)
  }
}

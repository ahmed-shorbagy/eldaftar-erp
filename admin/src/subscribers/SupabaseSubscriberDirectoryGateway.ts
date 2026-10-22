import type { SupabaseClient } from '@supabase/supabase-js'
import {
  mapSubscriberRpcError,
  SubscriberDirectoryError,
  subscriberPageSize,
  type SubscriberDirectoryGateway,
  type SubscriberQuery,
} from './SubscriberDirectoryGateway.ts'
import {
  parseSubscriberDetail,
  parseSubscriberPage,
  type SubscriberDetail,
  type SubscriberPage,
} from './subscriptionFormat.ts'

interface DirectoryIdentity {
  userId: string
  accessToken: string
  sessionId: string | null
}

type SessionProbe =
  | { state: 'ready'; identity: DirectoryIdentity }
  | { state: 'signed_out' }
  | { state: 'unavailable' }

type RpcResult = { data: unknown; error: { message?: string } | null }

type ReplyContinuation = 'accept' | 'refresh' | 'replaced'

function sessionIdFromAccessToken(accessToken: string): string | null {
  const segment = accessToken.split('.')[1]
  if (segment === undefined || segment.length === 0) return null
  try {
    const normalized = segment.replace(/-/g, '+').replace(/_/g, '/')
    const pad = (4 - (normalized.length % 4)) % 4
    const parsed: unknown = JSON.parse(atob(normalized.padEnd(normalized.length + pad, '=')))
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null
    const sessionId = Object.getOwnPropertyDescriptor(parsed, 'session_id')?.value
    return typeof sessionId === 'string' && sessionId.length > 0 ? sessionId : null
  } catch {
    return null
  }
}

function probeSession(session: {
  access_token?: string | null
  user?: { id?: string | null } | null
} | null): SessionProbe {
  if (session === null) return { state: 'signed_out' }
  const userId = session.user?.id
  const accessToken = session.access_token
  if (
    typeof userId !== 'string'
    || userId.length === 0
    || typeof accessToken !== 'string'
    || accessToken.length === 0
  ) {
    return { state: 'signed_out' }
  }
  return {
    state: 'ready',
    identity: {
      userId,
      accessToken,
      sessionId: sessionIdFromAccessToken(accessToken),
    },
  }
}

function continuation(before: DirectoryIdentity, after: DirectoryIdentity): ReplyContinuation {
  if (before.userId !== after.userId) return 'replaced'
  if (
    before.sessionId !== null
    && after.sessionId !== null
    && before.sessionId !== after.sessionId
  ) {
    return 'replaced'
  }
  if (before.accessToken !== after.accessToken) return 'refresh'
  return 'accept'
}

export class SupabaseSubscriberDirectoryGateway implements SubscriberDirectoryGateway {
  readonly #client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.#client = client
  }

  async list(query: SubscriberQuery): Promise<SubscriberPage> {
    return this.#read(
      () => this.#client.rpc('admin_list_subscribers_v1', {
        p_status: query.status,
        p_search: query.search,
        p_cursor: query.cursor,
        p_page_size: subscriberPageSize,
      }),
      parseSubscriberPage,
    )
  }

  async get(shopId: string): Promise<SubscriberDetail> {
    return this.#read(
      () => this.#client.rpc('admin_get_subscriber_v1', { p_shop_id: shopId }),
      parseSubscriberDetail,
    )
  }

  async #probe(): Promise<SessionProbe> {
    try {
      const { data, error } = await this.#client.auth.getSession()
      if (error) return { state: 'unavailable' }
      return probeSession(data.session)
    } catch {
      return { state: 'unavailable' }
    }
  }

  async #read<T>(call: () => PromiseLike<RpcResult>, parse: (data: unknown) => T): Promise<T> {
    const before = await this.#probe()
    if (before.state === 'signed_out') throw new SubscriberDirectoryError('access_lost')
    if (before.state === 'unavailable') throw new SubscriberDirectoryError('unavailable')
    const result = await call()
    return this.#settle(before.identity, result, call, parse, true)
  }

  async #settle<T>(
    before: DirectoryIdentity,
    result: RpcResult,
    call: () => PromiseLike<RpcResult>,
    parse: (data: unknown) => T,
    allowRetry: boolean,
  ): Promise<T> {
    const after = await this.#probe()
    if (after.state === 'signed_out') throw new SubscriberDirectoryError('access_lost')
    if (after.state === 'unavailable') throw new SubscriberDirectoryError('unavailable')
    const next = continuation(before, after.identity)
    if (next === 'replaced') throw new SubscriberDirectoryError('access_lost')
    if (next === 'refresh') {
      if (!allowRetry) throw new SubscriberDirectoryError('unavailable')
      const retryBefore = await this.#probe()
      if (retryBefore.state === 'signed_out') throw new SubscriberDirectoryError('access_lost')
      if (retryBefore.state === 'unavailable') throw new SubscriberDirectoryError('unavailable')
      if (continuation(before, retryBefore.identity) === 'replaced') {
        throw new SubscriberDirectoryError('access_lost')
      }
      const retry = await call()
      return this.#settle(retryBefore.identity, retry, call, parse, false)
    }
    if (result.error) throw mapSubscriberRpcError(result.error)
    return parse(result.data)
  }
}

import type { SupabaseClient } from '@supabase/supabase-js'
import {
  issueSubscriptionTimeoutMs,
  mapSubscriberRpcError,
  mapSubscriptionCodeRpcError,
  SubscriptionCodeError,
  subscriberPageSize,
  subscriptionCodePageSize,
  type IssueSubscriptionCodeInput,
  type SubscriberDirectoryGateway,
  type SubscriberQuery,
  type SubscriptionSessionBinding,
} from './SubscriberDirectoryGateway.ts'
import {
  parseIssuedSubscriptionCode,
  parseSubscriptionCodePage,
  type IssuedSubscriptionCode,
  type SubscriptionCodePage,
} from './subscriptionCodes.ts'
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
  expiresAt: number | null
}

interface BoundIdentity {
  userId: string
  accessToken: string
  sessionId: string
  expiresAt: number
  timerGen: number
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
  expires_at?: number | null
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
      expiresAt: typeof session.expires_at === 'number' ? session.expires_at : null,
    },
  }
}

function finiteExpirySeconds(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function probeCodeSession(session: {
  access_token?: string | null
  expires_at?: number | null
  user?: { id?: string | null } | null
} | null): SessionProbe {
  const probe = probeSession(session)
  if (probe.state !== 'ready') return probe
  if (probe.identity.sessionId === null) return { state: 'signed_out' }
  const expiresAt = finiteExpirySeconds(session?.expires_at)
  if (expiresAt === null || expiresAt * 1000 <= Date.now()) {
    return { state: 'signed_out' }
  }
  return {
    state: 'ready',
    identity: {
      ...probe.identity,
      expiresAt,
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
  if (before.sessionId === null || after.sessionId === null) {
    if (before.sessionId !== after.sessionId) return 'replaced'
  }
  if (before.accessToken !== after.accessToken) return 'refresh'
  return 'accept'
}

export class SupabaseSubscriberDirectoryGateway implements SubscriberDirectoryGateway {
  readonly #client: SupabaseClient
  readonly #leases = new Map<string, BoundIdentity>()
  readonly #expiryTimers = new Map<string, ReturnType<typeof setTimeout>>()

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

  async listSubscriptionCodes(shopId: string, cursor: string | null): Promise<SubscriptionCodePage> {
    return this.#read(
      () => this.#client.rpc('admin_list_subscription_codes_v1', {
        p_shop_id: shopId,
        p_cursor: cursor,
        p_page_size: subscriptionCodePageSize,
      }),
      (data) => parseSubscriptionCodePage(data, {
        shopId,
        pageSize: subscriptionCodePageSize,
        cursor,
      }),
      mapSubscriptionCodeReadError,
      true,
    )
  }

  async issueSubscriptionCode(
    input: IssueSubscriptionCodeInput,
    binding: SubscriptionSessionBinding,
  ): Promise<IssuedSubscriptionCode> {
    return this.#write(
      binding,
      () => this.#client.rpc('issue_subscription_code', {
        p_shop_id: input.shopId,
        p_duration_days: input.durationDays,
        p_code_ttl_days: input.codeTtlDays,
        p_request_key: input.requestKey,
      }),
      (data) => parseIssuedSubscriptionCode(data, {
        shopId: input.shopId,
        requestKey: input.requestKey,
        durationDays: input.durationDays,
      }),
    )
  }

  async bindSelectedShopSession(): Promise<SubscriptionSessionBinding> {
    const identity = await this.#requireCodeIdentity()
    const id = crypto.randomUUID()
    this.#leases.set(id, identity)
    return { id }
  }

  async assertBoundSession(binding: SubscriptionSessionBinding): Promise<void> {
    const origin = this.#requireLease(binding)
    const current = await this.#requireCodeIdentity()
    this.#assertSameLease(origin, current, binding)
    origin.accessToken = current.accessToken
    origin.expiresAt = current.expiresAt
  }

  async authorizeCopy(binding: SubscriptionSessionBinding, shopId: string): Promise<void> {
    await this.assertBoundSession(binding)
    await this.get(shopId)
    await this.assertBoundSession(binding)
  }

  watchBoundSession(binding: SubscriptionSessionBinding, onLost: () => void): () => void {
    let cancelled = false
    const lose = () => {
      if (cancelled) return
      cancelled = true
      this.#clearExpiry(binding.id)
      this.#leases.delete(binding.id)
      onLost()
    }
    const origin = this.#leases.get(binding.id)
    if (origin === undefined || !Number.isFinite(origin.expiresAt)) {
      lose()
      return () => {}
    }
    this.#armExpiry(binding, lose)
    const auth = this.#client.auth as {
      onAuthStateChange?: (
        listener: (event: string, session: {
          access_token?: string | null
          expires_at?: number | null
          user?: { id?: string | null } | null
        } | null) => void,
      ) => { data: { subscription: { unsubscribe: () => void } } }
    }
    if (typeof auth.onAuthStateChange !== 'function') {
      return () => {
        cancelled = true
        this.#clearExpiry(binding.id)
      }
    }
    const { data } = auth.onAuthStateChange((event, session) => {
      if (cancelled) return
      const held = this.#leases.get(binding.id)
      if (held === undefined) {
        lose()
        return
      }
      if (event === 'SIGNED_OUT' || session === null) {
        lose()
        return
      }
      const probe = probeCodeSession(session)
      if (probe.state !== 'ready' || probe.identity.sessionId === null) {
        lose()
        return
      }
      if (
        probe.identity.userId !== held.userId
        || probe.identity.sessionId !== held.sessionId
      ) {
        lose()
        return
      }
      const expiresAt = finiteExpirySeconds(probe.identity.expiresAt)
      if (expiresAt === null) {
        lose()
        return
      }
      held.accessToken = probe.identity.accessToken
      held.expiresAt = expiresAt
      this.#armExpiry(binding, lose)
    })
    return () => {
      cancelled = true
      this.#bumpTimer(binding.id)
      this.#clearExpiry(binding.id)
      data.subscription.unsubscribe()
    }
  }

  releaseBoundSession(binding: SubscriptionSessionBinding): void {
    this.#bumpTimer(binding.id)
    this.#clearExpiry(binding.id)
    this.#leases.delete(binding.id)
  }

  async #requireCodeIdentity(): Promise<BoundIdentity> {
    const probe = await this.#probe(true)
    if (probe.state === 'signed_out') throw new SubscriptionCodeError('access_lost')
    if (probe.state === 'unavailable') throw new SubscriptionCodeError('unavailable')
    if (probe.identity.sessionId === null) throw new SubscriptionCodeError('access_lost')
    const expiresAt = finiteExpirySeconds(probe.identity.expiresAt)
    if (expiresAt === null) throw new SubscriptionCodeError('access_lost')
    return {
      userId: probe.identity.userId,
      accessToken: probe.identity.accessToken,
      sessionId: probe.identity.sessionId,
      expiresAt,
      timerGen: 0,
    }
  }

  #requireLease(binding: SubscriptionSessionBinding | null | undefined): BoundIdentity {
    if (binding == null || typeof binding.id !== 'string' || binding.id.length === 0) {
      throw new SubscriptionCodeError('access_lost')
    }
    const origin = this.#leases.get(binding.id)
    if (origin === undefined) throw new SubscriptionCodeError('access_lost')
    return origin
  }

  #assertSameLease(
    origin: BoundIdentity,
    current: DirectoryIdentity | BoundIdentity,
    binding: SubscriptionSessionBinding,
  ): void {
    if (
      current.sessionId === null
      || current.userId !== origin.userId
      || current.sessionId !== origin.sessionId
    ) {
      this.#bumpTimer(binding.id)
      this.#clearExpiry(binding.id)
      this.#leases.delete(binding.id)
      throw new SubscriptionCodeError('access_lost')
    }
  }

  #bumpTimer(id: string): void {
    const origin = this.#leases.get(id)
    if (origin !== undefined) origin.timerGen += 1
  }

  #clearExpiry(id: string): void {
    const timer = this.#expiryTimers.get(id)
    if (timer !== undefined) {
      clearTimeout(timer)
      this.#expiryTimers.delete(id)
    }
  }

  #armExpiry(binding: SubscriptionSessionBinding, onLost: () => void): void {
    const origin = this.#leases.get(binding.id)
    this.#clearExpiry(binding.id)
    if (origin === undefined || !Number.isFinite(origin.expiresAt)) {
      onLost()
      return
    }
    const delay = origin.expiresAt * 1000 - Date.now()
    const gen = ++origin.timerGen
    if (delay <= 0) {
      this.#leases.delete(binding.id)
      onLost()
      return
    }
    const timer = setTimeout(() => {
      const current = this.#leases.get(binding.id)
      if (current === undefined || current.timerGen !== gen) return
      if (current.expiresAt * 1000 > Date.now()) {
        this.#armExpiry(binding, onLost)
        return
      }
      this.#clearExpiry(binding.id)
      this.#leases.delete(binding.id)
      onLost()
    }, delay)
    this.#expiryTimers.set(binding.id, timer)
  }

  async #probe(codePath: boolean): Promise<SessionProbe> {
    try {
      const { data, error } = await this.#client.auth.getSession()
      if (error) return { state: 'unavailable' }
      return codePath ? probeCodeSession(data.session) : probeSession(data.session)
    } catch {
      return { state: 'unavailable' }
    }
  }

  async #read<T>(
    call: () => PromiseLike<RpcResult>,
    parse: (data: unknown) => T,
    mapError: (error: { message?: string }) => Error = mapSubscriberRpcError,
    codePath = false,
  ): Promise<T> {
    const before = await this.#probe(codePath)
    if (before.state === 'signed_out') throw mapError({ message: 'unauthenticated' })
    if (before.state === 'unavailable') throw mapError({ message: 'unavailable' })
    const result = await call()
    return this.#settle(before.identity, result, call, parse, true, mapError, true, codePath, null)
  }

  async #write<T>(
    binding: SubscriptionSessionBinding,
    call: () => PromiseLike<RpcResult>,
    parse: (data: unknown) => T,
  ): Promise<T> {
    this.#requireLease(binding)
    const before = await this.#probe(true)
    if (before.state === 'signed_out') throw new SubscriptionCodeError('access_lost')
    if (before.state === 'unavailable') throw new SubscriptionCodeError('unavailable')
    const origin = this.#requireLease(binding)
    this.#assertSameLease(origin, before.identity, binding)
    origin.accessToken = before.identity.accessToken
    const expiresAt = finiteExpirySeconds(before.identity.expiresAt)
    if (expiresAt !== null) origin.expiresAt = expiresAt
    const result = await withTimeout(call(), issueSubscriptionTimeoutMs)
    return this.#settle(
      before.identity,
      result,
      call,
      parse,
      false,
      mapSubscriptionCodeRpcError,
      false,
      true,
      binding,
    )
  }

  async #settle<T>(
    before: DirectoryIdentity,
    result: RpcResult,
    call: () => PromiseLike<RpcResult>,
    parse: (data: unknown) => T,
    allowRetry: boolean,
    mapError: (error: { message?: string }) => Error,
    retryReads: boolean,
    codePath: boolean,
    binding: SubscriptionSessionBinding | null,
  ): Promise<T> {
    const after = await this.#probe(codePath)
    if (after.state === 'signed_out') throw mapError({ message: 'unauthenticated' })
    if (after.state === 'unavailable') throw mapError({ message: 'unavailable' })
    if (binding !== null) {
      this.#assertSameLease(this.#requireLease(binding), after.identity, binding)
    }
    const next = continuation(before, after.identity)
    if (next === 'replaced') throw mapError({ message: 'unauthenticated' })
    if (next === 'refresh') {
      if (!retryReads || !allowRetry) {
        if (!retryReads) {
          if (result.error) throw mapError(result.error)
          return parse(result.data)
        }
        throw mapError({ message: 'unavailable' })
      }
      const retryBefore = await this.#probe(codePath)
      if (retryBefore.state === 'signed_out') throw mapError({ message: 'unauthenticated' })
      if (retryBefore.state === 'unavailable') throw mapError({ message: 'unavailable' })
      if (binding !== null) {
        this.#assertSameLease(this.#requireLease(binding), retryBefore.identity, binding)
      }
      if (continuation(before, retryBefore.identity) === 'replaced') {
        throw mapError({ message: 'unauthenticated' })
      }
      const retry = await call()
      return this.#settle(
        retryBefore.identity,
        retry,
        call,
        parse,
        false,
        mapError,
        retryReads,
        codePath,
        binding,
      )
    }
    if (result.error) throw mapError(result.error)
    return parse(result.data)
  }
}

function mapSubscriptionCodeReadError(error: { message?: string }): SubscriptionCodeError {
  const mapped = mapSubscriptionCodeRpcError(error)
  if (mapped.code === 'access_lost' || mapped.code === 'stale_cursor' || mapped.code === 'not_found') {
    return mapped
  }
  if (error.message === 'unavailable') return new SubscriptionCodeError('unavailable')
  return mapped
}

async function withTimeout(promise: PromiseLike<RpcResult>, ms: number): Promise<RpcResult> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    return await Promise.race([
      Promise.resolve(promise),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          reject(new SubscriptionCodeError('timeout'))
        }, ms)
      }),
    ])
  } finally {
    if (timer !== undefined) clearTimeout(timer)
  }
}

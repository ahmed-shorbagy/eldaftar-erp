export type SubscriberStatusFilter = 'all' | 'pending' | 'active' | 'expired'

export type SubscriberDirectoryErrorCode =
  | 'access_lost'
  | 'stale_cursor'
  | 'not_found'
  | 'invalid_response'
  | 'unavailable'

export class SubscriberDirectoryError extends Error {
  readonly code: SubscriberDirectoryErrorCode

  constructor(code: SubscriberDirectoryErrorCode) {
    super(code)
    this.name = 'SubscriberDirectoryError'
    this.code = code
  }
}

export interface SubscriberQuery {
  status: SubscriberStatusFilter
  search: string
  cursor: string | null
}

export type SubscriptionCodeErrorCode =
  | SubscriberDirectoryErrorCode
  | 'timeout'
  | 'invalid_range'
  | 'request_conflict'

export class SubscriptionCodeError extends Error {
  readonly code: SubscriptionCodeErrorCode

  constructor(code: SubscriptionCodeErrorCode) {
    super(code)
    this.name = 'SubscriptionCodeError'
    this.code = code
  }
}

export interface IssueSubscriptionCodeInput {
  shopId: string
  durationDays: number
  codeTtlDays: number
  requestKey: string
}

export interface SubscriptionSessionBinding {
  readonly id: string
}

export interface SubscriberDirectoryGateway {
  list(query: SubscriberQuery): Promise<import('./subscriptionFormat.ts').SubscriberPage>
  get(shopId: string): Promise<import('./subscriptionFormat.ts').SubscriberDetail>
  issueSubscriptionCode(
    input: IssueSubscriptionCodeInput,
    binding: SubscriptionSessionBinding,
  ): Promise<import('./subscriptionCodes.ts').IssuedSubscriptionCode>
  listSubscriptionCodes(
    shopId: string,
    cursor: string | null,
  ): Promise<import('./subscriptionCodes.ts').SubscriptionCodePage>
  bindSelectedShopSession(): Promise<SubscriptionSessionBinding>
  assertBoundSession(binding: SubscriptionSessionBinding): Promise<void>
  authorizeCopy(binding: SubscriptionSessionBinding, shopId: string): Promise<void>
  watchBoundSession(binding: SubscriptionSessionBinding, onLost: () => void): () => void
  releaseBoundSession(binding: SubscriptionSessionBinding): void
}

export const subscriptionCodePageSize = 20
export const issueSubscriptionTimeoutMs = 15_000

export const subscriberPageSize = 20

export function mapSubscriberRpcError(error: { message?: string }): SubscriberDirectoryError {
  const message = error.message ?? ''
  if (/(unauthenticated|forbidden|session_expired|permission denied)/i.test(message)) {
    return new SubscriberDirectoryError('access_lost')
  }
  if (/stale_cursor|invalid_cursor/.test(message)) {
    return new SubscriberDirectoryError('stale_cursor')
  }
  if (/\bnot_found\b/.test(message)) {
    return new SubscriberDirectoryError('not_found')
  }
  return new SubscriberDirectoryError('unavailable')
}

export function mapSubscriptionCodeRpcError(error: { message?: string }): SubscriptionCodeError {
  const message = error.message ?? ''
  if (/(unauthenticated|forbidden|session_expired|permission denied|unauthorized)/i.test(message)) {
    return new SubscriptionCodeError('access_lost')
  }
  if (/stale_cursor|invalid_cursor/.test(message)) {
    return new SubscriptionCodeError('stale_cursor')
  }
  if (/\bshop_not_found\b|\bnot_found\b/.test(message)) {
    return new SubscriptionCodeError('not_found')
  }
  if (/invalid_input|invalid_shop|invalid_page_size/.test(message)) {
    return new SubscriptionCodeError('invalid_range')
  }
  if (/request_key_reused/.test(message)) {
    return new SubscriptionCodeError('request_conflict')
  }
  return new SubscriptionCodeError('unavailable')
}

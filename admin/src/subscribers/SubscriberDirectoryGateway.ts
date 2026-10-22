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

export interface SubscriberDirectoryGateway {
  list(query: SubscriberQuery): Promise<import('./subscriptionFormat.ts').SubscriberPage>
  get(shopId: string): Promise<import('./subscriptionFormat.ts').SubscriberDetail>
}

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

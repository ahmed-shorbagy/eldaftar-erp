import {
  type SubscriberDirectoryGateway,
  type SubscriptionSessionBinding,
} from '../subscribers/SubscriberDirectoryGateway.ts'
import type { SubscriptionCodePage } from '../subscribers/subscriptionCodes.ts'

const testBinding: SubscriptionSessionBinding = { id: 'test-lease' }

export function unusedSubscriptionCodeMethods(): Pick<
  SubscriberDirectoryGateway,
  | 'issueSubscriptionCode'
  | 'listSubscriptionCodes'
  | 'bindSelectedShopSession'
  | 'assertBoundSession'
  | 'authorizeCopy'
  | 'watchBoundSession'
  | 'releaseBoundSession'
> {
  return {
    async issueSubscriptionCode() {
      throw new Error('unused')
    },
    async listSubscriptionCodes(shopId: string): Promise<SubscriptionCodePage> {
      return {
        snapshotAt: '2026-10-22T00:30:00.000Z',
        shopId,
        shopName: '—',
        rowCount: '0',
        pageSize: 20,
        rows: [],
        nextCursor: null,
      }
    },
    async bindSelectedShopSession() {
      return testBinding
    },
    async assertBoundSession() {},
    async authorizeCopy() {},
    watchBoundSession() {
      return () => {}
    },
    releaseBoundSession() {},
  }
}

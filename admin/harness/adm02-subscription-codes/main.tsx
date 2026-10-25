import { createRoot } from 'react-dom/client'
import '../../src/theme/fonts.css'
import { App } from '../../src/App.tsx'
import { ThemeController } from '../../src/theme/themeController.ts'
import { tokens } from '../../src/theme/tokens.ts'
import type { AdminAccess, AdminAuthGateway } from '../../src/auth/AdminAuthGateway.ts'
import { SubscriberDirectoryError, type SubscriberDirectoryGateway } from '../../src/subscribers/SubscriberDirectoryGateway.ts'
import type { SubscriberRow } from '../../src/subscribers/subscriptionFormat.ts'

const params = new URLSearchParams(location.search)
const scale = params.get('scale') === '1.7' ? 1.7 : 1
for (const key of ['bodySize', 'detailSize', 'labelSize', 'titleSize', 'figureSize'] as const) {
  Object.assign(tokens, { [key]: tokens[key] * scale })
}
document.documentElement.style.fontSize = String(16 * scale) + 'px'

class SyntheticAuth implements AdminAuthGateway {
  status: AdminAccess = 'admin'
  listeners = new Set<(s: AdminAccess) => void>()
  subscribe(fn: (s: AdminAccess) => void) {
    this.listeners.add(fn)
    return () => { this.listeners.delete(fn) }
  }
  async refresh() {}
  async signIn() {}
  async signOut() {
    this.status = 'signedOut'
    this.listeners.forEach((fn) => fn(this.status))
  }
}

const snapshotAt = '2026-10-22T08:30:45.000Z'
const shop: SubscriberRow = {
  shopId: 'd2100000-0000-4000-8000-000000000001',
  shopName: 'مجوهرات النور التجريبية — إصدار الرموز',
  registeredAt: '2026-10-01T21:30:00.000Z',
  entitlementStartsAt: '2026-10-01T00:00:00.000Z',
  entitlementExpiresAt: '2027-10-01T00:00:00.000Z',
  subscriptionStatus: 'active',
}

const fakeCode = 'SYNTHETICDISPLAYCODE000000000000'
const historyRows = [
  {
    id: 'd2400000-0000-4000-8000-000000000001',
    issuedAt: '2026-10-20T08:00:00.000Z',
    durationDays: 30,
    codeTtlDays: 30,
    codeExpiresAt: '2026-11-19T08:00:00.000Z',
    issuedVia: 'platform_admin' as const,
    codeStatus: 'unused' as const,
    redeemedAt: null,
  },
  {
    id: 'd2400000-0000-4000-8000-000000000002',
    issuedAt: '2026-09-01T08:00:00.000Z',
    durationDays: 90,
    codeTtlDays: 14,
    codeExpiresAt: '2026-09-15T08:00:00.000Z',
    issuedVia: 'service_role' as const,
    codeStatus: 'expired' as const,
    redeemedAt: null,
  },
]

const gateway: SubscriberDirectoryGateway = {
  async list() {
    return {
      snapshotAt,
      counts: { all: '1', active: '1', pending: '0', expired: '0' },
      filteredCount: '1',
      pageSize: 20,
      rows: [shop],
      nextCursor: null,
    }
  },
  async get(id) {
    if (id !== shop.shopId) throw new SubscriberDirectoryError('not_found')
    return { snapshotAt, ...shop }
  },
  async listSubscriptionCodes() {
    if (params.get('history') === 'error') throw new SubscriberDirectoryError('unavailable')
    if (params.get('history') === 'empty') {
      return {
        snapshotAt,
        shopId: shop.shopId,
        shopName: shop.shopName,
        rowCount: '0',
        pageSize: 20,
        rows: [],
        nextCursor: null,
      }
    }
    return {
      snapshotAt,
      shopId: shop.shopId,
      shopName: shop.shopName,
      rowCount: '2',
      pageSize: 20,
      rows: historyRows,
      nextCursor: null,
    }
  },
  async issueSubscriptionCode() {
    if (params.get('issue') === 'replay') {
      return {
        status: 'replayed',
        code: null,
        shopId: shop.shopId,
        durationDays: 30,
        codeExpiresAt: '2026-11-21T00:00:00.000Z',
        requestKey: 'd2300000-0000-4000-8000-000000000011',
        issuedVia: 'platform_admin',
      }
    }
    return {
      status: 'issued',
      code: fakeCode,
      shopId: shop.shopId,
      durationDays: 30,
      codeExpiresAt: '2026-11-21T00:00:00.000Z',
      requestKey: 'd2300000-0000-4000-8000-000000000011',
      issuedVia: 'platform_admin',
    }
  },
  async bindSelectedShopSession() { return { id: 'synthetic-lease' } },
  async assertBoundSession() {},
  async authorizeCopy() {},
  watchBoundSession() { return () => {} },
  releaseBoundSession() {},
}

const store = {
  value: params.get('theme') === 'light' ? 'light' : 'dark',
  read() { return this.value },
  write(value: string) { this.value = value },
}

createRoot(document.getElementById('root')!).render(
  <>
    <p style={{ margin: 0, padding: '8px', fontFamily: 'Cairo', textAlign: 'center' }}>
      بيانات تجريبية للتحقق البصري — لا تتصل بالخادم ولا تعرض رمزاً حقيقياً
    </p>
    <App
      supabaseStatus="ready"
      authGateway={new SyntheticAuth()}
      subscriberGateway={gateway}
      themeController={new ThemeController(store)}
    />
  </>,
)

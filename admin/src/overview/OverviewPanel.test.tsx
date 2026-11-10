import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import { subscriberCopy } from '../subscribers/copy.ts'
import type {
  SubscriberDirectoryGateway,
  SubscriberQuery,
} from '../subscribers/SubscriberDirectoryGateway.ts'
import { formatServerInstant } from '../subscribers/subscriptionFormat.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'
import { overviewCopy } from './copy.ts'
import { OverviewError, type AdminOverview, type OverviewGateway } from './OverviewGateway.ts'

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null = 'light'
  read(): string | null {
    return this.value
  }
  write(value: string): void {
    this.value = value
  }
}

class StableAuth implements AdminAuthGateway {
  status: AdminAccess = 'admin'
  refresh = vi.fn(async (): Promise<void> => {})
  subscribe(): () => void {
    return () => {}
  }
  async signIn(): Promise<void> {}
  async signOut(): Promise<void> {}
}

const overview: AdminOverview = {
  snapshotAt: '2026-11-10T10:00:00.000Z',
  subscriptions: { all: '1234', active: '5', pending: '4', expired: '3' },
  expiring: { within3Days: '1', within7Days: '2', within30Days: '4' },
  registrations: { last7Days: '2', last30Days: '6' },
  support: { new: '3', inProgress: '1', answered: '0' },
  appVersions: [
    { platform: 'android', minVersion: '1.2.0' },
    { platform: 'ios', minVersion: null },
    { platform: 'windows', minVersion: null },
  ],
  announcementPublished: false,
}

function directory(seen: SubscriberQuery[]): SubscriberDirectoryGateway {
  return {
    async list(query) {
      seen.push(query)
      return {
        snapshotAt: '2026-11-10T10:00:00.000Z',
        counts: { all: '1234', active: '5', pending: '4', expired: '3' },
        filteredCount: '0',
        pageSize: 20,
        rows: [],
        nextCursor: null,
      }
    },
    async get() { throw new Error('unused') },
    async issueSubscriptionCode() { throw new Error('unused') },
    async listSubscriptionCodes() { throw new Error('unused') },
    async bindSelectedShopSession() { return { id: 'lease-1' } },
    async assertBoundSession() {},
    async authorizeCopy() {},
    watchBoundSession() { return () => {} },
    releaseBoundSession() {},
  }
}

function renderOverview(gateway: OverviewGateway, seen: SubscriberQuery[] = []) {
  const auth = new StableAuth()
  render(
    <App
      supabaseStatus="ready"
      authGateway={auth}
      overviewGateway={gateway}
      subscriberGateway={directory(seen)}
      contactGateway={null}
      appVersionGateway={null}
      helpGateway={null}
      supportGateway={null}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  return auth
}

test('the home page shows every figure from one snapshot', async () => {
  renderOverview({ get: async () => overview })
  expect(await screen.findByRole('heading', { level: 2, name: overviewCopy.title })).toBeInTheDocument()
  expect(screen.getByRole('link', { name: overviewCopy.navLabel })).toHaveAttribute('aria-current', 'page')
  expect(screen.getByTestId('overview-snapshot')).toHaveTextContent(formatServerInstant(overview.snapshotAt))
  const subscriptions = screen.getByRole('region', { name: overviewCopy.subscriptionsTitle })
  expect(within(subscriptions).getByRole('link', { name: `${overviewCopy.showList(overviewCopy.allShops)} (1234)` }))
    .toHaveAttribute('href', '/subscribers')
  expect(within(subscriptions).getByText('1,234')).toBeInTheDocument()
  const expiring = screen.getByRole('region', { name: overviewCopy.expiringTitle })
  expect(within(expiring).getByRole('link', { name: `${overviewCopy.showList(overviewCopy.within7)} (2)` }))
    .toHaveAttribute('href', '/subscribers?status=expiring_7')
  const registrations = screen.getByRole('region', { name: overviewCopy.registrationsTitle })
  expect(within(registrations).queryAllByRole('link')).toHaveLength(0)
  expect(within(registrations).getByRole('group', { name: `${overviewCopy.last30}: 6` })).toBeInTheDocument()
  const support = screen.getByRole('region', { name: overviewCopy.supportTitle })
  expect(within(support).getByRole('group', { name: `${overviewCopy.supportNew}: 3` })).toBeInTheDocument()
  expect(within(support).getByRole('link', { name: overviewCopy.openSupport })).toHaveAttribute('href', '/support')
  const app = screen.getByRole('region', { name: overviewCopy.appTitle })
  expect(within(app).getByText(overviewCopy.minimum('1.2.0'))).toBeInTheDocument()
  expect(within(app).getAllByText(overviewCopy.noMinimum)).toHaveLength(2)
  expect(within(app).getByText(overviewCopy.announcementNone)).toBeInTheDocument()
})

test('an expiring figure opens the filtered subscriber list, and clearing returns to all shops', async () => {
  const user = userEvent.setup()
  const seen: SubscriberQuery[] = []
  renderOverview({ get: async () => overview }, seen)
  const expiring = await screen.findByRole('region', { name: overviewCopy.expiringTitle })
  await user.click(within(expiring).getByRole('link', { name: `${overviewCopy.showList(overviewCopy.within7)} (2)` }))
  expect(window.location.pathname + window.location.search).toBe('/subscribers?status=expiring_7')
  expect(await screen.findByText(subscriberCopy.expiringFilter7)).toBeInTheDocument()
  await waitFor(() => expect(seen.at(-1)?.status).toBe('expiring_7'))

  await user.click(screen.getByRole('button', { name: subscriberCopy.clearExpiringFilter }))
  await waitFor(() => expect(seen.at(-1)?.status).toBe('all'))
  expect(window.location.pathname + window.location.search).toBe('/subscribers')
  expect(screen.queryByText(subscriberCopy.expiringFilter7)).not.toBeInTheDocument()
})

test('a shared filtered link applies its filter on first load', async () => {
  const seen: SubscriberQuery[] = []
  window.history.replaceState(null, '', '/subscribers?status=expiring_30')
  renderOverview({ get: async () => overview }, seen)
  expect(await screen.findByText(subscriberCopy.expiringFilter30)).toBeInTheDocument()
  expect(seen[0]?.status).toBe('expiring_30')
})

test('a load failure offers a retry that loads the figures', async () => {
  const user = userEvent.setup()
  let fail = true
  renderOverview({
    get: async () => {
      if (fail) throw new OverviewError('unavailable')
      return overview
    },
  })
  expect(await screen.findByText(overviewCopy.loadError)).toBeInTheDocument()
  fail = false
  await user.click(screen.getByRole('button', { name: overviewCopy.retry }))
  expect(await screen.findByRole('region', { name: overviewCopy.subscriptionsTitle })).toBeInTheDocument()
  expect(screen.queryByText(overviewCopy.loadError)).not.toBeInTheDocument()
})

test('access loss removes the figures and rechecks the session', async () => {
  const auth = renderOverview({ get: async () => { throw new OverviewError('unauthorized') } })
  await waitFor(() => expect(auth.refresh).toHaveBeenCalled())
  expect(screen.queryByRole('region', { name: overviewCopy.subscriptionsTitle })).not.toBeInTheDocument()
  expect(screen.queryByText(overviewCopy.loadError)).not.toBeInTheDocument()
})

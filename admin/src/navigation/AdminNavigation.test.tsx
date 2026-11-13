import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import type { HelpGateway } from '../help/HelpGateway.ts'
import { helpCopy } from '../help/copy.ts'
import { shellCopy } from '../shell/copy.ts'
import { subscriberCopy } from '../subscribers/copy.ts'
import type { SubscriberDirectoryGateway } from '../subscribers/SubscriberDirectoryGateway.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'

const shopId = 'a1100000-0000-4000-8000-000000000001'
const desktopMatchMedia = window.matchMedia

afterEach(() => {
  window.matchMedia = desktopMatchMedia
})

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
  async refresh(): Promise<void> {}
  subscribe(): () => void {
    return () => {}
  }
  async signIn(): Promise<void> {}
  async signOut(): Promise<void> {}
}

const helpGateway: HelpGateway = {
  async listCatalog() { return [] },
  async upsertTopic() { throw new Error('unused') },
  async upsertArticle() { throw new Error('unused') },
  async getAnnouncement() { return { titleAr: '', bodyAr: '', linkUrl: null, published: false } },
  async setAnnouncement() { throw new Error('unused') },
}

function subscriberGateway(get = vi.fn(async (id: string) => ({
  shopId: id,
  shopName: 'متجر الرابط',
  registeredAt: '2026-10-01T00:00:00.000Z',
  entitlementStartsAt: null,
  entitlementExpiresAt: null,
  subscriptionStatus: 'pending' as const,
  snapshotAt: '2026-10-22T00:30:00.000Z',
}))): SubscriberDirectoryGateway {
  return {
    async list() {
      return {
        snapshotAt: '2026-10-22T00:30:00.000Z',
        counts: { all: '0', active: '0', pending: '0', expired: '0' },
        filteredCount: '0',
        pageSize: 20,
        rows: [],
        nextCursor: null,
      }
    },
    get,
    async issueSubscriptionCode() { throw new Error('unused') },
    async revokeSubscriptionCode() { throw new Error('unused') },
    async listSubscriptionCodes() {
      return {
        snapshotAt: '2026-10-22T00:30:00.000Z',
        shopId,
        shopName: 'متجر الرابط',
        rowCount: '0',
        pageSize: 20,
        rows: [],
        nextCursor: null,
      }
    },
    async bindSelectedShopSession() { return { id: 'lease-1' } },
    async assertBoundSession() {},
    async authorizeCopy() {},
    watchBoundSession() { return () => {} },
    releaseBoundSession() {},
  }
}

function renderAdmin(directory: SubscriberDirectoryGateway | null = null) {
  render(
    <App
      supabaseStatus="ready"
      authGateway={new StableAuth()}
      subscriberGateway={directory}
      contactGateway={null}
      appVersionGateway={null}
      helpGateway={helpGateway}
      supportGateway={null}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
}

function useNarrowViewport() {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: String(query).includes('max-width'),
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }))
}

test('a deep link opens its area and marks it current in the rail', async () => {
  window.history.replaceState(null, '', '/help')
  renderAdmin()
  expect(await screen.findByRole('heading', { name: helpCopy.title })).toBeInTheDocument()
  const nav = screen.getByRole('navigation', { name: shellCopy.navigationLabel })
  expect(within(nav).getByRole('link', { name: helpCopy.navLabel })).toHaveAttribute('aria-current', 'page')
  expect(within(nav).getByRole('link', { name: 'المشتركون' })).not.toHaveAttribute('aria-current')
  expect(within(nav).getByRole('link', { name: 'الدعم الفني' })).toHaveAttribute('href', '/support')
})

test('choosing a section updates the URL and back returns to the previous section', async () => {
  const user = userEvent.setup()
  window.history.replaceState(null, '', '/subscribers')
  renderAdmin()
  expect(window.location.pathname).toBe('/subscribers')
  vi.mocked(window.scrollTo).mockClear()
  await user.click(screen.getByRole('link', { name: helpCopy.navLabel }))
  expect(window.location.pathname).toBe('/help')
  expect(await screen.findByRole('heading', { name: helpCopy.title })).toBeInTheDocument()
  expect(window.scrollTo).toHaveBeenCalledWith({ top: 0 })

  act(() => {
    window.history.replaceState(null, '', '/subscribers')
    window.dispatchEvent(new PopStateEvent('popstate'))
  })
  await waitFor(() => {
    expect(screen.queryByRole('heading', { name: helpCopy.title })).not.toBeInTheDocument()
  })
  expect(screen.getByRole('link', { name: 'المشتركون' })).toHaveAttribute('aria-current', 'page')
})

test('an unknown path is replaced with the overview home', () => {
  window.history.replaceState(null, '', '/no-such-page')
  renderAdmin()
  expect(window.location.pathname).toBe('/')
  expect(screen.getByRole('link', { name: 'نظرة عامة' })).toHaveAttribute('aria-current', 'page')
})

test('a subscriber link opens that shop and closing returns to the list URL', async () => {
  const user = userEvent.setup()
  const get = vi.fn(async (id: string) => ({
    shopId: id,
    shopName: 'متجر الرابط',
    registeredAt: '2026-10-01T00:00:00.000Z',
    entitlementStartsAt: null,
    entitlementExpiresAt: null,
    subscriptionStatus: 'pending' as const,
    snapshotAt: '2026-10-22T00:30:00.000Z',
  }))
  window.history.replaceState(null, '', `/subscribers/${shopId}`)
  renderAdmin(subscriberGateway(get))
  const dialog = await screen.findByRole('dialog', { name: subscriberCopy.detailTitle })
  expect(await within(dialog).findByRole('heading', { name: 'متجر الرابط' })).toBeInTheDocument()
  expect(get).toHaveBeenCalledWith(shopId)
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.close }))
  expect(window.location.pathname).toBe('/subscribers')
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
})

test('a link to a missing shop shows the not-found message', async () => {
  const { SubscriberDirectoryError } = await import('../subscribers/SubscriberDirectoryGateway.ts')
  window.history.replaceState(null, '', `/subscribers/${shopId}`)
  renderAdmin(subscriberGateway(vi.fn(async () => {
    throw new SubscriberDirectoryError('not_found')
  })))
  const dialog = await screen.findByRole('dialog', { name: subscriberCopy.detailTitle })
  expect(await within(dialog).findByText(subscriberCopy.notFound)).toBeInTheDocument()
})

test('narrow screens open sections from the menu drawer', async () => {
  useNarrowViewport()
  const user = userEvent.setup()
  renderAdmin()
  expect(screen.queryByRole('navigation', { name: shellCopy.navigationLabel })).not.toBeInTheDocument()
  const menu = screen.getByRole('button', { name: shellCopy.openNavigation })
  expect(menu).toHaveAttribute('aria-expanded', 'false')
  await user.click(menu)
  const nav = await screen.findByRole('navigation', { name: shellCopy.navigationLabel })
  await user.click(within(nav).getByRole('link', { name: helpCopy.navLabel }))
  expect(window.location.pathname).toBe('/help')
  expect(await screen.findByRole('heading', { name: helpCopy.title })).toBeInTheDocument()
  await waitFor(() => {
    expect(screen.queryByRole('navigation', { name: shellCopy.navigationLabel })).not.toBeInTheDocument()
  })
})

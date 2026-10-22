import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'
import { subscriberCopy } from './copy.ts'
import {
  SubscriberDirectoryError,
  type SubscriberDirectoryGateway,
  type SubscriberQuery,
} from './SubscriberDirectoryGateway.ts'
import type { SubscriberDetail, SubscriberPage, SubscriberRow } from './subscriptionFormat.ts'

const originalMatchMedia = window.matchMedia

afterEach(() => {
  window.matchMedia = originalMatchMedia
})

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null

  constructor(value: string | null = 'light') {
    this.value = value
  }

  read(): string | null { return this.value }
  write(value: string): void { this.value = value }
}

class StableAuth implements AdminAuthGateway {
  status: AdminAccess = 'admin'
  refresh = vi.fn(async (): Promise<void> => {})
  subscribe(): () => void { return () => {} }
  async signIn(): Promise<void> {}
  async signOut(): Promise<void> {}
}

function row(name: string, status: SubscriberRow['subscriptionStatus'] = 'active', id = 'a1100000-0000-4000-8000-000000000001'): SubscriberRow {
  return {
    shopId: id,
    shopName: name,
    registeredAt: '2026-10-22T00:30:45.000Z',
    entitlementStartsAt: status === 'pending' && name === 'بدون مدة' ? null : '2026-10-01T00:00:00.000Z',
    entitlementExpiresAt: status === 'pending' && name === 'بدون مدة' ? null : '2027-10-01T00:00:00.000Z',
    subscriptionStatus: status,
  }
}

function page(overrides: Partial<SubscriberPage> = {}): SubscriberPage {
  return {
    snapshotAt: '2026-10-22T00:30:45.000Z',
    counts: { all: '4', active: '2', pending: '1', expired: '1' },
    filteredCount: '4',
    pageSize: 20,
    rows: [row('متجر الأول'), row('متجر الثاني', 'pending', 'a1100000-0000-4000-8000-000000000002')],
    nextCursor: 'cursor-1',
    ...overrides,
  }
}

function renderDirectory(gateway: SubscriberDirectoryGateway, mode = 'light') {
  const authGateway = new StableAuth()
  render(
    <App
      supabaseStatus="ready"
      authGateway={authGateway}
      subscriberGateway={gateway}
      themeController={new ThemeController(new MemoryThemePreferenceStore(mode))}
    />,
  )
  return { authGateway }
}

test('shows global counts apart from the filtered count and server dates', async () => {
  const seen: SubscriberQuery[] = []
  renderDirectory({
    async list(query) {
      seen.push(query)
      return page({
        filteredCount: '9007199254740993',
        counts: {
          all: '9007199254740993',
          active: '9007199254740993',
          pending: '0',
          expired: '0',
        },
        rows: [row('متجر الأول')],
        nextCursor: null,
      })
    },
    async get(shopId) {
      return { ...row('متجر الأول'), snapshotAt: '2026-10-22T00:30:45.000Z', shopId }
    },
  })

  expect(await screen.findByRole('heading', { name: subscriberCopy.heading })).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.statusIndependence)).toBeInTheDocument()
  const global = screen.getByRole('group', { name: subscriberCopy.globalGroup })
  expect(within(global).getByText(subscriberCopy.countAll)).toBeInTheDocument()
  expect(within(global).getAllByText('9,007,199,254,740,993').length).toBeGreaterThan(0)
  const filtered = screen.getByRole('group', { name: subscriberCopy.filteredGroup })
  expect(within(filtered).getByText('9,007,199,254,740,993')).toBeInTheDocument()
  expect(screen.getAllByText(/2026/).length).toBeGreaterThan(0)
  expect(screen.getByText(subscriberCopy.intro)).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.snapshotLabel, { exact: false })).toBeInTheDocument()
  expect(screen.getByRole('columnheader', { name: subscriberCopy.columnStart })).toBeInTheDocument()
  expect(screen.getByRole('heading', { level: 3, name: 'متجر الأول' })).toBeInTheDocument()
  expect(screen.queryByRole('heading', { name: subscriberCopy.columnStart })).not.toBeInTheDocument()
  expect(screen.queryByText('التوقيت العالمي')).not.toBeInTheDocument()
  expect(screen.queryByText('لقطة الخادم')).not.toBeInTheDocument()
  expect(screen.queryByText(/لا يعرض هذا الدليل/)).not.toBeInTheDocument()
  expect(seen[0]).toEqual({ status: 'all', search: '', cursor: null })
  expect(screen.queryByText(/إصدار/)).not.toBeInTheDocument()
  expect(screen.queryByText(/مساعدة/)).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: /تجديد/ })).not.toBeInTheDocument()
})

test('changing filters resets the cursor and drops the previous page', async () => {
  const user = userEvent.setup()
  const seen: SubscriberQuery[] = []
  renderDirectory({
    async list(query) {
      seen.push(query)
      if (query.cursor) return page({ rows: [row('صفحة لاحقة', 'expired', 'a1100000-0000-4000-8000-000000000009')], nextCursor: null, filteredCount: '4' })
      if (query.search === 'ذهب%_') return page({ rows: [row('ذهب%_خاص')], nextCursor: null, filteredCount: '1' })
      if (query.status === 'expired') return page({ rows: [row('متجر منتهٍ', 'expired', 'a1100000-0000-4000-8000-000000000004')], nextCursor: null, filteredCount: '1' })
      return page()
    },
    async get() { throw new Error('unused') },
  })
  await screen.findByText('متجر الأول')
  await user.click(screen.getByRole('button', { name: subscriberCopy.nextPage }))
  await screen.findByText('صفحة لاحقة')
  await user.click(screen.getByRole('button', { name: subscriberCopy.statusExpired }))
  expect(screen.queryByText('صفحة لاحقة')).not.toBeInTheDocument()
  expect(screen.queryByText('متجر الأول')).not.toBeInTheDocument()
  expect(await screen.findByText('متجر منتهٍ')).toBeInTheDocument()
  expect(seen.at(-1)).toMatchObject({ status: 'expired', search: '', cursor: null })

  await user.type(screen.getByRole('textbox', { name: subscriberCopy.searchLabel }), 'ذهب%_')
  await user.click(screen.getByRole('button', { name: subscriberCopy.searchAction }))
  expect(await screen.findByText('ذهب%_خاص')).toBeInTheDocument()
  expect(seen.at(-1)).toMatchObject({ status: 'expired', search: 'ذهب%_', cursor: null })

  await user.click(screen.getByRole('button', { name: subscriberCopy.refresh }))
  await waitFor(() => expect(seen.at(-1)).toMatchObject({ status: 'expired', search: 'ذهب%_', cursor: null }))
})

test('a late response cannot replace the current filter or survive access loss', async () => {
  const user = userEvent.setup()
  const resolvers: Array<(value: SubscriberPage) => void> = []
  const rejecters: Array<(error: Error) => void> = []
  const { authGateway } = renderDirectory({
    list: () => new Promise<SubscriberPage>((resolve, reject) => {
      resolvers.push(resolve)
      rejecters.push(reject)
    }),
    async get() { throw new Error('unused') },
  })

  await waitFor(() => expect(resolvers).toHaveLength(1))
  await user.click(screen.getByRole('button', { name: subscriberCopy.statusPending }))
  await waitFor(() => expect(resolvers).toHaveLength(2))
  resolvers[1]?.(page({
    rows: [row('متجر منتظر', 'pending', 'a1100000-0000-4000-8000-000000000003')],
    filteredCount: '1',
  }))
  expect(await screen.findByText('متجر منتظر')).toBeInTheDocument()
  resolvers[0]?.(page({ rows: [row('متجر قديم')] }))
  await waitFor(() => expect(screen.queryByText('متجر قديم')).not.toBeInTheDocument())

  await user.click(screen.getByRole('button', { name: subscriberCopy.statusActive }))
  await waitFor(() => expect(resolvers).toHaveLength(3))
  const refreshCalls = authGateway.refresh.mock.calls.length
  rejecters[2]?.(new SubscriberDirectoryError('access_lost'))
  expect(await screen.findByText(subscriberCopy.accessLost)).toBeInTheDocument()
  expect(screen.queryByText('متجر منتظر')).not.toBeInTheDocument()
  expect(screen.queryByRole('table')).not.toBeInTheDocument()
  expect(authGateway.refresh.mock.calls.length).toBeGreaterThan(refreshCalls)
})

test('detail dialog supports escape and ignores a late open after close', async () => {
  const user = userEvent.setup()
  let resolveDetail: ((value: SubscriberDetail) => void) | undefined
  renderDirectory({
    async list() {
      return page({
        rows: [row('بدون مدة', 'pending', 'a1100000-0000-4000-8000-000000000008')],
        nextCursor: null,
      })
    },
    get: () => new Promise<SubscriberDetail>((resolve) => { resolveDetail = resolve }),
  })
  const opener = await screen.findByRole('button', { name: 'تفاصيل اشتراك بدون مدة' })
  await user.click(opener)
  expect(await screen.findByRole('dialog', { name: subscriberCopy.detailTitle })).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.loadingDetail)).toBeInTheDocument()
  await user.keyboard('{Escape}')
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  resolveDetail?.({
    ...row('بدون مدة', 'pending', 'a1100000-0000-4000-8000-000000000008'),
    snapshotAt: '2026-10-22T00:30:45.000Z',
  })
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())

  await user.click(screen.getByRole('button', { name: 'تفاصيل اشتراك بدون مدة' }))
  resolveDetail?.({
    ...row('بدون مدة', 'pending', 'a1100000-0000-4000-8000-000000000008'),
    entitlementStartsAt: null,
    entitlementExpiresAt: null,
    snapshotAt: '2026-10-22T00:30:45.000Z',
  })
  const dialog = await screen.findByRole('dialog', { name: subscriberCopy.detailTitle })
  expect(within(dialog).getByRole('heading', { level: 3, name: 'بدون مدة' })).toBeInTheDocument()
  const startLabel = within(dialog).getByText(subscriberCopy.columnStart)
  expect(startLabel.tagName).toBe('DT')
  expect(startLabel.closest('dl')).not.toBeNull()
  expect(startLabel.nextElementSibling?.tagName).toBe('DD')
  expect(within(dialog).queryByRole('heading', { name: subscriberCopy.columnStart })).not.toBeInTheDocument()
  expect(within(dialog).getByText(subscriberCopy.snapshotLabel)).toBeInTheDocument()
  expect(within(dialog).getAllByText(subscriberCopy.snapshotLabel)).toHaveLength(1)
  expect(within(dialog).getAllByText(subscriberCopy.missingTerm).length).toBeGreaterThan(0)
  expect(within(dialog).getAllByText(/2026/).length).toBeGreaterThan(0)
  const content = within(dialog).getByRole('region', { name: subscriberCopy.detailContent })
  content.focus()
  expect(content).toHaveFocus()
  await user.keyboard('{Tab}')
  expect(within(dialog).getByRole('button', { name: subscriberCopy.close })).toHaveFocus()
  await user.keyboard('{Shift>}{Tab}{/Shift}')
  expect(content).toHaveFocus()
  await user.keyboard('{Escape}')
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  expect(opener).toHaveFocus()
})

test('resume keeps the applied search and a failure can be retried', async () => {
  const user = userEvent.setup()
  const seen: SubscriberQuery[] = []
  let fail = true
  renderDirectory({
    async list(query) {
      seen.push(query)
      if (fail) throw new SubscriberDirectoryError('unavailable')
      return page({ rows: [row('بعد المحاولة')], nextCursor: null, filteredCount: '1' })
    },
    async get() { throw new Error('unused') },
  })
  expect(await screen.findByText(subscriberCopy.loadError)).toBeInTheDocument()
  await user.type(screen.getByRole('textbox', { name: subscriberCopy.searchLabel }), 'ذهب')
  fail = false
  await user.click(screen.getByRole('button', { name: subscriberCopy.retry }))
  expect(await screen.findByText('بعد المحاولة')).toBeInTheDocument()
  expect(seen.at(-1)?.search).toBe('')

  await user.click(screen.getByRole('button', { name: subscriberCopy.searchAction }))
  await waitFor(() => expect(seen.at(-1)).toMatchObject({ search: 'ذهب', cursor: null }))
  const calls = seen.length
  Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' })
  document.dispatchEvent(new Event('visibilitychange'))
  await waitFor(() => expect(seen.length).toBeGreaterThan(calls))
  expect(seen.at(-1)).toMatchObject({ search: 'ذهب', status: 'all' })
})

test('narrow layout uses cards instead of the desktop table', async () => {
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
  renderDirectory({
    async list() { return page({ nextCursor: null }) },
    async get() { throw new Error('unused') },
  }, 'dark')
  expect(await screen.findAllByRole('article')).toHaveLength(2)
  expect(screen.getByRole('heading', { level: 3, name: 'متجر الأول' })).toBeInTheDocument()
  const startLabels = screen.getAllByText(subscriberCopy.columnStart)
  expect(startLabels.length).toBeGreaterThan(0)
  for (const label of startLabels) {
    expect(label.tagName).toBe('DT')
    expect(label.closest('dl')).not.toBeNull()
    expect(label.nextElementSibling?.tagName).toBe('DD')
  }
  expect(screen.queryByRole('heading', { name: subscriberCopy.columnStart })).not.toBeInTheDocument()
  expect(screen.queryByRole('table', { name: subscriberCopy.tableLabel })).not.toBeInTheDocument()
  expect(document.documentElement.style.colorScheme).toBe('dark')
  expect(screen.getByRole('button', { name: 'تفاصيل اشتراك متجر الأول' })).toBeInTheDocument()
})

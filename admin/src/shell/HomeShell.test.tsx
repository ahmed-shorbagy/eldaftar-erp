import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import type { SupabaseStartupStatus } from '../config/supabaseStartup.ts'
import { ThemeController } from '../theme/themeController.ts'
import {
  themeStorageKey,
  type ThemePreferenceStore,
} from '../theme/themePreference.ts'
import { shellCopy } from './copy.ts'

class FakeAdminAuthGateway implements AdminAuthGateway {
  status: AdminAccess

  constructor(status: AdminAccess = 'admin') {
    this.status = status
  }

  subscribe(_listener: (access: AdminAccess) => void): () => void {
    return () => {}
  }

  async refresh(): Promise<void> {}
  async signIn(): Promise<void> {}
  async signOut(): Promise<void> {}
}
class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null

  constructor(value: string | null = null) {
    this.value = value
  }

  read(): string | null {
    return this.value
  }

  write(value: string): void {
    this.value = value
  }
}

test('sign-out blocks duplicate requests and exposes a failed request for retry', async () => {
  const user = userEvent.setup()
  const gateway = new FakeAdminAuthGateway()
  let notify: (access: AdminAccess) => void = () => {}
  let rejectSignOut: (reason: Error) => void = () => {}
  let completeSignOut: () => void = () => {}
  let attempts = 0
  gateway.subscribe = (listener) => {
    notify = listener
    return () => { notify = () => {} }
  }
  gateway.signOut = () => {
    attempts += 1
    return new Promise<void>((resolve, reject) => {
      rejectSignOut = reject
      completeSignOut = () => {
        gateway.status = 'signedOut'
        notify('signedOut')
        resolve()
      }
    })
  }
  render(
    <App
      supabaseStatus="ready"
      authGateway={gateway}
      subscriberGateway={null}
      appVersionGateway={null}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  await user.dblClick(screen.getByRole('button', { name: 'تسجيل الخروج' }))
  expect(attempts).toBe(1)
  expect(screen.getByText(shellCopy.signingOut)).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: 'تسجيل الخروج' })).not.toBeInTheDocument()
  rejectSignOut(new Error('offline'))
  const failure = await screen.findByRole('alert')
  expect(within(failure).getByText(shellCopy.signOutFailure)).toBeInTheDocument()
  await user.click(within(failure).getByRole('button', { name: shellCopy.retrySignOut }))
  expect(attempts).toBe(2)
  expect(screen.getByText(shellCopy.signingOut)).toBeInTheDocument()
  completeSignOut()
  await waitFor(() => expect(screen.queryByText(shellCopy.signingOut)).not.toBeInTheDocument())
  expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: 'تسجيل الخروج' })).not.toBeInTheDocument()
})

function renderShell(
  status: SupabaseStartupStatus,
  store = new MemoryThemePreferenceStore(),
) {
  const themeController = new ThemeController(store)
  render(<App supabaseStatus={status} themeController={themeController} authGateway={new FakeAdminAuthGateway()} />)
  return store
}

test('missing public config shows the Arabic setup message in RTL', () => {
  renderShell('missingConfiguration')

  expect(screen.getByRole('heading', { name: shellCopy.appTitle })).toBeInTheDocument()
  expect(screen.getByTestId('brand-mark')).toBeInTheDocument()
  expect(screen.getByText(shellCopy.prototypeLabel)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.missingTitle)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.missingBody)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.missingHint)).toBeInTheDocument()
  expect(screen.getByText(/VITE_SUPABASE_URL/)).toBeInTheDocument()
  expect(screen.getByText(/VITE_SUPABASE_PUBLISHABLE_KEY/)).toBeInTheDocument()
  expect(screen.queryByText(shellCopy.readyTitle)).not.toBeInTheDocument()
  expect(screen.queryByText(/get started/i)).not.toBeInTheDocument()
  expect(screen.queryByText(/count is/i)).not.toBeInTheDocument()
  expect(screen.getAllByRole('button')).toHaveLength(1)
  expect(document.documentElement.lang).toBe('ar')
  expect(document.documentElement.dir).toBe('rtl')
  expect(screen.getByRole('main').closest('[dir="rtl"]')).not.toBeNull()
  expect(screen.getByText(/VITE_SUPABASE_URL/).closest('[dir="ltr"]')).not.toBeNull()
})

test('a signed-in admin sees the subscriber directory instead of the prototype shell', async () => {
  render(
    <App
      supabaseStatus="ready"
      authGateway={new FakeAdminAuthGateway()}
      subscriberGateway={{
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
        async get() {
          throw new Error('unused')
        },
        async issueSubscriptionCode() {
          throw new Error('unused')
        },
        async listSubscriptionCodes() {
          return {
            snapshotAt: '2026-10-22T00:30:00.000Z',
            shopId: 'a1100000-0000-4000-8000-000000000001',
            shopName: 'متجر',
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
      }}
      appVersionGateway={null}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  expect(await screen.findByRole('heading', { name: 'المشتركون' })).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'تحديث التطبيق' })).toBeInTheDocument()
  expect(screen.queryByText(shellCopy.prototypeLabel)).not.toBeInTheDocument()
  expect(screen.queryByText(shellCopy.readyBody)).not.toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'تسجيل الخروج' })).toBeInTheDocument()
})

test('failed startup stays labeled as a prototype', () => {
  renderShell('failed')
  expect(screen.getByText(shellCopy.prototypeLabel)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.failedTitle)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.failedBody)).toBeInTheDocument()
  expect(screen.queryByText(shellCopy.missingTitle)).not.toBeInTheDocument()
  expect(screen.queryByRole('heading', { name: 'المشتركون' })).not.toBeInTheDocument()
  expect(screen.queryByText(/public-key/)).not.toBeInTheDocument()
})

test('signed-out visitors see the Arabic admin sign-in form', () => {
  render(
    <App
      supabaseStatus="ready"
      authGateway={new FakeAdminAuthGateway('signedOut')}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  expect(screen.getByRole('heading', { name: 'إدارة الدفتر' })).toBeInTheDocument()
  expect(screen.getByTestId('brand-mark')).toBeInTheDocument()
  expect(screen.getByRole('textbox', { name: /البريد الإلكتروني/ })).toBeInTheDocument()
  expect(screen.queryByText(shellCopy.prototypeLabel)).not.toBeInTheDocument()
})
test('theme toggle switches light and dark and persists the choice', async () => {
  const user = userEvent.setup()
  const store = renderShell('missingConfiguration', new MemoryThemePreferenceStore('light'))

  expect(document.documentElement.style.colorScheme).toBe('light')
  await user.click(screen.getByRole('button', { name: shellCopy.toggleToDark }))

  expect(store.value).toBe('dark')
  expect(window.localStorage.getItem(themeStorageKey)).toBeNull()
  expect(screen.getByRole('button', { name: shellCopy.toggleToLight })).toBeInTheDocument()
  expect(document.documentElement.style.colorScheme).toBe('dark')

  await user.click(screen.getByRole('button', { name: shellCopy.toggleToLight }))

  expect(store.value).toBe('light')
  expect(screen.getByRole('button', { name: shellCopy.toggleToDark })).toBeInTheDocument()
  expect(document.documentElement.style.colorScheme).toBe('light')
})

test('a stored dark choice is restored before the first toggle', () => {
  const store = new MemoryThemePreferenceStore('dark')
  renderShell('missingConfiguration', store)

  expect(screen.getByRole('button', { name: shellCopy.toggleToLight })).toBeInTheDocument()
  expect(document.documentElement.style.colorScheme).toBe('dark')
})

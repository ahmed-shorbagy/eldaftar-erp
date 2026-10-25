import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'
import {
  AppVersionError,
  type AppVersionGateway,
  type AppVersionPolicyRow,
  type AppVersionSetInput,
  type AppVersionSetResult,
} from './AppVersionGateway.ts'
import { appVersionCopy } from './copy.ts'

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null

  constructor(value: string | null = 'light') {
    this.value = value
  }

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

function emptyRows(): AppVersionPolicyRow[] {
  return [
    { platform: 'android', minVersion: null, messageAr: '', updateUrl: null },
    { platform: 'ios', minVersion: null, messageAr: '', updateUrl: null },
    { platform: 'windows', minVersion: null, messageAr: '', updateUrl: null },
  ]
}

function gateway(overrides: Partial<AppVersionGateway> = {}): AppVersionGateway {
  return {
    async list() {
      return emptyRows()
    },
    async set(input: AppVersionSetInput): Promise<AppVersionSetResult> {
      return {
        platform: input.platform,
        minVersion: input.minVersion,
        messageAr: input.messageAr,
        updateUrl: input.updateUrl,
        status: 'saved',
      }
    },
    ...overrides,
  }
}

async function openPanel(versionGateway: AppVersionGateway, expectTitle = true) {
  const authGateway = new StableAuth()
  render(
    <App
      supabaseStatus="ready"
      authGateway={authGateway}
      subscriberGateway={null}
      appVersionGateway={versionGateway}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  await userEvent.click(screen.getByRole('button', { name: appVersionCopy.navLabel }))
  if (expectTitle) {
    expect(await screen.findByRole('heading', { name: appVersionCopy.title })).toBeInTheDocument()
  }
  return { authGateway }
}

test('loads per-platform drafts and saves a valid android policy', async () => {
  const user = userEvent.setup()
  const sets: AppVersionSetInput[] = []
  await openPanel(
    gateway({
      async list() {
        return [
          {
            platform: 'android',
            minVersion: '1.0.0',
            messageAr: 'حدّث الآن',
            updateUrl: 'https://example.com/android',
          },
          { platform: 'ios', minVersion: null, messageAr: '', updateUrl: null },
          { platform: 'windows', minVersion: null, messageAr: '', updateUrl: null },
        ]
      },
      async set(input) {
        sets.push(input)
        return { ...input, status: 'saved' }
      },
    }),
  )
  const android = screen.getByRole('region', { name: appVersionCopy.android })
  expect(within(android).getByText(`${appVersionCopy.currentMin}: 1.0.0`)).toBeInTheDocument()
  const versionField = within(android).getByLabelText(
    `${appVersionCopy.android} ${appVersionCopy.minVersion}`,
  )
  await user.clear(versionField)
  await user.type(versionField, '1.2.0')
  const messageField = within(android).getByLabelText(appVersionCopy.message)
  await user.clear(messageField)
  await user.type(messageField, 'يلزم التحديث')
  await user.click(within(android).getByRole('button', { name: appVersionCopy.save }))
  await waitFor(() => expect(sets).toHaveLength(1))
  expect(sets[0]).toEqual({
    platform: 'android',
    minVersion: '1.2.0',
    messageAr: 'يلزم التحديث',
    updateUrl: 'https://example.com/android',
  })
  expect(await within(android).findByText(appVersionCopy.saved)).toBeInTheDocument()
})

test('rejects invalid version and empty message before calling set', async () => {
  const user = userEvent.setup()
  const set = vi.fn()
  await openPanel(gateway({ set }))
  const android = screen.getByRole('region', { name: appVersionCopy.android })
  await user.type(
    within(android).getByLabelText(`${appVersionCopy.android} ${appVersionCopy.minVersion}`),
    '1.0',
  )
  await user.click(within(android).getByRole('button', { name: appVersionCopy.save }))
  expect(within(android).getByText(appVersionCopy.invalidVersion)).toBeInTheDocument()
  expect(set).not.toHaveBeenCalled()

  await user.clear(
    within(android).getByLabelText(`${appVersionCopy.android} ${appVersionCopy.minVersion}`),
  )
  await user.type(
    within(android).getByLabelText(`${appVersionCopy.android} ${appVersionCopy.minVersion}`),
    '1.0.0',
  )
  await user.click(within(android).getByRole('button', { name: appVersionCopy.save }))
  expect(within(android).getByText(appVersionCopy.invalidMessage)).toBeInTheDocument()
  expect(set).not.toHaveBeenCalled()
})

test('clear sends null minimum and reports success', async () => {
  const user = userEvent.setup()
  const sets: AppVersionSetInput[] = []
  await openPanel(
    gateway({
      async set(input) {
        sets.push(input)
        return { ...input, status: 'saved' }
      },
    }),
  )
  const ios = screen.getByRole('region', { name: appVersionCopy.ios })
  await user.click(within(ios).getByRole('button', { name: appVersionCopy.clear }))
  await waitFor(() => expect(sets).toHaveLength(1))
  expect(sets[0]).toEqual({
    platform: 'ios',
    minVersion: null,
    messageAr: '',
    updateUrl: null,
  })
  expect(await within(ios).findByText(appVersionCopy.cleared)).toBeInTheDocument()
})

test('session loss during save refreshes auth access', async () => {
  const user = userEvent.setup()
  const { authGateway } = await openPanel(
    gateway({
      async set() {
        throw new AppVersionError('unauthorized')
      },
    }),
  )
  const windows = screen.getByRole('region', { name: appVersionCopy.windows })
  await user.type(
    within(windows).getByLabelText(`${appVersionCopy.windows} ${appVersionCopy.minVersion}`),
    '2.0.0',
  )
  await user.type(within(windows).getByLabelText(appVersionCopy.message), 'حدّث')
  await user.click(within(windows).getByRole('button', { name: appVersionCopy.save }))
  await waitFor(() => expect(authGateway.refresh).toHaveBeenCalled())
})

test('load failure shows Arabic retry without inventing policy', async () => {
  const user = userEvent.setup()
  let fail = true
  await openPanel(
    gateway({
      async list() {
        if (fail) throw new AppVersionError('unavailable')
        return emptyRows()
      },
    }),
    false,
  )
  expect(await screen.findByText(appVersionCopy.loadError)).toBeInTheDocument()
  fail = false
  await user.click(screen.getByRole('button', { name: appVersionCopy.retry }))
  expect(await screen.findByRole('heading', { name: appVersionCopy.title })).toBeInTheDocument()
  expect(screen.getAllByText(appVersionCopy.noMinimum).length).toBeGreaterThan(0)
})

test('disables save while a request is in flight', async () => {
  const user = userEvent.setup()
  let resolveSet!: (value: AppVersionSetResult) => void
  await openPanel(
    gateway({
      set() {
        return new Promise((resolve) => {
          resolveSet = resolve
        })
      },
    }),
  )
  const android = screen.getByRole('region', { name: appVersionCopy.android })
  await user.type(
    within(android).getByLabelText(`${appVersionCopy.android} ${appVersionCopy.minVersion}`),
    '1.1.0',
  )
  await user.type(within(android).getByLabelText(appVersionCopy.message), 'رسالة')
  await user.click(within(android).getByRole('button', { name: appVersionCopy.save }))
  expect(within(android).getByRole('button', { name: appVersionCopy.saving })).toBeDisabled()
  resolveSet({
    platform: 'android',
    minVersion: '1.1.0',
    messageAr: 'رسالة',
    updateUrl: null,
    status: 'saved',
  })
  expect(await within(android).findByText(appVersionCopy.saved)).toBeInTheDocument()
})

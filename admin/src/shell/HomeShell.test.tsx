import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { App } from '../App.tsx'
import type { SupabaseStartupStatus } from '../config/supabaseStartup.ts'
import { ThemeController } from '../theme/themeController.ts'
import {
  themeStorageKey,
  type ThemePreferenceStore,
} from '../theme/themePreference.ts'
import { shellCopy } from './copy.ts'

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

function renderShell(
  status: SupabaseStartupStatus,
  store = new MemoryThemePreferenceStore(),
) {
  const themeController = new ThemeController(store)
  render(<App supabaseStatus={status} themeController={themeController} />)
  return store
}

test('missing public config shows the Arabic setup message in RTL', () => {
  renderShell('missingConfiguration')

  expect(screen.getByRole('heading', { name: shellCopy.appTitle })).toBeInTheDocument()
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

test('ready and failed states stay labeled as a prototype', () => {
  const { unmount } = render(
    <App
      supabaseStatus="ready"
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  expect(screen.getByText(shellCopy.prototypeLabel)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.readyTitle)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.readyBody)).toBeInTheDocument()
  expect(screen.queryByText(/VITE_SUPABASE_URL/)).not.toBeInTheDocument()
  unmount()

  renderShell('failed')
  expect(screen.getByText(shellCopy.prototypeLabel)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.failedTitle)).toBeInTheDocument()
  expect(screen.getByText(shellCopy.failedBody)).toBeInTheDocument()
  expect(screen.queryByText(shellCopy.missingTitle)).not.toBeInTheDocument()
  expect(screen.queryByText(/public-key/)).not.toBeInTheDocument()
})

test('theme toggle switches light and dark and persists the choice', async () => {
  const user = userEvent.setup()
  const store = renderShell('missingConfiguration')

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

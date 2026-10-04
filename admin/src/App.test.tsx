import { fireEvent, render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { App } from './App.tsx'
import { ThemeController } from './theme/themeController.ts'
import type { ThemePreferenceStore } from './theme/themePreference.ts'

test('signed-out owner can change theme and retain it when the app restarts', () => {
  let stored = 'light'
  const store: ThemePreferenceStore = {
    read: () => stored,
    write: (value) => { stored = value },
  }
  const first = render(<App supabaseStatus="ready" themeController={new ThemeController(store)} />)
  fireEvent.click(screen.getByRole('button', { name: 'التحويل إلى المظهر الداكن' }))
  expect(stored).toBe('dark')
  expect(document.documentElement).toHaveStyle({ colorScheme: 'dark' })
  expect(screen.getByLabelText(/البريد الإلكتروني/)).toHaveAttribute('autocomplete', 'username')
  expect(screen.getByLabelText(/كلمة المرور/)).toHaveAttribute('autocomplete', 'current-password')
  first.unmount()

  render(<App supabaseStatus="ready" themeController={new ThemeController(store)} />)
  expect(screen.getByRole('button', { name: 'التحويل إلى المظهر الفاتح' })).toBeInTheDocument()
  expect(screen.getByRole('heading', { name: 'إدارة الدفتر' })).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: 'التحويل إلى المظهر الفاتح' }))
  expect(stored).toBe('light')
})

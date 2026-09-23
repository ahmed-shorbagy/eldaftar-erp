import { beforeEach, expect, test } from 'vitest'
import { ThemeController } from './themeController.ts'
import {
  LocalStorageThemeStore,
  themeStorageKey,
  type ThemePreferenceStore,
} from './themePreference.ts'

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

beforeEach(() => {
  window.localStorage.clear()
})

test('unknown or empty preference follows the system', () => {
  const store = new MemoryThemePreferenceStore('nope')
  const controller = new ThemeController(store)

  controller.load()

  expect(controller.mode).toBe('system')
})

test('loads a persisted light or dark choice', () => {
  const store = new MemoryThemePreferenceStore('dark')
  const controller = new ThemeController(store)

  controller.load()
  expect(controller.mode).toBe('dark')

  store.value = 'light'
  controller.load()
  expect(controller.mode).toBe('light')
})

test('toggle persists the opposite of the resolved brightness', () => {
  const store = new MemoryThemePreferenceStore()
  const controller = new ThemeController(store)

  controller.toggle('light')
  expect(controller.mode).toBe('dark')
  expect(store.value).toBe('dark')

  controller.toggle('dark')
  expect(controller.mode).toBe('light')
  expect(store.value).toBe('light')
})

test('keeps the toggled choice when storage throws', () => {
  const store: ThemePreferenceStore = {
    read: () => null,
    write: () => {
      throw new Error('storage blocked')
    },
  }
  const controller = new ThemeController(store)

  controller.toggle('light')

  expect(controller.mode).toBe('dark')
})

test('persists the choice in local storage under theme_mode', () => {
  const controller = new ThemeController(new LocalStorageThemeStore())
  controller.load()
  expect(controller.mode).toBe('system')

  controller.toggle('light')
  expect(window.localStorage.getItem(themeStorageKey)).toBe('dark')

  const reloaded = new ThemeController(new LocalStorageThemeStore())
  reloaded.load()
  expect(reloaded.mode).toBe('dark')
})

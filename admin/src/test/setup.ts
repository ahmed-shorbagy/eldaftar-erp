import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'

afterEach(() => {
  cleanup()
  window.localStorage.clear()
  // Admin routes live in the URL; start every test at the root path.
  window.history.replaceState(null, '', '/')
})

// jsdom does not implement scrolling; section changes call window.scrollTo.
Object.defineProperty(window, 'scrollTo', { writable: true, configurable: true, value: vi.fn() })

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  configurable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})

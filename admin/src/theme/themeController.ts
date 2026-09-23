import {
  decodeThemeChoice,
  type ResolvedTheme,
  type ThemeChoice,
  type ThemePreferenceStore,
} from './themePreference.ts'

export class ThemeController {
  mode: ThemeChoice
  readonly #store: ThemePreferenceStore

  constructor(store: ThemePreferenceStore) {
    this.#store = store
    this.mode = decodeThemeChoice(store.read())
  }

  load(): void {
    this.mode = decodeThemeChoice(this.#store.read())
  }

  toggle(resolved: ResolvedTheme): void {
    this.mode = resolved === 'dark' ? 'light' : 'dark'
    try {
      this.#store.write(this.mode)
    } catch {
      // Keep the session choice when browser storage is unavailable.
    }
  }
}

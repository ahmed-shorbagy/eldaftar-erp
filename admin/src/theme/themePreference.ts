export const themeStorageKey = 'theme_mode'

export type ThemeChoice = 'light' | 'dark' | 'system'
export type ResolvedTheme = 'light' | 'dark'

export interface ThemePreferenceStore {
  read: () => string | null
  write: (value: string) => void
}

export function decodeThemeChoice(stored: string | null): ThemeChoice {
  if (stored === 'light' || stored === 'dark') {
    return stored
  }
  return 'system'
}

export function resolveThemeChoice(
  choice: ThemeChoice,
  systemIsDark: boolean,
): ResolvedTheme {
  if (choice === 'light' || choice === 'dark') {
    return choice
  }
  return systemIsDark ? 'dark' : 'light'
}

export class LocalStorageThemeStore implements ThemePreferenceStore {
  read(): string | null {
    try {
      return window.localStorage.getItem(themeStorageKey)
    } catch {
      return null
    }
  }

  write(value: string): void {
    window.localStorage.setItem(themeStorageKey, value)
  }
}

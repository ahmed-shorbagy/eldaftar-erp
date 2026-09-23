import { CacheProvider } from '@emotion/react'
import CssBaseline from '@mui/material/CssBaseline'
import { ThemeProvider } from '@mui/material/styles'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { SupabaseStartupStatus } from './config/supabaseStartup.ts'
import { HomeShell } from './shell/HomeShell.tsx'
import { rtlCache } from './theme/rtlCache.ts'
import { createAppTheme } from './theme/theme.ts'
import type { ThemeController } from './theme/themeController.ts'
import { resolveThemeChoice } from './theme/themePreference.ts'
import { useSystemDark } from './theme/useSystemDark.ts'

export function App({
  supabaseStatus,
  themeController,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeController: ThemeController
}) {
  const [choice, setChoice] = useState(themeController.mode)
  const systemDark = useSystemDark()
  const resolved = resolveThemeChoice(choice, systemDark)
  const theme = useMemo(() => createAppTheme(resolved), [resolved])

  useEffect(() => {
    document.documentElement.lang = 'ar'
    document.documentElement.dir = 'rtl'
    document.documentElement.style.colorScheme = resolved
  }, [resolved])

  const toggleTheme = useCallback(() => {
    themeController.toggle(resolved)
    setChoice(themeController.mode)
  }, [resolved, themeController])

  return (
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <HomeShell
          supabaseStatus={supabaseStatus}
          themeMode={resolved}
          onToggleTheme={toggleTheme}
        />
      </ThemeProvider>
    </CacheProvider>
  )
}

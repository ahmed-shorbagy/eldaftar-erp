import { CacheProvider } from '@emotion/react'
import CssBaseline from '@mui/material/CssBaseline'
import { ThemeProvider } from '@mui/material/styles'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { AdminAuthScreen } from './auth/AdminAuthScreen.tsx'
import type { AdminAccess, AdminAuthGateway } from './auth/AdminAuthGateway.ts'
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
  authGateway = null,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeController: ThemeController
  authGateway?: AdminAuthGateway | null
}) {
  const [choice, setChoice] = useState(themeController.mode)
  const [access, setAccess] = useState<AdminAccess>(authGateway?.status ?? 'unavailable')
  const systemDark = useSystemDark()
  const resolved = resolveThemeChoice(choice, systemDark)
  const theme = useMemo(() => createAppTheme(resolved), [resolved])

  useEffect(() => {
    document.documentElement.lang = 'ar'
    document.documentElement.dir = 'rtl'
    document.documentElement.style.colorScheme = resolved
  }, [resolved])

  useEffect(() => {
    if (authGateway === null || supabaseStatus !== 'ready') return
    const unsubscribe = authGateway.subscribe(setAccess)
    void authGateway.refresh()
    return unsubscribe
  }, [authGateway, supabaseStatus])
  const toggleTheme = useCallback(() => {
    themeController.toggle(resolved)
    setChoice(themeController.mode)
  }, [resolved, themeController])

  return (
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        {supabaseStatus === 'ready' && access !== 'admin' ? (
          <AdminAuthScreen status={access} gateway={authGateway} />
        ) : (
          <HomeShell
            supabaseStatus={supabaseStatus}
            themeMode={resolved}
            onToggleTheme={toggleTheme}
            onSignOut={supabaseStatus !== 'ready' || authGateway === null ? undefined : () => void authGateway.signOut()}
          />
        )}
      </ThemeProvider>
    </CacheProvider>
  )
}

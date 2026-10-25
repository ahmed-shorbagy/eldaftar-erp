import { CacheProvider } from '@emotion/react'
import Alert from '@mui/material/Alert'
import Button from '@mui/material/Button'
import ButtonGroup from '@mui/material/ButtonGroup'
import CssBaseline from '@mui/material/CssBaseline'
import { ThemeProvider } from '@mui/material/styles'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AppVersionPolicyPanel } from './appVersion/AppVersionPolicyPanel.tsx'
import type { AppVersionGateway } from './appVersion/AppVersionGateway.ts'
import { appVersionCopy } from './appVersion/copy.ts'
import { SupabaseAppVersionGateway } from './appVersion/SupabaseAppVersionGateway.ts'
import { AdminAuthScreen } from './auth/AdminAuthScreen.tsx'
import type { AdminAccess, AdminAuthGateway } from './auth/AdminAuthGateway.ts'
import { getSupabaseClient } from './config/supabaseClient.ts'
import type { SupabaseStartupStatus } from './config/supabaseStartup.ts'
import { HomeShell } from './shell/HomeShell.tsx'
import { shellCopy } from './shell/copy.ts'
import { SubscriberDirectory } from './subscribers/SubscriberDirectory.tsx'
import type { SubscriberDirectoryGateway } from './subscribers/SubscriberDirectoryGateway.ts'
import { SupabaseSubscriberDirectoryGateway } from './subscribers/SupabaseSubscriberDirectoryGateway.ts'
import { DirectoryUnavailable } from './subscribers/DirectoryUnavailable.tsx'
import { rtlCache } from './theme/rtlCache.ts'
import { createAppTheme } from './theme/theme.ts'
import type { ThemeController } from './theme/themeController.ts'
import { resolveThemeChoice } from './theme/themePreference.ts'
import { useSystemDark } from './theme/useSystemDark.ts'

type AdminDestination = 'subscribers' | 'appVersion'

export function App({
  supabaseStatus,
  themeController,
  authGateway = null,
  subscriberGateway,
  appVersionGateway,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeController: ThemeController
  authGateway?: AdminAuthGateway | null
  subscriberGateway?: SubscriberDirectoryGateway | null
  appVersionGateway?: AppVersionGateway | null
}) {
  const [choice, setChoice] = useState(themeController.mode)
  const [access, setAccess] = useState<AdminAccess>(authGateway?.status ?? 'unavailable')
  const [signingOut, setSigningOut] = useState(false)
  const [signOutError, setSignOutError] = useState(false)
  const [destination, setDestination] = useState<AdminDestination>('subscribers')
  const signOutPending = useRef(false)
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
    const unsubscribe = authGateway.subscribe((next) => {
      setAccess(next)
      if (next === 'admin') setSignOutError(false)
    })
    void authGateway.refresh()
    return unsubscribe
  }, [authGateway, supabaseStatus])
  const directoryGateway = useMemo(() => {
    if (subscriberGateway !== undefined) return subscriberGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseSubscriberDirectoryGateway(client)
  }, [subscriberGateway])
  const versionGateway = useMemo(() => {
    if (appVersionGateway !== undefined) return appVersionGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseAppVersionGateway(client)
  }, [appVersionGateway])
  const reportAccessLoss = useCallback(() => {
    void authGateway?.refresh()
  }, [authGateway])
  const signOut = useCallback(() => {
    if (authGateway === null || signOutPending.current) return
    signOutPending.current = true
    setSigningOut(true)
    setSignOutError(false)
    void authGateway.signOut().catch(() => {
      setSignOutError(true)
    }).finally(() => {
      signOutPending.current = false
      setSigningOut(false)
    })
  }, [authGateway])
  const toggleTheme = useCallback(() => {
    themeController.toggle(resolved)
    setChoice(themeController.mode)
  }, [resolved, themeController])

  return (
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        {signingOut && <Alert severity="info" role="status" sx={{ m: 2 }}>{shellCopy.signingOut}</Alert>}
        {signOutError && (
          <Alert
            severity="error"
            sx={{ m: 2 }}
            action={<Button color="inherit" onClick={signOut}>{shellCopy.retrySignOut}</Button>}
          >
            {shellCopy.signOutFailure}
          </Alert>
        )}
        {supabaseStatus === 'ready' && (signingOut || access !== 'admin') ? (
          <AdminAuthScreen status={signingOut ? 'checking' : access} gateway={authGateway} themeMode={resolved} onToggleTheme={toggleTheme} />
        ) : (
          <HomeShell
            supabaseStatus={supabaseStatus}
            themeMode={resolved}
            onToggleTheme={toggleTheme}
            onSignOut={supabaseStatus !== 'ready' || authGateway === null ? undefined : signOut}
            navigation={
              supabaseStatus === 'ready' && access === 'admin' ? (
                <ButtonGroup variant="outlined" fullWidth sx={{ minHeight: 48 }}>
                  <Button
                    variant={destination === 'subscribers' ? 'contained' : 'outlined'}
                    onClick={() => setDestination('subscribers')}
                    sx={{ minHeight: 48 }}
                  >
                    {appVersionCopy.subscribersNav}
                  </Button>
                  <Button
                    variant={destination === 'appVersion' ? 'contained' : 'outlined'}
                    onClick={() => setDestination('appVersion')}
                    sx={{ minHeight: 48 }}
                  >
                    {appVersionCopy.navLabel}
                  </Button>
                </ButtonGroup>
              ) : undefined
            }
            directory={
              supabaseStatus === 'ready' && access === 'admin'
                ? destination === 'subscribers'
                  ? directoryGateway
                    ? <SubscriberDirectory gateway={directoryGateway} onAccessLost={reportAccessLoss} />
                    : <DirectoryUnavailable />
                  : versionGateway
                    ? <AppVersionPolicyPanel gateway={versionGateway} onAccessLost={reportAccessLoss} />
                    : <DirectoryUnavailable />
                : undefined
            }
          />
        )}
      </ThemeProvider>
    </CacheProvider>
  )
}

import { CacheProvider } from '@emotion/react'
import DashboardOutlinedIcon from '@mui/icons-material/DashboardOutlined'
import HistoryOutlinedIcon from '@mui/icons-material/HistoryOutlined'
import HelpOutlineOutlinedIcon from '@mui/icons-material/HelpOutlineOutlined'
import PeopleAltOutlinedIcon from '@mui/icons-material/PeopleAltOutlined'
import SupportAgentOutlinedIcon from '@mui/icons-material/SupportAgentOutlined'
import SystemUpdateAltOutlinedIcon from '@mui/icons-material/SystemUpdateAltOutlined'
import Alert from '@mui/material/Alert'
import Button from '@mui/material/Button'
import CssBaseline from '@mui/material/CssBaseline'
import { ThemeProvider } from '@mui/material/styles'
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { AppVersionPolicyPanel } from './appVersion/AppVersionPolicyPanel.tsx'
import type { AppVersionGateway } from './appVersion/AppVersionGateway.ts'
import { appVersionCopy } from './appVersion/copy.ts'
import { SupabaseAppVersionGateway } from './appVersion/SupabaseAppVersionGateway.ts'
import { AuditLogPanel } from './audit/AuditLogPanel.tsx'
import type { AuditGateway } from './audit/AuditGateway.ts'
import { auditCopy } from './audit/copy.ts'
import { SupabaseAuditGateway } from './audit/SupabaseAuditGateway.ts'
import { AdminAuthScreen } from './auth/AdminAuthScreen.tsx'
import type { AdminAccess, AdminAuthGateway } from './auth/AdminAuthGateway.ts'
import { getSupabaseClient } from './config/supabaseClient.ts'
import type { SupabaseStartupStatus } from './config/supabaseStartup.ts'
import { HelpContentPanel } from './help/HelpContentPanel.tsx'
import type { HelpGateway } from './help/HelpGateway.ts'
import { helpCopy } from './help/copy.ts'
import { SupabaseHelpGateway } from './help/SupabaseHelpGateway.ts'
import { SupabaseSupportGateway } from './support/SupabaseSupportGateway.ts'
import { SupportMailboxPanel } from './support/SupportMailboxPanel.tsx'
import type { SupportGateway } from './support/SupportGateway.ts'
import { supportCopy } from './support/copy.ts'
import { formatAdminPath, subscribersRoute, type AdminArea, type AdminRoute } from './navigation/adminRoutes.ts'
import { overviewCopy } from './overview/copy.ts'
import type { OverviewGateway } from './overview/OverviewGateway.ts'
import { OverviewPanel } from './overview/OverviewPanel.tsx'
import { SupabaseOverviewGateway } from './overview/SupabaseOverviewGateway.ts'
import { useAdminRoute } from './navigation/useAdminRoute.ts'
import type { AdminNavItem } from './shell/AdminNavigation.tsx'
import { HomeShell } from './shell/HomeShell.tsx'
import { shellCopy } from './shell/copy.ts'
import { SubscriberDirectory } from './subscribers/SubscriberDirectory.tsx'
import type { SubscriberContactGateway } from './subscribers/SubscriberContactGateway.ts'
import type { SubscriberDirectoryGateway } from './subscribers/SubscriberDirectoryGateway.ts'
import { SupabaseSubscriberContactGateway } from './subscribers/SupabaseSubscriberContactGateway.ts'
import { SupabaseSubscriberDirectoryGateway } from './subscribers/SupabaseSubscriberDirectoryGateway.ts'
import { DirectoryUnavailable } from './subscribers/DirectoryUnavailable.tsx'
import { rtlCache } from './theme/rtlCache.ts'
import { createAppTheme } from './theme/theme.ts'
import type { ThemeController } from './theme/themeController.ts'
import { resolveThemeChoice } from './theme/themePreference.ts'
import { useSystemDark } from './theme/useSystemDark.ts'

const navAreas: Array<{ area: AdminArea; label: string; icon: ReactNode }> = [
  { area: 'overview', label: overviewCopy.navLabel, icon: <DashboardOutlinedIcon /> },
  { area: 'subscribers', label: helpCopy.subscribersNav, icon: <PeopleAltOutlinedIcon /> },
  { area: 'appVersion', label: appVersionCopy.navLabel, icon: <SystemUpdateAltOutlinedIcon /> },
  { area: 'help', label: helpCopy.navLabel, icon: <HelpOutlineOutlinedIcon /> },
  { area: 'support', label: supportCopy.navLabel, icon: <SupportAgentOutlinedIcon /> },
  { area: 'audit', label: auditCopy.navLabel, icon: <HistoryOutlinedIcon /> },
]

function areaRoute(area: AdminArea): AdminRoute {
  return area === 'subscribers' ? subscribersRoute() : { area }
}

export function App({
  supabaseStatus,
  themeController,
  authGateway = null,
  subscriberGateway,
  contactGateway,
  appVersionGateway,
  helpGateway,
  supportGateway,
  overviewGateway,
  auditGateway,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeController: ThemeController
  authGateway?: AdminAuthGateway | null
  subscriberGateway?: SubscriberDirectoryGateway | null
  contactGateway?: SubscriberContactGateway | null
  appVersionGateway?: AppVersionGateway | null
  helpGateway?: HelpGateway | null
  supportGateway?: SupportGateway | null
  overviewGateway?: OverviewGateway | null
  auditGateway?: AuditGateway | null
}) {
  const [choice, setChoice] = useState(themeController.mode)
  const [access, setAccess] = useState<AdminAccess>(authGateway?.status ?? 'unavailable')
  const [signingOut, setSigningOut] = useState(false)
  const [signOutError, setSignOutError] = useState(false)
  const { route, navigate } = useAdminRoute()
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
  const piiGateway = useMemo(() => {
    if (contactGateway !== undefined) return contactGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseSubscriberContactGateway(client)
  }, [contactGateway])
  const versionGateway = useMemo(() => {
    if (appVersionGateway !== undefined) return appVersionGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseAppVersionGateway(client)
  }, [appVersionGateway])
  const contentGateway = useMemo(() => {
    if (helpGateway !== undefined) return helpGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseHelpGateway(client)
  }, [helpGateway])
  const supportMailboxGateway = useMemo(() => {
    if (supportGateway !== undefined) return supportGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseSupportGateway(client)
  }, [supportGateway])
  const overviewReadGateway = useMemo(() => {
    if (overviewGateway !== undefined) return overviewGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseOverviewGateway(client)
  }, [overviewGateway])
  const auditReadGateway = useMemo(() => {
    if (auditGateway !== undefined) return auditGateway
    const client = getSupabaseClient()
    return client === null ? null : new SupabaseAuditGateway(client)
  }, [auditGateway])
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

  const directory = (() => {
    if (!(supabaseStatus === 'ready' && access === 'admin')) return undefined
    if (route.area === 'overview') {
      return overviewReadGateway
        ? (
          <OverviewPanel
            gateway={overviewReadGateway}
            onAccessLost={reportAccessLoss}
            onOpen={(next) => {
              navigate(next)
              window.scrollTo({ top: 0 })
            }}
          />
        )
        : <DirectoryUnavailable />
    }
    if (route.area === 'subscribers') {
      return directoryGateway
        ? (
          <SubscriberDirectory
            gateway={directoryGateway}
            contactGateway={piiGateway}
            onAccessLost={reportAccessLoss}
            selectedShopId={route.shopId}
            onSelectedShopChange={(shopId) => navigate(subscribersRoute(route.status, shopId))}
            statusFilter={route.status}
            onStatusFilterChange={(status) => navigate(subscribersRoute(status, null), { replace: true })}
          />
        )
        : <DirectoryUnavailable />
    }
    if (route.area === 'appVersion') {
      return versionGateway
        ? <AppVersionPolicyPanel gateway={versionGateway} onAccessLost={reportAccessLoss} />
        : <DirectoryUnavailable />
    }
    if (route.area === 'audit') {
      return auditReadGateway
        ? (
          <AuditLogPanel
            gateway={auditReadGateway}
            onAccessLost={reportAccessLoss}
            onOpen={(next) => {
              navigate(next)
              window.scrollTo({ top: 0 })
            }}
          />
        )
        : <DirectoryUnavailable />
    }
    if (route.area === 'support') {
      return supportMailboxGateway
        ? <SupportMailboxPanel gateway={supportMailboxGateway} onAccessLost={reportAccessLoss} />
        : <DirectoryUnavailable />
    }
    return contentGateway
      ? <HelpContentPanel gateway={contentGateway} onAccessLost={reportAccessLoss} />
      : <DirectoryUnavailable />
  })()

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
              supabaseStatus === 'ready' && access === 'admin'
                ? {
                  items: navAreas.map((item): AdminNavItem => ({
                    key: item.area,
                    label: item.label,
                    icon: item.icon,
                    href: formatAdminPath(areaRoute(item.area)),
                    selected: route.area === item.area,
                  })),
                  onSelect: (key) => {
                    const target = navAreas.find((item) => item.area === key)
                    if (!target) return
                    navigate(areaRoute(target.area))
                    // A new section starts at its top, not at the previous scroll offset.
                    if (target.area !== route.area) window.scrollTo({ top: 0 })
                  },
                }
                : undefined
            }
            directory={directory}
          />
        )}
      </ThemeProvider>
    </CacheProvider>
  )
}

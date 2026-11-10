import DarkModeOutlinedIcon from '@mui/icons-material/DarkModeOutlined'
import LightModeOutlinedIcon from '@mui/icons-material/LightModeOutlined'
import LogoutOutlinedIcon from '@mui/icons-material/LogoutOutlined'
import MenuOutlinedIcon from '@mui/icons-material/MenuOutlined'
import AppBar from '@mui/material/AppBar'
import Box from '@mui/material/Box'
import Drawer from '@mui/material/Drawer'
import IconButton from '@mui/material/IconButton'
import { useTheme } from '@mui/material/styles'
import Toolbar from '@mui/material/Toolbar'
import Typography from '@mui/material/Typography'
import useMediaQuery from '@mui/material/useMediaQuery'
import { useState, type ReactNode } from 'react'
import type { SupabaseStartupStatus } from '../config/supabaseStartup.ts'
import { BrandMark } from '../theme/BrandMark.tsx'
import { tokens } from '../theme/tokens.ts'
import type { ResolvedTheme } from '../theme/themePreference.ts'
import { AdminNavigation, type AdminNavItem } from './AdminNavigation.tsx'
import { shellCopy } from './copy.ts'

const railWidth = 232

export function HomeShell({
  supabaseStatus,
  themeMode,
  onToggleTheme,
  onSignOut,
  directory,
  navigation,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeMode: ResolvedTheme
  onToggleTheme: () => void
  onSignOut?: () => void
  directory?: ReactNode
  navigation?: { items: AdminNavItem[]; onSelect: (key: string) => void }
}) {
  const theme = useTheme()
  // The permanent rail takes 232px, so it appears only from the lg breakpoint
  // (1200px); below that the directory table keeps its full width and the
  // sections open from a menu drawer.
  const narrow = useMediaQuery(theme.breakpoints.down('lg'), { noSsr: true })
  const [drawerOpen, setDrawerOpen] = useState(false)
  const showRail = navigation !== undefined && !narrow
  const showDrawer = navigation !== undefined && narrow
  const isDark = themeMode === 'dark'
  const toggleLabel = isDark ? shellCopy.toggleToLight : shellCopy.toggleToDark
  const bannerBackground = isDark
    ? tokens.darkPrimaryContainer
    : tokens.lightPrimaryContainer
  const bannerForeground = isDark
    ? tokens.darkOnPrimaryContainer
    : tokens.lightOnPrimaryContainer

  return (
    <Box
      lang="ar"
      dir="rtl"
      sx={{
        minHeight: '100vh',
        bgcolor: 'background.default',
        color: 'text.primary',
      }}
    >
      <AppBar
        position="sticky"
        color="transparent"
        elevation={0}
        sx={{ bgcolor: 'background.default', color: 'text.primary' }}
      >
        <Toolbar
          sx={{
            display: 'grid',
            gridTemplateColumns: '1fr auto 1fr',
            alignItems: 'center',
            gap: 1,
          }}
        >
          <Box sx={{ display: 'flex', justifyContent: 'flex-start' }}>
            {showDrawer && (
              <IconButton
                aria-label={shellCopy.openNavigation}
                aria-expanded={drawerOpen}
                aria-controls="admin-navigation-drawer"
                color="inherit"
                onClick={() => setDrawerOpen(true)}
              >
                <MenuOutlinedIcon />
              </IconButton>
            )}
          </Box>
          <Typography
            component="h1"
            variant="h6"
            sx={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 1,
              minWidth: 0,
              fontWeight: 700,
            }}
          >
            <BrandMark />
            {shellCopy.appTitle}
          </Typography>
          <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 1 }}>
            {onSignOut && (
              <IconButton aria-label="تسجيل الخروج" color="inherit" onClick={onSignOut}>
                <LogoutOutlinedIcon />
              </IconButton>
            )}
            <IconButton aria-label={toggleLabel} color="inherit" onClick={onToggleTheme}>
              {isDark ? <LightModeOutlinedIcon /> : <DarkModeOutlinedIcon />}
            </IconButton>
          </Box>
        </Toolbar>
      </AppBar>
      {showDrawer && navigation && (
        <Drawer
          id="admin-navigation-drawer"
          anchor="left"
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          slotProps={{ paper: { sx: { width: railWidth + 32, maxWidth: '85vw', p: 2, bgcolor: 'background.default' } } }}
        >
          <Typography component="p" variant="subtitle1" sx={{ fontWeight: 700, mb: 1, px: 1.5 }}>
            {shellCopy.navigationLabel}
          </Typography>
          <AdminNavigation
            items={navigation.items}
            onSelect={(key) => {
              setDrawerOpen(false)
              navigation.onSelect(key)
            }}
          />
        </Drawer>
      )}
      <Box
        sx={showRail
          ? {
            display: 'grid',
            gridTemplateColumns: `${railWidth}px minmax(0, 1fr)`,
            alignItems: 'start',
          }
          : undefined}
      >
      {showRail && navigation && (
        <Box
          component="aside"
          sx={{
            position: 'sticky',
            top: 64,
            alignSelf: 'start',
            p: 2,
            minHeight: 'calc(100vh - 64px)',
            borderInlineEnd: 1,
            borderColor: 'divider',
          }}
        >
          <AdminNavigation items={navigation.items} onSelect={navigation.onSelect} />
        </Box>
      )}
      <Box
        component="main"
        sx={{
          width: '100%',
          maxWidth: directory ? tokens.adminDirectoryMaxWidth : tokens.contentMaxWidth,
          mx: 'auto',
          px: { xs: `${tokens.spaceMd}px`, md: `${tokens.spaceXl}px` },
          py: { xs: `${tokens.spaceMd}px`, md: `${tokens.spaceXl}px` },
          display: 'grid',
          gap: `${tokens.spaceMd}px`,
          minWidth: 0,
        }}
      >
        {directory ?? (
          <>
            <Box
              sx={{
                p: 2,
                borderRadius: '16px',
                bgcolor: bannerBackground,
                color: bannerForeground,
              }}
            >
              <Typography
                component="p"
                variant="subtitle1"
                sx={{ fontWeight: 700, color: 'inherit', mb: 1, lineHeight: 1.4 }}
              >
                {shellCopy.prototypeLabel}
              </Typography>
              <Typography variant="body1" sx={{ color: 'inherit', lineHeight: 1.6 }}>
                {shellCopy.prototypeBody}
              </Typography>
            </Box>
            <StatusCard status={supabaseStatus} />
          </>
        )}
      </Box>
      </Box>
    </Box>
  )
}

function StatusCard({ status }: { status: SupabaseStartupStatus }) {
  const content = statusContent(status)

  return (
    <Box
      sx={{
        p: '20px',
        borderRadius: '20px',
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
      }}
    >
      <Typography
        component="h2"
        variant="h5"
        data-testid="supabase-status-title"
        sx={{ fontWeight: 700, color: 'text.primary', lineHeight: 1.4, mb: 1.5 }}
      >
        {content.title}
      </Typography>
      <Typography
        data-testid="supabase-status-body"
        sx={{ color: 'text.primary', lineHeight: 1.6 }}
      >
        {content.body}
      </Typography>
      {status === 'missingConfiguration' ? <MissingConfigurationHelp /> : null}
    </Box>
  )
}

function MissingConfigurationHelp() {
  return (
    <>
      <Typography sx={{ color: 'text.primary', lineHeight: 1.6, mt: 1.5 }}>
        {shellCopy.missingHint}
      </Typography>
      <Box
        component="pre"
        dir="ltr"
        sx={{
          mt: 1.5,
          mb: 0,
          p: 1.5,
          overflow: 'auto',
          borderRadius: '12px',
          border: 1,
          borderColor: 'divider',
          bgcolor: 'background.default',
          color: 'text.primary',
          fontFamily: 'ui-monospace, Consolas, monospace',
          whiteSpace: 'pre-wrap',
          textAlign: 'left',
          lineHeight: 1.6,
        }}
      >
        {shellCopy.defineExample}
      </Box>
    </>
  )
}

function statusContent(status: SupabaseStartupStatus): {
  title: string
  body: string
} {
  switch (status) {
    case 'missingConfiguration':
      return { title: shellCopy.missingTitle, body: shellCopy.missingBody }
    case 'ready':
      return { title: shellCopy.readyTitle, body: shellCopy.readyBody }
    case 'failed':
      return { title: shellCopy.failedTitle, body: shellCopy.failedBody }
  }
}

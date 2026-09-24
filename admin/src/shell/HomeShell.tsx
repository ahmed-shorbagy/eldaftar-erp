import DarkModeOutlinedIcon from '@mui/icons-material/DarkModeOutlined'
import LightModeOutlinedIcon from '@mui/icons-material/LightModeOutlined'
import LogoutOutlinedIcon from '@mui/icons-material/LogoutOutlined'
import AppBar from '@mui/material/AppBar'
import Box from '@mui/material/Box'
import IconButton from '@mui/material/IconButton'
import Toolbar from '@mui/material/Toolbar'
import Typography from '@mui/material/Typography'
import type { SupabaseStartupStatus } from '../config/supabaseStartup.ts'
import { tokens } from '../theme/tokens.ts'
import type { ResolvedTheme } from '../theme/themePreference.ts'
import { shellCopy } from './copy.ts'

export function HomeShell({
  supabaseStatus,
  themeMode,
  onToggleTheme,
  onSignOut,
}: {
  supabaseStatus: SupabaseStartupStatus
  themeMode: ResolvedTheme
  onToggleTheme: () => void
  onSignOut?: () => void
}) {
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
            gridTemplateColumns: '48px 1fr 48px',
            alignItems: 'center',
          }}
        >
          <Box aria-hidden />
          <Typography
            component="h1"
            variant="h6"
            sx={{ textAlign: 'center', fontWeight: 700 }}
          >
            {shellCopy.appTitle}
          </Typography>
          {onSignOut && <IconButton aria-label="تسجيل الخروج" color="inherit" onClick={onSignOut}><LogoutOutlinedIcon /></IconButton>}
          <IconButton aria-label={toggleLabel} color="inherit" onClick={onToggleTheme}>
            {isDark ? <LightModeOutlinedIcon /> : <DarkModeOutlinedIcon />}
          </IconButton>
        </Toolbar>
      </AppBar>
      <Box
        component="main"
        sx={{
          width: '100%',
          maxWidth: tokens.contentMaxWidth,
          mx: 'auto',
          px: { xs: '20px', md: '32px' },
          py: { xs: '20px', md: '32px' },
          display: 'grid',
          gap: 2,
        }}
      >
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

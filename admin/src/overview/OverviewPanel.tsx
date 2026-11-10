import ChevronLeftOutlinedIcon from '@mui/icons-material/ChevronLeftOutlined'
import RefreshOutlinedIcon from '@mui/icons-material/RefreshOutlined'
import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import ButtonBase from '@mui/material/ButtonBase'
import Typography from '@mui/material/Typography'
import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react'
import { formatAdminPath, subscribersRoute, type AdminRoute } from '../navigation/adminRoutes.ts'
import { formatExactCount, formatServerInstant } from '../subscribers/subscriptionFormat.ts'
import { tokens } from '../theme/tokens.ts'
import { OverviewError, type AdminOverview, type OverviewGateway } from './OverviewGateway.ts'
import { overviewCopy } from './copy.ts'

type Phase = 'loading' | 'ready' | 'error' | 'accessLost'

/**
 * Platform-admin home (ADR 0045): figures from one server snapshot. Each
 * subscription and expiring figure opens the subscriber list behind it.
 */
export function OverviewPanel({
  gateway,
  onAccessLost,
  onOpen,
}: {
  gateway: OverviewGateway
  onAccessLost: () => void
  onOpen: (route: AdminRoute) => void
}) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [overview, setOverview] = useState<AdminOverview | null>(null)
  const [reloadToken, setReloadToken] = useState(0)
  const requestRef = useRef(0)

  useEffect(() => {
    const requestId = ++requestRef.current
    void gateway.get().then(
      (result) => {
        if (requestId !== requestRef.current) return
        setOverview(result)
        setPhase('ready')
      },
      (error: unknown) => {
        if (requestId !== requestRef.current) return
        if (error instanceof OverviewError && error.code === 'unauthorized') {
          setOverview(null)
          setPhase('accessLost')
          onAccessLost()
          return
        }
        setPhase('error')
      },
    )
    return () => {
      requestRef.current += 1
    }
  }, [gateway, onAccessLost, reloadToken])

  useEffect(() => {
    const revalidate = () => {
      if (document.visibilityState === 'visible') setReloadToken((value) => value + 1)
    }
    document.addEventListener('visibilitychange', revalidate)
    return () => document.removeEventListener('visibilitychange', revalidate)
  }, [])

  const reload = () => {
    setPhase('loading')
    setReloadToken((value) => value + 1)
  }

  if (phase === 'accessLost') return null

  return (
    <Box component="section" aria-labelledby="overview-title" sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, minWidth: 0 }}>
      <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'flex-start', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Box sx={{ minWidth: 0 }}>
          <Typography id="overview-title" component="h2" variant="h5" sx={{ fontWeight: 700, lineHeight: 1.4, mb: 0.5 }}>
            {overviewCopy.title}
          </Typography>
          <Typography sx={{ lineHeight: 1.6 }}>{overviewCopy.intro}</Typography>
        </Box>
        <Button
          variant="outlined"
          onClick={reload}
          disabled={phase === 'loading'}
          startIcon={<RefreshOutlinedIcon aria-hidden />}
        >
          {overviewCopy.refresh}
        </Button>
      </Box>

      {phase === 'loading' && overview === null && (
        <Typography role="status">{overviewCopy.loading}</Typography>
      )}
      {phase === 'error' && (
        <Alert
          severity="error"
          action={<Button color="inherit" onClick={reload}>{overviewCopy.retry}</Button>}
        >
          {overviewCopy.loadError}
        </Alert>
      )}

      {overview !== null && (
        <Box aria-busy={phase === 'loading'} sx={{ display: 'grid', gap: `${tokens.spaceLg}px`, minWidth: 0 }}>
          <Typography variant="body2" data-testid="overview-snapshot">
            {overviewCopy.snapshot}: <bdi>{formatServerInstant(overview.snapshotAt)}</bdi>
          </Typography>

          <Section title={overviewCopy.subscriptionsTitle}>
            <FigureGrid>
              <Figure label={overviewCopy.allShops} value={overview.subscriptions.all} route={subscribersRoute('all')} onOpen={onOpen} />
              <Figure label={overviewCopy.active} value={overview.subscriptions.active} route={subscribersRoute('active')} onOpen={onOpen} />
              <Figure label={overviewCopy.pending} value={overview.subscriptions.pending} route={subscribersRoute('pending')} onOpen={onOpen} />
              <Figure label={overviewCopy.expired} value={overview.subscriptions.expired} route={subscribersRoute('expired')} onOpen={onOpen} />
            </FigureGrid>
          </Section>

          <Section title={overviewCopy.expiringTitle} hint={overviewCopy.expiringHint}>
            <FigureGrid>
              <Figure label={overviewCopy.within3} value={overview.expiring.within3Days} route={subscribersRoute('expiring_3')} onOpen={onOpen} emphasize />
              <Figure label={overviewCopy.within7} value={overview.expiring.within7Days} route={subscribersRoute('expiring_7')} onOpen={onOpen} />
              <Figure label={overviewCopy.within30} value={overview.expiring.within30Days} route={subscribersRoute('expiring_30')} onOpen={onOpen} />
            </FigureGrid>
          </Section>

          <Section title={overviewCopy.registrationsTitle} hint={overviewCopy.registrationsHint}>
            <FigureGrid>
              <Figure label={overviewCopy.last7} value={overview.registrations.last7Days} />
              <Figure label={overviewCopy.last30} value={overview.registrations.last30Days} />
            </FigureGrid>
          </Section>

          <Section
            title={overviewCopy.supportTitle}
            action={<SectionLink label={overviewCopy.openSupport} route={{ area: 'support' }} onOpen={onOpen} />}
          >
            <FigureGrid>
              <Figure label={overviewCopy.supportNew} value={overview.support.new} emphasize />
              <Figure label={overviewCopy.supportInProgress} value={overview.support.inProgress} />
              <Figure label={overviewCopy.supportAnswered} value={overview.support.answered} />
            </FigureGrid>
          </Section>

          <Section title={overviewCopy.appTitle}>
            <Box
              component="dl"
              sx={{
                m: 0,
                p: `${tokens.spaceMd}px`,
                borderRadius: `${tokens.cardRadius}px`,
                border: 1,
                borderColor: 'divider',
                bgcolor: 'background.paper',
                display: 'grid',
                gridTemplateColumns: 'auto 1fr',
                columnGap: `${tokens.spaceMd}px`,
                rowGap: `${tokens.spaceSm}px`,
                alignItems: 'baseline',
              }}
            >
              {overview.appVersions.map((row) => (
                <AppRow
                  key={row.platform}
                  label={overviewCopy[row.platform]}
                  value={row.minVersion === null ? overviewCopy.noMinimum : overviewCopy.minimum(row.minVersion)}
                />
              ))}
              <AppRow
                label={overviewCopy.announcement}
                value={overview.announcementPublished ? overviewCopy.announcementPublished : overviewCopy.announcementNone}
              />
            </Box>
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}>
              <SectionLink label={overviewCopy.openAppVersion} route={{ area: 'appVersion' }} onOpen={onOpen} />
              <SectionLink label={overviewCopy.openHelp} route={{ area: 'help' }} onOpen={onOpen} />
            </Box>
          </Section>
        </Box>
      )}
    </Box>
  )
}

function Section({
  title,
  hint,
  action,
  children,
}: {
  title: string
  hint?: string
  action?: ReactNode
  children: ReactNode
}) {
  return (
    <Box component="section" aria-label={title} sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, minWidth: 0 }}>
      <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Typography component="h3" variant="h6" sx={{ fontWeight: 700, fontSize: tokens.titleSize, lineHeight: 1.4 }}>
          {title}
        </Typography>
        {action}
      </Box>
      {hint && <Typography variant="body2" sx={{ lineHeight: 1.6 }}>{hint}</Typography>}
      {children}
    </Box>
  )
}

function FigureGrid({ children }: { children: ReactNode }) {
  return (
    <Box
      sx={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 180px), 1fr))',
        gap: `${tokens.spaceSm}px`,
      }}
    >
      {children}
    </Box>
  )
}

function plainClick(event: MouseEvent<HTMLAnchorElement>): boolean {
  return !(
    event.defaultPrevented
    || event.button !== 0
    || event.metaKey
    || event.ctrlKey
    || event.shiftKey
    || event.altKey
  )
}

/** A figure tile. With a route it is a link to the list behind the number. */
function Figure({
  label,
  value,
  route,
  onOpen,
  emphasize = false,
}: {
  label: string
  value: string
  route?: AdminRoute
  onOpen?: (route: AdminRoute) => void
  emphasize?: boolean
}) {
  const highlighted = emphasize && value !== '0'
  const content = (
    <>
      <Typography component="span" variant="subtitle2" sx={{ fontWeight: 600, lineHeight: 1.5, textAlign: 'start' }}>
        {label}
      </Typography>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1, width: '100%' }}>
        <Typography
          component="span"
          dir="ltr"
          sx={{
            fontSize: tokens.figureSize,
            fontWeight: 700,
            fontVariantNumeric: 'tabular-nums',
            lineHeight: 1.3,
            color: highlighted ? 'primary.main' : 'text.primary',
          }}
        >
          {formatExactCount(value)}
        </Typography>
        {route && <ChevronLeftOutlinedIcon aria-hidden sx={{ color: 'text.secondary' }} />}
      </Box>
    </>
  )
  const frame = {
    display: 'grid',
    // ButtonBase centers its content by default; keep tiles start-aligned.
    gridTemplateColumns: 'minmax(0, 1fr)',
    justifyContent: 'stretch',
    alignItems: 'start',
    gap: `${tokens.spaceSm / 2}px`,
    justifyItems: 'start',
    alignContent: 'start',
    width: '100%',
    minHeight: 96,
    p: `${tokens.spaceMd}px`,
    borderRadius: `${tokens.cardRadius}px`,
    border: 1,
    borderColor: highlighted ? 'primary.main' : 'divider',
    bgcolor: 'background.paper',
    color: 'text.primary',
    textAlign: 'start',
    minWidth: 0,
  } as const
  if (!route || !onOpen) {
    return <Box role="group" aria-label={`${label}: ${value}`} sx={frame}>{content}</Box>
  }
  return (
    <ButtonBase
      component="a"
      href={formatAdminPath(route)}
      aria-label={`${overviewCopy.showList(label)} (${value})`}
      onClick={(event: MouseEvent<HTMLAnchorElement>) => {
        if (!plainClick(event)) return
        event.preventDefault()
        onOpen(route)
      }}
      sx={{
        ...frame,
        transition: 'border-color 120ms',
        '&:hover': { borderColor: 'primary.main' },
        '&.Mui-focusVisible': { outline: '2px solid', outlineColor: 'primary.main', outlineOffset: 2 },
      }}
    >
      {content}
    </ButtonBase>
  )
}

function SectionLink({
  label,
  route,
  onOpen,
}: {
  label: string
  route: AdminRoute
  onOpen: (route: AdminRoute) => void
}) {
  return (
    <Button
      variant="text"
      href={formatAdminPath(route)}
      onClick={(event: MouseEvent<HTMLAnchorElement>) => {
        if (!plainClick(event)) return
        event.preventDefault()
        onOpen(route)
      }}
      endIcon={<ChevronLeftOutlinedIcon aria-hidden />}
    >
      {label}
    </Button>
  )
}

function AppRow({ label, value }: { label: string; value: string }) {
  return (
    <>
      <Typography component="dt" sx={{ fontWeight: 600 }}>{label}</Typography>
      <Typography component="dd" sx={{ m: 0 }}><bdi>{value}</bdi></Typography>
    </>
  )
}

import RefreshOutlinedIcon from '@mui/icons-material/RefreshOutlined'
import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Link from '@mui/material/Link'
import MenuItem from '@mui/material/MenuItem'
import TextField from '@mui/material/TextField'
import ToggleButton from '@mui/material/ToggleButton'
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup'
import Typography from '@mui/material/Typography'
import { useEffect, useRef, useState, type MouseEvent } from 'react'
import { formatAdminPath, subscribersRoute, type AdminRoute } from '../navigation/adminRoutes.ts'
import { formatServerInstant } from '../subscribers/subscriptionFormat.ts'
import { tokens } from '../theme/tokens.ts'
import {
  AuditError,
  auditFamilies,
  type AuditEvent,
  type AuditFamilyFilter,
  type AuditGateway,
} from './AuditGateway.ts'
import { auditActionLabel, auditCopy, auditFamilyLabel, auditSummary } from './copy.ts'

type Phase = 'loading' | 'ready' | 'error' | 'accessLost'

/** Read-only platform-admin action history (ADR 0046). */
export function AuditLogPanel({
  gateway,
  onAccessLost,
  onOpen,
}: {
  gateway: AuditGateway
  onAccessLost: () => void
  onOpen: (route: AdminRoute) => void
}) {
  const [family, setFamily] = useState<AuditFamilyFilter>('all')
  const [actor, setActor] = useState<string | null>(null)
  const [reloadToken, setReloadToken] = useState(0)
  const [phase, setPhase] = useState<Phase>('loading')
  const [rows, setRows] = useState<AuditEvent[]>([])
  const [cursor, setCursor] = useState<string | null>(null)
  const [snapshotAt, setSnapshotAt] = useState<string | null>(null)
  const [admins, setAdmins] = useState<Array<{ userId: string; email: string }>>([])
  const [loadingMore, setLoadingMore] = useState(false)
  const [pageFailed, setPageFailed] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const requestRef = useRef(0)

  const loseAccess = () => {
    requestRef.current += 1
    setRows([])
    setCursor(null)
    setPhase('accessLost')
    onAccessLost()
  }

  useEffect(() => {
    const requestId = ++requestRef.current
    void gateway.list({ family, actorUserId: actor, cursor: null }).then(
      (page) => {
        if (requestId !== requestRef.current) return
        setRows(page.rows)
        setCursor(page.nextCursor)
        setSnapshotAt(page.snapshotAt)
        setAdmins(page.admins)
        setPhase('ready')
      },
      (error: unknown) => {
        if (requestId !== requestRef.current) return
        if (error instanceof AuditError && error.code === 'unauthorized') {
          requestRef.current += 1
          setRows([])
          setCursor(null)
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
  }, [gateway, onAccessLost, family, actor, reloadToken])

  const reload = () => {
    setPhase('loading')
    setPageFailed(false)
    setNotice(null)
    setReloadToken((value) => value + 1)
  }

  const changeFamily = (next: AuditFamilyFilter | null) => {
    if (next === null || next === family) return
    setRows([])
    setCursor(null)
    setPhase('loading')
    setPageFailed(false)
    setNotice(null)
    setFamily(next)
  }

  const changeActor = (next: string | null) => {
    if (next === actor) return
    setRows([])
    setCursor(null)
    setPhase('loading')
    setPageFailed(false)
    setNotice(null)
    setActor(next)
  }

  const loadMore = async () => {
    if (cursor === null || loadingMore) return
    const requestId = requestRef.current
    setLoadingMore(true)
    setPageFailed(false)
    try {
      const page = await gateway.list({ family, actorUserId: actor, cursor })
      if (requestId !== requestRef.current) return
      setRows((current) => [...current, ...page.rows])
      setCursor(page.nextCursor)
      setSnapshotAt(page.snapshotAt)
    } catch (error) {
      if (requestId !== requestRef.current) return
      if (error instanceof AuditError && error.code === 'unauthorized') {
        loseAccess()
        return
      }
      if (error instanceof AuditError && error.code === 'stale') {
        reload()
        setNotice(auditCopy.staleReset)
        return
      }
      setPageFailed(true)
    } finally {
      if (requestId === requestRef.current) setLoadingMore(false)
    }
  }

  if (phase === 'accessLost') return null

  return (
    <Box component="section" aria-labelledby="audit-title" sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, minWidth: 0 }}>
      <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'flex-start', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Box sx={{ minWidth: 0, flex: '1 1 320px' }}>
          <Typography id="audit-title" component="h2" variant="h5" sx={{ fontWeight: 700, lineHeight: 1.4, mb: 0.5 }}>
            {auditCopy.title}
          </Typography>
          <Typography sx={{ lineHeight: 1.6 }}>{auditCopy.intro}</Typography>
        </Box>
        <Button variant="outlined" onClick={reload} disabled={phase === 'loading'} startIcon={<RefreshOutlinedIcon aria-hidden />}>
          {auditCopy.refresh}
        </Button>
      </Box>

      <ToggleButtonGroup
        exclusive
        value={family}
        onChange={(_, value: AuditFamilyFilter | null) => changeFamily(value)}
        aria-label={auditCopy.familyGroup}
        sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}
      >
        {(['all', ...auditFamilies] as AuditFamilyFilter[]).map((value) => (
          <ToggleButton key={value} value={value} aria-pressed={family === value} sx={{ minHeight: `${tokens.minControlSize}px`, px: 2 }}>
            {auditFamilyLabel[value]}
          </ToggleButton>
        ))}
      </ToggleButtonGroup>

      <TextField
        select
        label={auditCopy.actorLabel}
        value={actor ?? ''}
        onChange={(event) => changeActor(event.target.value === '' ? null : event.target.value)}
        // Show «كل المسؤولين» for the empty value instead of a blank field.
        slotProps={{ select: { displayEmpty: true }, inputLabel: { shrink: true } }}
        sx={{ maxWidth: 420 }}
      >
        <MenuItem value="">{auditCopy.actorAll}</MenuItem>
        {admins.map((admin) => (
          <MenuItem key={admin.userId} value={admin.userId}>
            <bdi dir="ltr">{admin.email}</bdi>
          </MenuItem>
        ))}
      </TextField>

      {notice && <Alert severity="info" role="status">{notice}</Alert>}
      {snapshotAt && phase !== 'error' && (
        <Typography variant="body2" data-testid="audit-snapshot">
          {auditCopy.snapshot}: <bdi>{formatServerInstant(snapshotAt)}</bdi>
        </Typography>
      )}
      {phase === 'loading' && <Typography role="status">{auditCopy.loading}</Typography>}
      {phase === 'error' && (
        <Alert severity="error" action={<Button color="inherit" onClick={reload}>{auditCopy.retry}</Button>}>
          {auditCopy.loadError}
        </Alert>
      )}
      {phase === 'ready' && rows.length === 0 && <Typography>{auditCopy.empty}</Typography>}

      {rows.length > 0 && (
        <Box component="ol" aria-label={auditCopy.listLabel} aria-busy={phase === 'loading'} sx={{ listStyle: 'none', m: 0, p: 0, display: 'grid', gap: `${tokens.spaceSm}px` }}>
          {rows.map((event) => (
            <AuditRow key={event.eventKey} event={event} onOpen={onOpen} />
          ))}
        </Box>
      )}

      {pageFailed && <Alert severity="error">{auditCopy.pageError}</Alert>}
      {cursor !== null && phase === 'ready' && (
        <Button variant="outlined" onClick={() => void loadMore()} disabled={loadingMore} sx={{ justifySelf: 'center', minWidth: 200 }}>
          {loadingMore ? auditCopy.loadingMore : auditCopy.loadMore}
        </Button>
      )}
    </Box>
  )
}

function AuditRow({ event, onOpen }: { event: AuditEvent; onOpen: (route: AdminRoute) => void }) {
  const summary = auditSummary(event.action, event.details)
  const shopRoute = event.shopId === null ? null : subscribersRoute('all', event.shopId)
  return (
    <Box
      component="li"
      sx={{
        p: `${tokens.spaceMd}px`,
        borderRadius: `${tokens.cardRadius}px`,
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        display: 'grid',
        gap: 0.5,
        minWidth: 0,
      }}
    >
      <Box sx={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Typography component="h3" sx={{ fontWeight: 700, lineHeight: 1.5 }}>
          {auditActionLabel[event.action]}
        </Typography>
        <Typography variant="body2" component="span">
          <bdi>{formatServerInstant(event.occurredAt)}</bdi>
        </Typography>
      </Box>
      {summary && <Typography sx={{ lineHeight: 1.6, overflowWrap: 'anywhere' }}><bdi>{summary}</bdi></Typography>}
      {shopRoute && event.shopId && (
        <Typography variant="body2">
          {auditCopy.shopLabel}:{' '}
          <Link
            href={formatAdminPath(shopRoute)}
            aria-label={auditCopy.openShop(event.shopName ?? event.shopId)}
            onClick={(clickEvent: MouseEvent<HTMLAnchorElement>) => {
              if (clickEvent.button !== 0 || clickEvent.metaKey || clickEvent.ctrlKey || clickEvent.shiftKey || clickEvent.altKey) return
              clickEvent.preventDefault()
              onOpen(shopRoute)
            }}
          >
            <bdi>{event.shopName ?? event.shopId}</bdi>
          </Link>
        </Typography>
      )}
      <Typography variant="body2" sx={{ color: 'text.secondary', overflowWrap: 'anywhere' }}>
        {auditCopy.actorLabel}:{' '}
        {event.actorEmail === null ? auditCopy.unknownActor : <bdi dir="ltr">{event.actorEmail}</bdi>}
      </Typography>
    </Box>
  )
}

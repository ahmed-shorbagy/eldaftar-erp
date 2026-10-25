import RefreshOutlinedIcon from '@mui/icons-material/RefreshOutlined'
import SearchOutlinedIcon from '@mui/icons-material/SearchOutlined'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Chip from '@mui/material/Chip'
import Dialog from '@mui/material/Dialog'
import DialogActions from '@mui/material/DialogActions'
import DialogContent from '@mui/material/DialogContent'
import DialogTitle from '@mui/material/DialogTitle'
import Table from '@mui/material/Table'
import TableBody from '@mui/material/TableBody'
import TableCell from '@mui/material/TableCell'
import TableContainer from '@mui/material/TableContainer'
import TableHead from '@mui/material/TableHead'
import TableRow from '@mui/material/TableRow'
import TextField from '@mui/material/TextField'
import ToggleButton from '@mui/material/ToggleButton'
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup'
import Typography from '@mui/material/Typography'
import useMediaQuery from '@mui/material/useMediaQuery'
import { useTheme } from '@mui/material/styles'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { tokens } from '../theme/tokens.ts'
import { subscriberCopy } from './copy.ts'
import type { SubscriberContactGateway } from './SubscriberContactGateway.ts'
import { SubscriberContactReveal } from './SubscriberContactReveal.tsx'
import {
  SubscriberDirectoryError,
  type SubscriberDirectoryGateway,
  type SubscriberStatusFilter,
} from './SubscriberDirectoryGateway.ts'
import { SubscriptionCodesPanel } from './SubscriptionCodesPanel.tsx'
import {
  formatExactCount,
  formatServerInstant,
  type SubscriberDetail,
  type SubscriberPage,
  type SubscriberRow,
  type SubscriptionStatus,
} from './subscriptionFormat.ts'

interface DirectoryQuery {
  status: SubscriberStatusFilter
  search: string
  cursor: string | null
  previousCursors: Array<string | null>
}

const initialQuery: DirectoryQuery = {
  status: 'all',
  search: '',
  cursor: null,
  previousCursors: [],
}

const exactCountSx = {
  fontVariantNumeric: 'tabular-nums',
  fontWeight: 700,
  fontSize: tokens.figureSize,
  textAlign: 'start',
  overflowWrap: 'anywhere',
  minWidth: 0,
  maxWidth: '100%',
  lineHeight: 1.35,
} as const

const filters: Array<{ value: SubscriberStatusFilter; label: string }> = [
  { value: 'all', label: subscriberCopy.filterAll },
  { value: 'active', label: subscriberCopy.statusActive },
  { value: 'pending', label: subscriberCopy.statusPending },
  { value: 'expired', label: subscriberCopy.statusExpired },
]

type DetailState =
  | { phase: 'loading'; shopId: string; shopName: string }
  | { phase: 'ready'; detail: SubscriberDetail }
  | { phase: 'error'; shopId: string; shopName: string; notFound: boolean }

export function SubscriberDirectory({
  gateway,
  contactGateway = null,
  onAccessLost,
}: {
  gateway: SubscriberDirectoryGateway
  contactGateway?: SubscriberContactGateway | null
  onAccessLost: () => void
}) {
  const theme = useTheme()
  const narrow = useMediaQuery(theme.breakpoints.down('md'), { noSsr: true })
  const [query, setQuery] = useState<DirectoryQuery>(initialQuery)
  const [draftSearch, setDraftSearch] = useState('')
  const [refreshToken, setRefreshToken] = useState(0)
  const [phase, setPhase] = useState<'loading' | 'ready' | 'error' | 'accessLost'>('loading')
  const [page, setPage] = useState<SubscriberPage | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [detail, setDetail] = useState<DetailState | null>(null)
  const requestRef = useRef(0)
  const detailRef = useRef(0)
  const loadKey = `${query.status}\u0000${query.search}\u0000${query.cursor ?? ''}\u0000${refreshToken}`
  const [seenLoadKey, setSeenLoadKey] = useState(loadKey)
  if (seenLoadKey !== loadKey) {
    setSeenLoadKey(loadKey)
    setPhase('loading')
    setPage(null)
    setDetail(null)
  }

  useEffect(() => {
    const requestId = ++requestRef.current
    let active = true
    detailRef.current += 1
    void gateway.list({
      status: query.status,
      search: query.search,
      cursor: query.cursor,
    }).then(
      (result) => {
        if (!active || requestId !== requestRef.current) return
        setPage(result)
        setPhase('ready')
      },
      (error: unknown) => {
        if (!active || requestId !== requestRef.current) return
        if (error instanceof SubscriberDirectoryError && error.code === 'access_lost') {
          requestRef.current += 1
          setPage(null)
          setDetail(null)
          setNotice(null)
          setPhase('accessLost')
          onAccessLost()
          return
        }
        if (
          error instanceof SubscriberDirectoryError
          && error.code === 'stale_cursor'
          && query.cursor !== null
        ) {
          setNotice(subscriberCopy.staleReset)
          setQuery((current) => ({ ...current, cursor: null, previousCursors: [] }))
          return
        }
        setPage(null)
        setPhase('error')
      },
    )
    return () => {
      active = false
    }
  }, [gateway, onAccessLost, query, refreshToken])

  useEffect(() => {
    const revalidate = () => {
      if (document.visibilityState !== 'visible') return
      setRefreshToken((value) => value + 1)
    }
    document.addEventListener('visibilitychange', revalidate)
    return () => document.removeEventListener('visibilitychange', revalidate)
  }, [])

  function replaceQuery(next: DirectoryQuery) {
    setNotice(null)
    setPage(null)
    setDetail(null)
    setPhase('loading')
    setQuery(next)
  }

  function changeStatus(next: SubscriberStatusFilter | null) {
    if (next === null || next === query.status) return
    replaceQuery({
      ...query,
      status: next,
      cursor: null,
      previousCursors: [],
    })
  }

  function applySearch() {
    replaceQuery({
      ...query,
      search: draftSearch.trim(),
      cursor: null,
      previousCursors: [],
    })
    setRefreshToken((value) => value + 1)
  }

  function clearSearch() {
    setDraftSearch('')
    replaceQuery({
      ...query,
      search: '',
      cursor: null,
      previousCursors: [],
    })
    setRefreshToken((value) => value + 1)
  }

  async function openDetail(row: SubscriberRow) {
    const requestId = ++detailRef.current
    setDetail({ phase: 'loading', shopId: row.shopId, shopName: row.shopName })
    try {
      const result = await gateway.get(row.shopId)
      if (requestId !== detailRef.current) return
      setDetail({ phase: 'ready', detail: result })
    } catch (error) {
      if (requestId !== detailRef.current) return
      if (error instanceof SubscriberDirectoryError && error.code === 'access_lost') {
        requestRef.current += 1
        detailRef.current += 1
        setPage(null)
        setDetail(null)
        setNotice(null)
        setPhase('accessLost')
        onAccessLost()
        return
      }
      setDetail({
        phase: 'error',
        shopId: row.shopId,
        shopName: row.shopName,
        notFound: error instanceof SubscriberDirectoryError && error.code === 'not_found',
      })
    }
  }

  function closeDetail() {
    detailRef.current += 1
    setDetail(null)
  }

  const pageNumber = query.previousCursors.length + 1
  const loading = phase === 'loading'

  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceLg}px`, minWidth: 0 }}>
      <Box>
        <Typography component="h2" variant="h5" sx={{ fontWeight: 700, lineHeight: 1.4 }}>
          {subscriberCopy.heading}
        </Typography>
        <Typography sx={{ color: 'text.primary', lineHeight: 1.6, mt: 1 }}>
          {subscriberCopy.intro}
        </Typography>
        <Typography sx={{ color: 'text.primary', lineHeight: 1.6, mt: 1 }}>
          {subscriberCopy.statusIndependence}
        </Typography>
      </Box>

      <Box
        component="form"
        role="search"
        onSubmit={(event) => {
          event.preventDefault()
          applySearch()
        }}
        sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px`, alignItems: 'flex-start' }}
      >
        <TextField
          label={subscriberCopy.searchLabel}
          helperText={subscriberCopy.searchHelp}
          value={draftSearch}
          onChange={(event) => setDraftSearch(event.target.value)}
          sx={{ flex: '1 1 220px', minWidth: 0 }}
          slotProps={{ htmlInput: { maxLength: 120, autoComplete: 'off' } }}
        />
        <Button type="submit" variant="contained" startIcon={<SearchOutlinedIcon aria-hidden />}>
          {subscriberCopy.searchAction}
        </Button>
        <Button type="button" variant="outlined" onClick={clearSearch}>
          {subscriberCopy.clearSearch}
        </Button>
        <Button
          type="button"
          variant="outlined"
          disabled={loading}
          onClick={() => {
            setPage(null)
            setDetail(null)
            setPhase('loading')
            setRefreshToken((value) => value + 1)
          }}
          startIcon={<RefreshOutlinedIcon aria-hidden />}
        >
          {subscriberCopy.refresh}
        </Button>
      </Box>

      <ToggleButtonGroup
        exclusive
        value={query.status}
        onChange={(_, value: SubscriberStatusFilter | null) => changeStatus(value)}
        aria-label={subscriberCopy.filterGroup}
        sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}
      >
        {filters.map((filter) => (
          <ToggleButton
            key={filter.value}
            value={filter.value}
            aria-pressed={query.status === filter.value}
            sx={{ minHeight: `${tokens.minControlSize}px`, px: 2 }}
          >
            {filter.label}
          </ToggleButton>
        ))}
      </ToggleButtonGroup>

      <Box
        role="group"
        aria-label={subscriberCopy.globalGroup}
        aria-busy={loading}
        sx={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 200px), 1fr))',
          gap: `${tokens.spaceSm}px`,
        }}
      >
        <CountCard label={subscriberCopy.countAll} value={page ? formatExactCount(page.counts.all) : '…'} />
        <CountCard label={subscriberCopy.countActive} value={page ? formatExactCount(page.counts.active) : '…'} />
        <CountCard label={subscriberCopy.countPending} value={page ? formatExactCount(page.counts.pending) : '…'} />
        <CountCard label={subscriberCopy.countExpired} value={page ? formatExactCount(page.counts.expired) : '…'} />
      </Box>
      <Box
        role="group"
        aria-label={subscriberCopy.filteredGroup}
        sx={{
          p: `${tokens.spaceMd}px`,
          borderRadius: `${tokens.cardRadius}px`,
          border: 1,
          borderColor: 'divider',
          bgcolor: 'background.paper',
          minWidth: 0,
        }}
      >
        <Typography component="h3" variant="subtitle2" sx={{ fontWeight: 600 }}>
          {subscriberCopy.filteredLabel}
        </Typography>
        <Typography dir="ltr" sx={exactCountSx}>
          {page ? formatExactCount(page.filteredCount) : '…'}
        </Typography>
      </Box>

      <Typography role="status" aria-live="polite" sx={{ lineHeight: 1.6, overflowWrap: 'anywhere', minWidth: 0 }}>
        {phase === 'loading' && subscriberCopy.loading}
        {phase === 'ready' && page && subscriberCopy.liveSummary(
          formatExactCount(page.counts.all),
          formatExactCount(page.filteredCount),
        )}
        {phase === 'error' && subscriberCopy.loadError}
        {phase === 'accessLost' && subscriberCopy.accessLost}
        {notice ? ` ${notice}` : ''}
      </Typography>
      {phase === 'ready' && page && (
        <Typography sx={{ color: 'text.primary', lineHeight: 1.6, overflowWrap: 'anywhere', minWidth: 0 }}>
          {subscriberCopy.snapshotLabel}: <TimeValue value={page.snapshotAt} />
        </Typography>
      )}

      {phase === 'error' && (
        <Button variant="contained" onClick={() => setRefreshToken((value) => value + 1)}>
          {subscriberCopy.retry}
        </Button>
      )}
      {phase === 'ready' && page && page.rows.length === 0 && (
        <Typography sx={{ lineHeight: 1.6 }}>
          {page.counts.all === '0' ? subscriberCopy.emptyAll : subscriberCopy.emptyFilter}
        </Typography>
      )}
      {phase === 'ready' && page && page.rows.length > 0 && (
        narrow ? (
          <Box sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, minWidth: 0 }}>
            {page.rows.map((row) => (
              <ShopCard key={row.shopId} row={row} onOpen={() => void openDetail(row)} />
            ))}
          </Box>
        ) : (
          <TableContainer sx={{ maxWidth: '100%', overflowX: 'auto' }}>
            <Table aria-label={subscriberCopy.tableLabel} sx={{ tableLayout: 'fixed', width: '100%' }}>
              <TableHead>
                <TableRow>
                  <TableCell>{subscriberCopy.columnShop}</TableCell>
                  <TableCell>{subscriberCopy.columnStatus}</TableCell>
                  <TableCell>{subscriberCopy.columnRegistered}</TableCell>
                  <TableCell>{subscriberCopy.columnStart}</TableCell>
                  <TableCell>{subscriberCopy.columnExpiry}</TableCell>
                  <TableCell>{subscriberCopy.details}</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {page.rows.map((row) => (
                  <TableRow key={row.shopId} hover>
                    <TableCell sx={{ overflowWrap: 'anywhere', minWidth: 0 }}>
                      <Typography component="h3" variant="body1" sx={{ fontWeight: 700, lineHeight: 1.5, overflowWrap: 'anywhere', m: 0 }}>
                        {row.shopName}
                      </Typography>
                      <Typography variant="body2" dir="ltr" sx={{ overflowWrap: 'anywhere', textAlign: 'right' }}>
                        {row.shopId}
                      </Typography>
                    </TableCell>
                    <TableCell><StatusValue row={row} /></TableCell>
                    <TableCell><TimeValue value={row.registeredAt} /></TableCell>
                    <TableCell><TermValue value={row.entitlementStartsAt} missingTerm={row.entitlementStartsAt === null && row.entitlementExpiresAt === null} /></TableCell>
                    <TableCell><TermValue value={row.entitlementExpiresAt} missingTerm={row.entitlementStartsAt === null && row.entitlementExpiresAt === null} /></TableCell>
                    <TableCell>
                      <Button variant="outlined" aria-label={subscriberCopy.detailsName(row.shopName)} onClick={() => void openDetail(row)}>
                        {subscriberCopy.details}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )
      )}

      {phase === 'ready' && page && (
        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px`, alignItems: 'center' }}>
          <Button
            variant="outlined"
            disabled={query.previousCursors.length === 0}
            onClick={() => {
              const previous = [...query.previousCursors]
              const cursor = previous.pop() ?? null
              replaceQuery({ ...query, previousCursors: previous, cursor })
            }}
          >
            {subscriberCopy.previousPage}
          </Button>
          <Typography>{subscriberCopy.pageLabel(pageNumber)}</Typography>
          <Button
            variant="outlined"
            disabled={page.nextCursor === null}
            onClick={() => {
              if (page.nextCursor === null) return
              replaceQuery({
                ...query,
                previousCursors: [...query.previousCursors, query.cursor],
                cursor: page.nextCursor,
              })
            }}
          >
            {subscriberCopy.nextPage}
          </Button>
        </Box>
      )}

      <Dialog
        open={detail !== null}
        onClose={closeDetail}
        fullWidth
        maxWidth="sm"
        aria-labelledby="subscriber-detail-title"
      >
        <DialogTitle id="subscriber-detail-title" sx={{ lineHeight: 1.4 }}>
          {subscriberCopy.detailTitle}
        </DialogTitle>
        <DialogContent
          role="region"
          aria-label={subscriberCopy.detailContent}
          tabIndex={0}
          sx={{
            display: 'grid',
            gap: `${tokens.spaceMd}px`,
            '&:focus-visible': { outline: '2px solid', outlineColor: 'primary.main', outlineOffset: -4 },
          }}
        >
          {detail?.phase === 'loading' && (
            <Typography role="status">{subscriberCopy.loadingDetail}</Typography>
          )}
          {detail?.phase === 'error' && (
            <Typography role="alert">
              {detail.notFound ? subscriberCopy.notFound : subscriberCopy.detailError}
            </Typography>
          )}
          {detail?.phase === 'ready' && (
            <>
              <DetailFields detail={detail.detail} />
              {contactGateway && (
                <SubscriberContactReveal
                  shopId={detail.detail.shopId}
                  gateway={contactGateway}
                  onAccessLost={() => {
                    requestRef.current += 1
                    detailRef.current += 1
                    setPage(null)
                    setDetail(null)
                    setNotice(null)
                    setPhase('accessLost')
                    onAccessLost()
                  }}
                />
              )}
              <SubscriptionCodesPanel
                shopId={detail.detail.shopId}
                shopName={detail.detail.shopName}
                gateway={gateway}
                onAccessLost={() => {
                  requestRef.current += 1
                  detailRef.current += 1
                  setPage(null)
                  setDetail(null)
                  setNotice(null)
                  setPhase('accessLost')
                  onAccessLost()
                }}
              />
            </>
          )}
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          {detail?.phase === 'error' && !detail.notFound && (
            <Button
              variant="contained"
              onClick={() => void openDetail({
                shopId: detail.shopId,
                shopName: detail.shopName,
                registeredAt: '',
                entitlementStartsAt: null,
                entitlementExpiresAt: null,
                subscriptionStatus: 'pending',
              })}
            >
              {subscriberCopy.retry}
            </Button>
          )}
          <Button variant="outlined" onClick={closeDetail} autoFocus>
            {subscriberCopy.close}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}

function CountCard({ label, value }: { label: string; value: string }) {
  return (
    <Box
      sx={{
        p: `${tokens.spaceMd}px`,
        borderRadius: `${tokens.cardRadius}px`,
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        minWidth: 0,
      }}
    >
      <Typography component="h3" variant="subtitle2" sx={{ fontWeight: 600, lineHeight: 1.5 }}>
        {label}
      </Typography>
      <Typography dir="ltr" sx={exactCountSx}>
        {value}
      </Typography>
    </Box>
  )
}

function ShopCard({ row, onOpen }: { row: SubscriberRow; onOpen: () => void }) {
  return (
    <Box
      component="article"
      sx={{
        p: `${tokens.spaceMd}px`,
        borderRadius: `${tokens.cardRadius}px`,
        border: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        display: 'grid',
        gap: `${tokens.spaceSm}px`,
        minWidth: 0,
      }}
    >
      <Typography component="h3" variant="body1" sx={{ fontWeight: 700, lineHeight: 1.5, overflowWrap: 'anywhere', m: 0 }}>
        {row.shopName}
      </Typography>
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, m: 0, minWidth: 0 }}>
        <Field label={subscriberCopy.shopId} value={<Typography dir="ltr" sx={{ overflowWrap: 'anywhere', textAlign: 'start' }}>{row.shopId}</Typography>} />
        <Field label={subscriberCopy.columnStatus} value={<StatusValue row={row} />} />
        <Field label={subscriberCopy.columnRegistered} value={<TimeValue value={row.registeredAt} />} />
        <Field label={subscriberCopy.columnStart} value={<TermValue value={row.entitlementStartsAt} missingTerm={row.entitlementStartsAt === null && row.entitlementExpiresAt === null} />} />
        <Field label={subscriberCopy.columnExpiry} value={<TermValue value={row.entitlementExpiresAt} missingTerm={row.entitlementStartsAt === null && row.entitlementExpiresAt === null} />} />
      </Box>
      <Button variant="outlined" aria-label={subscriberCopy.detailsName(row.shopName)} onClick={onOpen}>
        {subscriberCopy.details}
      </Button>
    </Box>
  )
}

function DetailFields({ detail }: { detail: SubscriberDetail }) {
  const missingTerm = detail.entitlementStartsAt === null && detail.entitlementExpiresAt === null
  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, minWidth: 0 }}>
      <Typography component="h3" variant="body1" sx={{ fontWeight: 700, lineHeight: 1.5, overflowWrap: 'anywhere', m: 0 }}>
        {detail.shopName}
      </Typography>
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, m: 0, minWidth: 0 }}>
        <Field label={subscriberCopy.shopId} value={<Typography dir="ltr" sx={{ overflowWrap: 'anywhere', textAlign: 'start' }}>{detail.shopId}</Typography>} />
        <Field label={subscriberCopy.columnStatus} value={<StatusValue row={detail} />} />
        <Field label={subscriberCopy.columnRegistered} value={<TimeValue value={detail.registeredAt} />} />
        <Field label={subscriberCopy.columnStart} value={<TermValue value={detail.entitlementStartsAt} missingTerm={missingTerm} />} />
        <Field label={subscriberCopy.columnExpiry} value={<TermValue value={detail.entitlementExpiresAt} missingTerm={missingTerm} />} />
        <Field label={subscriberCopy.snapshotLabel} value={<TimeValue value={detail.snapshotAt} />} />
      </Box>
    </Box>
  )
}

function Field({ label, value }: { label: string; value: ReactNode }) {
  return (
    <Box sx={{ minWidth: 0 }}>
      <Typography component="dt" variant="subtitle2" sx={{ fontWeight: 600 }}>{label}</Typography>
      <Box component="dd" sx={{ m: 0, lineHeight: 1.6, overflowWrap: 'anywhere', minWidth: 0 }}>{value}</Box>
    </Box>
  )
}

function StatusValue({ row }: { row: SubscriberRow }) {
  const label = statusLabel(row.subscriptionStatus)
  const color = row.subscriptionStatus === 'active'
    ? 'success'
    : row.subscriptionStatus === 'pending'
      ? 'primary'
      : 'default'
  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceSm / 2}px`, justifyItems: 'start' }}>
      <Chip color={color} variant="outlined" label={label} />
      {row.subscriptionStatus === 'pending' && row.entitlementStartsAt !== null && (
        <Typography variant="body2">{subscriberCopy.futureTerm}</Typography>
      )}
      {row.entitlementStartsAt === null && row.entitlementExpiresAt === null && (
        <Typography variant="body2">{subscriberCopy.missingTerm}</Typography>
      )}
    </Box>
  )
}

function TermValue({ value, missingTerm }: { value: string | null; missingTerm: boolean }) {
  if (missingTerm) return <Typography>{subscriberCopy.missingTerm}</Typography>
  if (value === null) return <Typography>{subscriberCopy.missingDate}</Typography>
  return <TimeValue value={value} />
}

function TimeValue({ value }: { value: string }) {
  const formatted = formatServerInstant(value)
  return (
    <Typography component="span" sx={{ display: 'inline', fontVariantNumeric: 'tabular-nums', overflowWrap: 'anywhere' }}>
      {formatted}
    </Typography>
  )
}

function statusLabel(status: SubscriptionStatus): string {
  switch (status) {
    case 'active':
      return subscriberCopy.statusActive
    case 'pending':
      return subscriberCopy.statusPending
    case 'expired':
      return subscriberCopy.statusExpired
  }
}

import AddCommentOutlinedIcon from '@mui/icons-material/AddCommentOutlined'
import RefreshOutlinedIcon from '@mui/icons-material/RefreshOutlined'
import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Chip from '@mui/material/Chip'
import Dialog from '@mui/material/Dialog'
import DialogActions from '@mui/material/DialogActions'
import DialogContent from '@mui/material/DialogContent'
import DialogTitle from '@mui/material/DialogTitle'
import MenuItem from '@mui/material/MenuItem'
import TextField from '@mui/material/TextField'
import ToggleButton from '@mui/material/ToggleButton'
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup'
import Typography from '@mui/material/Typography'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { formatExactCount, formatServerInstant } from '../subscribers/subscriptionFormat.ts'
import { tokens } from '../theme/tokens.ts'
import {
  BroadcastError,
  bodyMax,
  broadcastSegments,
  normalizeDraft,
  reasonMax,
  reasonMin,
  titleMax,
  validateDraft,
  type BroadcastDraft,
  type BroadcastGateway,
  type BroadcastRow,
  type BroadcastSegment,
  type DraftErrors,
  type SendInput,
  type SendResult,
} from './BroadcastGateway.ts'
import { broadcastCopy, segmentLabel, segmentSummary, stateLabel } from './copy.ts'

interface FormState {
  segment: BroadcastSegment
  days: string
  shopId: string
  title: string
  body: string
  link: string
  scheduled: boolean
  startsLocal: string
  customEnd: boolean
  endsLocal: string
}

type ComposePhase =
  | { step: 'form'; errors: DraftErrors; previewing: boolean; notice: string | null }
  | { step: 'review'; input: SendInput }
  | { step: 'sending'; input: SendInput }
  | { step: 'sent'; result: SendResult }
  | { step: 'retry'; input: SendInput; message: string }
  | { step: 'changed'; draft: BroadcastDraft }
  | { step: 'final'; message: string }

type ListPhase = 'loading' | 'ready' | 'error' | 'accessLost'

function emptyForm(shopId: string | null): FormState {
  return {
    segment: shopId ? 'shop' : 'all',
    days: '7',
    shopId: shopId ?? '',
    title: '',
    body: '',
    link: '',
    scheduled: false,
    startsLocal: '',
    customEnd: false,
    endsLocal: '',
  }
}

/** A `datetime-local` value is the viewer's local wall time. */
function localToIso(value: string): string | null {
  if (value.trim() === '') return null
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? 'invalid' : parsed.toISOString()
}

function toDraft(form: FormState): BroadcastDraft {
  const days = /^[0-9]+$/.test(form.days.trim()) ? Number(form.days.trim()) : null
  return normalizeDraft({
    segment: form.segment,
    days: form.segment === 'expiring' ? days : null,
    shopId: form.segment === 'shop' ? form.shopId : null,
    titleAr: form.title,
    bodyAr: form.body,
    linkUrl: form.link,
    startsAt: form.scheduled ? localToIso(form.startsLocal) ?? 'invalid' : null,
    endsAt: form.customEnd ? localToIso(form.endsLocal) ?? 'invalid' : null,
  })
}

/** Platform-admin broadcasts to shop owners (ADR 0048, ADM-06). */
export function BroadcastsPanel({
  gateway,
  onAccessLost,
  initialShopId = null,
}: {
  gateway: BroadcastGateway
  onAccessLost: () => void
  initialShopId?: string | null
}) {
  const [rows, setRows] = useState<BroadcastRow[]>([])
  const [cursor, setCursor] = useState<string | null>(null)
  const [snapshotAt, setSnapshotAt] = useState<string | null>(null)
  const [listPhase, setListPhase] = useState<ListPhase>('loading')
  const [reloadToken, setReloadToken] = useState(0)
  const [loadingMore, setLoadingMore] = useState(false)
  const [pageFailed, setPageFailed] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const listRef = useRef(0)

  const [composeOpen, setComposeOpen] = useState(initialShopId !== null)
  const [form, setForm] = useState<FormState>(() => emptyForm(initialShopId))
  const [compose, setCompose] = useState<ComposePhase>({ step: 'form', errors: {}, previewing: false, notice: null })
  const composeRef = useRef(0)
  const sendingRef = useRef(false)

  const [withdrawTarget, setWithdrawTarget] = useState<BroadcastRow | null>(null)
  const [withdrawReason, setWithdrawReason] = useState('')
  const [withdrawState, setWithdrawState] = useState<'form' | 'invalid' | 'pending' | 'done' | 'already' | 'failed'>('form')
  const withdrawRef = useRef(0)

  const loseAccess = () => {
    listRef.current += 1
    composeRef.current += 1
    withdrawRef.current += 1
    setRows([])
    setCursor(null)
    setComposeOpen(false)
    setWithdrawTarget(null)
    setListPhase('accessLost')
    onAccessLost()
  }
  const loseAccessRef = useRef(loseAccess)
  useEffect(() => {
    loseAccessRef.current = loseAccess
  })

  useEffect(() => {
    const requestId = ++listRef.current
    void gateway.list(null).then(
      (page) => {
        if (requestId !== listRef.current) return
        setRows(page.rows)
        setCursor(page.nextCursor)
        setSnapshotAt(page.snapshotAt)
        setListPhase('ready')
      },
      (error: unknown) => {
        if (requestId !== listRef.current) return
        if (error instanceof BroadcastError && error.code === 'unauthorized') {
          loseAccessRef.current()
          return
        }
        setListPhase('error')
      },
    )
    return () => {
      listRef.current += 1
    }
  }, [gateway, reloadToken])

  const reload = () => {
    setListPhase('loading')
    setPageFailed(false)
    setNotice(null)
    setReloadToken((value) => value + 1)
  }

  const loadMore = async () => {
    if (cursor === null || loadingMore) return
    const requestId = listRef.current
    setLoadingMore(true)
    setPageFailed(false)
    try {
      const page = await gateway.list(cursor)
      if (requestId !== listRef.current) return
      setRows((current) => [...current, ...page.rows.filter((row) => !current.some((seen) => seen.id === row.id))])
      setCursor(page.nextCursor)
    } catch (error) {
      if (requestId !== listRef.current) return
      if (error instanceof BroadcastError && error.code === 'unauthorized') {
        loseAccess()
        return
      }
      if (error instanceof BroadcastError && error.code === 'stale') {
        reload()
        setNotice(broadcastCopy.staleReset)
        return
      }
      setPageFailed(true)
    } finally {
      if (requestId === listRef.current) setLoadingMore(false)
    }
  }

  function openCompose() {
    composeRef.current += 1
    sendingRef.current = false
    setForm(emptyForm(null))
    setCompose({ step: 'form', errors: {}, previewing: false, notice: null })
    setComposeOpen(true)
  }

  function closeCompose() {
    composeRef.current += 1
    sendingRef.current = false
    setComposeOpen(false)
    setCompose({ step: 'form', errors: {}, previewing: false, notice: null })
  }

  function updateForm(patch: Partial<FormState>) {
    setForm((current) => ({ ...current, ...patch }))
    setCompose((current) => current.step === 'form' ? { ...current, errors: {}, notice: null } : current)
  }

  async function review(draft: BroadcastDraft) {
    const errors = validateDraft(draft)
    if (Object.keys(errors).length > 0) {
      setCompose({ step: 'form', errors, previewing: false, notice: null })
      return
    }
    const requestId = ++composeRef.current
    setCompose({ step: 'form', errors: {}, previewing: true, notice: null })
    try {
      const preview = await gateway.preview({ segment: draft.segment, days: draft.days, shopId: draft.shopId })
      if (requestId !== composeRef.current) return
      setCompose({
        step: 'review',
        input: { ...draft, requestKey: crypto.randomUUID().toLowerCase(), expectedCount: Number(preview.recipientCount) },
      })
    } catch (error) {
      if (requestId !== composeRef.current) return
      const code = error instanceof BroadcastError ? error.code : 'unavailable'
      if (code === 'unauthorized') {
        loseAccess()
        return
      }
      if (code === 'invalid') {
        setCompose({ step: 'form', errors: {}, previewing: false, notice: broadcastCopy.sendInvalid })
        return
      }
      setCompose({
        step: 'form',
        errors: code === 'not_found' ? { shopId: true } : {},
        previewing: false,
        notice: code === 'not_found' ? broadcastCopy.previewNotFound : broadcastCopy.previewError,
      })
    }
  }

  async function send(input: SendInput) {
    if (sendingRef.current) return
    sendingRef.current = true
    const requestId = ++composeRef.current
    setCompose({ step: 'sending', input })
    try {
      const result = await gateway.send(input)
      if (requestId !== composeRef.current) return
      setCompose({ step: 'sent', result })
      reload()
    } catch (error) {
      if (requestId !== composeRef.current) return
      const code = error instanceof BroadcastError ? error.code : 'unavailable'
      if (code === 'unauthorized') {
        loseAccess()
        return
      }
      if (code === 'audience_changed') {
        const { requestKey: _key, expectedCount: _count, ...draft } = input
        void _key
        void _count
        setCompose({ step: 'changed', draft })
      } else if (code === 'empty_audience') {
        setCompose({ step: 'final', message: broadcastCopy.emptyAudience })
      } else if (code === 'request_conflict') {
        setCompose({ step: 'final', message: broadcastCopy.sendConflict })
      } else if (code === 'invalid' || code === 'not_found') {
        setCompose({ step: 'form', errors: {}, previewing: false, notice: broadcastCopy.sendInvalid })
      } else {
        setCompose({
          step: 'retry',
          input,
          message: code === 'timeout' ? broadcastCopy.sendTimeout : broadcastCopy.sendUnknown,
        })
      }
    } finally {
      if (requestId === composeRef.current) sendingRef.current = false
    }
  }

  function openWithdraw(row: BroadcastRow) {
    withdrawRef.current += 1
    setWithdrawTarget(row)
    setWithdrawReason('')
    setWithdrawState('form')
  }

  async function confirmWithdraw() {
    if (withdrawTarget === null || withdrawState === 'pending') return
    const reason = withdrawReason.trim()
    // eslint-disable-next-line no-control-regex
    if (reason.length < reasonMin || reason.length > reasonMax || /[\u0000-\u001f\u007f]/.test(reason)) {
      setWithdrawState('invalid')
      return
    }
    const requestId = ++withdrawRef.current
    setWithdrawState('pending')
    try {
      const result = await gateway.withdraw(withdrawTarget.id, reason)
      if (requestId !== withdrawRef.current) return
      setWithdrawState(result.status === 'withdrawn' ? 'done' : 'already')
      reload()
    } catch (error) {
      if (requestId !== withdrawRef.current) return
      if (error instanceof BroadcastError && error.code === 'unauthorized') {
        loseAccess()
        return
      }
      setWithdrawState('failed')
    }
  }

  if (listPhase === 'accessLost') return null

  const draftErrors = compose.step === 'form' ? compose.errors : {}

  return (
    <Box component="section" aria-labelledby="broadcasts-title" sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, minWidth: 0 }}>
      <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'flex-start', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Box sx={{ minWidth: 0, flex: '1 1 320px' }}>
          <Typography id="broadcasts-title" component="h2" variant="h5" sx={{ fontWeight: 700, lineHeight: 1.4, mb: 0.5 }}>
            {broadcastCopy.title}
          </Typography>
          <Typography sx={{ lineHeight: 1.6 }}>{broadcastCopy.intro}</Typography>
        </Box>
        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}>
          <Button variant="contained" onClick={openCompose} startIcon={<AddCommentOutlinedIcon aria-hidden />}>
            {broadcastCopy.compose}
          </Button>
          <Button variant="outlined" onClick={reload} disabled={listPhase === 'loading'} startIcon={<RefreshOutlinedIcon aria-hidden />}>
            {broadcastCopy.refresh}
          </Button>
        </Box>
      </Box>

      {notice && <Alert severity="info" role="status">{notice}</Alert>}
      {snapshotAt && listPhase === 'ready' && (
        <Typography variant="body2">
          {broadcastCopy.snapshot}: <bdi>{formatServerInstant(snapshotAt)}</bdi>
        </Typography>
      )}
      {listPhase === 'loading' && <Typography role="status">{broadcastCopy.loading}</Typography>}
      {listPhase === 'error' && (
        <Alert severity="error" action={<Button color="inherit" onClick={reload}>{broadcastCopy.retry}</Button>}>
          {broadcastCopy.loadError}
        </Alert>
      )}
      {listPhase === 'ready' && rows.length === 0 && <Typography>{broadcastCopy.empty}</Typography>}
      {rows.length > 0 && (
        <Box component="ol" aria-label={broadcastCopy.listLabel} sx={{ listStyle: 'none', m: 0, p: 0, display: 'grid', gap: `${tokens.spaceSm}px` }}>
          {rows.map((row) => (
            <BroadcastCard key={row.id} row={row} onWithdraw={row.state === 'withdrawn' ? null : () => openWithdraw(row)} />
          ))}
        </Box>
      )}
      {pageFailed && <Alert severity="error">{broadcastCopy.pageError}</Alert>}
      {cursor !== null && listPhase === 'ready' && (
        <Button variant="outlined" onClick={() => void loadMore()} disabled={loadingMore} sx={{ justifySelf: 'center', minWidth: 200 }}>
          {loadingMore ? broadcastCopy.loadingMore : broadcastCopy.loadMore}
        </Button>
      )}

      <Dialog open={composeOpen} onClose={closeCompose} fullWidth maxWidth="md" aria-labelledby="broadcast-compose-title">
        <DialogTitle id="broadcast-compose-title" sx={{ lineHeight: 1.4 }}>
          {compose.step === 'review' || compose.step === 'sending' ? broadcastCopy.reviewTitle : broadcastCopy.composeTitle}
        </DialogTitle>
        <DialogContent sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, pt: '8px !important' }}>
          {compose.step === 'form' && (
            <>
              {compose.notice && <Alert severity="error">{compose.notice}</Alert>}
              <TextField
                select
                label={broadcastCopy.segmentLabel}
                value={form.segment}
                onChange={(event) => updateForm({ segment: event.target.value as BroadcastSegment })}
              >
                {broadcastSegments.map((segment) => (
                  <MenuItem key={segment} value={segment}>{segmentLabel[segment]}</MenuItem>
                ))}
              </TextField>
              {form.segment === 'expiring' && (
                <TextField
                  label={broadcastCopy.daysLabel}
                  value={form.days}
                  error={draftErrors.days === true}
                  helperText={draftErrors.days ? broadcastCopy.daysError : broadcastCopy.daysHelp}
                  onChange={(event) => updateForm({ days: event.target.value })}
                  slotProps={{ htmlInput: { inputMode: 'numeric', autoComplete: 'off' } }}
                />
              )}
              {form.segment === 'shop' && (
                <TextField
                  label={broadcastCopy.shopIdLabel}
                  value={form.shopId}
                  error={draftErrors.shopId === true}
                  helperText={draftErrors.shopId ? broadcastCopy.shopIdError : broadcastCopy.shopIdHelp}
                  onChange={(event) => updateForm({ shopId: event.target.value })}
                  slotProps={{ htmlInput: { dir: 'ltr', autoComplete: 'off', spellCheck: false } }}
                />
              )}
              <TextField
                label={broadcastCopy.titleLabel}
                value={form.title}
                error={draftErrors.title === true}
                helperText={draftErrors.title ? broadcastCopy.titleError : broadcastCopy.counter(form.title.trim().length, titleMax)}
                onChange={(event) => updateForm({ title: event.target.value })}
                slotProps={{ htmlInput: { maxLength: titleMax + 20 } }}
              />
              <TextField
                label={broadcastCopy.bodyLabel}
                value={form.body}
                multiline
                minRows={4}
                error={draftErrors.body === true}
                helperText={draftErrors.body ? broadcastCopy.bodyError : broadcastCopy.counter(form.body.trim().length, bodyMax)}
                onChange={(event) => updateForm({ body: event.target.value })}
              />
              <TextField
                label={broadcastCopy.linkLabel}
                value={form.link}
                error={draftErrors.link === true}
                helperText={
                  <>
                    {draftErrors.link ? broadcastCopy.linkError : broadcastCopy.linkHelp}{' '}
                    <bdi dir="ltr">{broadcastCopy.httpsPrefix}</bdi>
                  </>
                }
                onChange={(event) => updateForm({ link: event.target.value })}
                slotProps={{ htmlInput: { dir: 'ltr', inputMode: 'url', autoComplete: 'off' } }}
              />
              <ChoiceRow
                label={broadcastCopy.timingLabel}
                value={form.scheduled ? 'later' : 'now'}
                options={[['now', broadcastCopy.timingNow], ['later', broadcastCopy.timingLater]]}
                onChange={(value) => updateForm({ scheduled: value === 'later' })}
              />
              {form.scheduled && (
                <TextField
                  type="datetime-local"
                  label={broadcastCopy.startsAtLabel}
                  value={form.startsLocal}
                  error={draftErrors.startsAt === true}
                  helperText={draftErrors.startsAt ? broadcastCopy.startsAtError : broadcastCopy.startsAtHelp}
                  onChange={(event) => updateForm({ startsLocal: event.target.value })}
                  slotProps={{ inputLabel: { shrink: true } }}
                />
              )}
              <ChoiceRow
                label={broadcastCopy.endLabel}
                value={form.customEnd ? 'custom' : 'default'}
                options={[['default', broadcastCopy.endDefault], ['custom', broadcastCopy.endCustom]]}
                onChange={(value) => updateForm({ customEnd: value === 'custom' })}
              />
              {form.customEnd && (
                <TextField
                  type="datetime-local"
                  label={broadcastCopy.endsAtLabel}
                  value={form.endsLocal}
                  error={draftErrors.endsAt === true}
                  helperText={draftErrors.endsAt ? broadcastCopy.endsAtError : broadcastCopy.endsAtHelp}
                  onChange={(event) => updateForm({ endsLocal: event.target.value })}
                  slotProps={{ inputLabel: { shrink: true } }}
                />
              )}
              {compose.previewing && <Typography role="status">{broadcastCopy.previewing}</Typography>}
            </>
          )}
          {(compose.step === 'review' || compose.step === 'sending') && (
            <ReviewSummary input={compose.input} shopName={null} />
          )}
          {compose.step === 'sending' && <Typography role="status">{broadcastCopy.sending}</Typography>}
          {compose.step === 'sent' && (
            <Alert severity="success" role="status">
              {compose.result.status === 'replayed'
                ? broadcastCopy.replayed
                : broadcastCopy.sent(formatExactCount(compose.result.recipientCount))}
              {' '}
              {broadcastCopy.scheduledFor}: <bdi>{formatServerInstant(compose.result.startsAt)}</bdi>
            </Alert>
          )}
          {compose.step === 'retry' && <Alert severity="warning" role="alert">{compose.message}</Alert>}
          {compose.step === 'changed' && <Alert severity="warning" role="alert">{broadcastCopy.audienceChanged}</Alert>}
          {compose.step === 'final' && <Alert severity="error" role="alert">{compose.message}</Alert>}
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2, flexWrap: 'wrap', gap: 1 }}>
          {compose.step === 'form' && (
            <Button variant="contained" disabled={compose.previewing} onClick={() => void review(toDraft(form))}>
              {broadcastCopy.review}
            </Button>
          )}
          {compose.step === 'review' && (
            <>
              <Button variant="outlined" onClick={() => setCompose({ step: 'form', errors: {}, previewing: false, notice: null })}>
                {broadcastCopy.edit}
              </Button>
              <Button variant="contained" disabled={compose.input.expectedCount < 1} onClick={() => void send(compose.input)}>
                {broadcastCopy.confirmSend}
              </Button>
            </>
          )}
          {compose.step === 'sending' && (
            <Button variant="contained" disabled>{broadcastCopy.confirmSend}</Button>
          )}
          {compose.step === 'retry' && (
            <Button variant="contained" onClick={() => void send(compose.input)}>{broadcastCopy.retrySame}</Button>
          )}
          {compose.step === 'changed' && (
            <Button variant="contained" onClick={() => void review(compose.draft)}>{broadcastCopy.reviewAgain}</Button>
          )}
          <Button variant="outlined" onClick={closeCompose}>{broadcastCopy.close}</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={withdrawTarget !== null} onClose={() => setWithdrawTarget(null)} fullWidth maxWidth="sm" aria-labelledby="broadcast-withdraw-title">
        <DialogTitle id="broadcast-withdraw-title">{broadcastCopy.withdrawTitle}</DialogTitle>
        <DialogContent sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, pt: '8px !important' }}>
          {withdrawTarget && <Typography sx={{ fontWeight: 700 }}><bdi>{withdrawTarget.titleAr}</bdi></Typography>}
          {(withdrawState === 'form' || withdrawState === 'invalid' || withdrawState === 'pending') && (
            <>
              <Typography sx={{ lineHeight: 1.6 }}>{broadcastCopy.withdrawIntro}</Typography>
              <TextField
                label={broadcastCopy.withdrawReason}
                value={withdrawReason}
                disabled={withdrawState === 'pending'}
                error={withdrawState === 'invalid'}
                helperText={withdrawState === 'invalid' ? broadcastCopy.withdrawReasonError : broadcastCopy.withdrawReasonHelp}
                onChange={(event) => {
                  setWithdrawReason(event.target.value)
                  setWithdrawState('form')
                }}
                slotProps={{ htmlInput: { maxLength: reasonMax } }}
              />
            </>
          )}
          {withdrawState === 'pending' && <Typography role="status">{broadcastCopy.withdrawing}</Typography>}
          {withdrawState === 'done' && <Alert severity="success" role="status">{broadcastCopy.withdrawn}</Alert>}
          {withdrawState === 'already' && <Alert severity="info" role="status">{broadcastCopy.alreadyWithdrawn}</Alert>}
          {withdrawState === 'failed' && <Alert severity="error" role="alert">{broadcastCopy.withdrawFailed}</Alert>}
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2, flexWrap: 'wrap', gap: 1 }}>
          {(withdrawState === 'form' || withdrawState === 'invalid' || withdrawState === 'pending' || withdrawState === 'failed') && (
            <Button variant="contained" color="error" disabled={withdrawState === 'pending'} onClick={() => void confirmWithdraw()}>
              {broadcastCopy.confirmWithdraw}
            </Button>
          )}
          <Button variant="outlined" onClick={() => setWithdrawTarget(null)}>{broadcastCopy.close}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}

function ChoiceRow({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: Array<[string, string]>
  onChange: (value: string) => void
}) {
  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceSm}px` }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{label}</Typography>
      <ToggleButtonGroup
        exclusive
        aria-label={label}
        value={value}
        onChange={(_event, next: string | null) => {
          if (next !== null) onChange(next)
        }}
        sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}
      >
        {options.map(([key, text]) => (
          <ToggleButton key={key} value={key} sx={{ minHeight: `${tokens.minControlSize}px`, px: 2 }}>{text}</ToggleButton>
        ))}
      </ToggleButtonGroup>
    </Box>
  )
}

function ReviewSummary({ input, shopName }: { input: SendInput; shopName: string | null }) {
  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceSm}px` }}>
      <Box
        sx={{
          p: `${tokens.spaceMd}px`,
          borderRadius: `${tokens.cardRadius}px`,
          border: 1,
          borderColor: 'primary.main',
          display: 'grid',
          gap: 0.5,
        }}
      >
        <Typography variant="subtitle2">{broadcastCopy.recipients}</Typography>
        <Typography variant="h4" component="p" sx={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }} data-testid="broadcast-recipient-count">
          {formatExactCount(String(input.expectedCount))}
        </Typography>
        <Typography>{segmentSummary(input.segment, input.days, shopName)}</Typography>
      </Box>
      {input.expectedCount < 1 && <Alert severity="warning">{broadcastCopy.noRecipients}</Alert>}
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, m: 0 }}>
        <Field label={broadcastCopy.titleLabel} value={<bdi>{input.titleAr}</bdi>} />
        <Field label={broadcastCopy.bodyLabel} value={<Box component="span" sx={{ whiteSpace: 'pre-line' }}><bdi>{input.bodyAr}</bdi></Box>} />
        {input.linkUrl && <Field label={broadcastCopy.linkShown} value={<bdi dir="ltr">{input.linkUrl}</bdi>} />}
        <Field
          label={broadcastCopy.startsAtLabel}
          value={input.startsAt ? <bdi>{formatServerInstant(input.startsAt)}</bdi> : broadcastCopy.startsNow}
        />
        <Field
          label={broadcastCopy.endsAtLabel}
          value={input.endsAt ? <bdi>{formatServerInstant(input.endsAt)}</bdi> : broadcastCopy.defaultEnd}
        />
      </Box>
      <Typography sx={{ lineHeight: 1.6 }}>{broadcastCopy.reviewNote}</Typography>
    </Box>
  )
}

function BroadcastCard({ row, onWithdraw }: { row: BroadcastRow; onWithdraw: (() => void) | null }) {
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
        gap: `${tokens.spaceSm}px`,
        minWidth: 0,
      }}
    >
      <Box sx={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: `${tokens.spaceSm}px` }}>
        <Typography component="h3" sx={{ fontWeight: 700, lineHeight: 1.5, overflowWrap: 'anywhere' }}>
          <bdi>{row.titleAr}</bdi>
        </Typography>
        <Chip
          variant="outlined"
          color={row.state === 'active' ? 'success' : row.state === 'scheduled' ? 'primary' : 'default'}
          label={stateLabel[row.state]}
        />
      </Box>
      <Typography sx={{ lineHeight: 1.6, whiteSpace: 'pre-line', overflowWrap: 'anywhere' }}><bdi>{row.bodyAr}</bdi></Typography>
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', m: 0 }}>
        <Field label={broadcastCopy.audience} value={segmentSummary(row.segment, row.segmentDays, row.segmentShopName)} />
        <Field label={broadcastCopy.startsAtLabel} value={<bdi>{formatServerInstant(row.startsAt)}</bdi>} />
        <Field label={broadcastCopy.endsAtLabel} value={<bdi>{formatServerInstant(row.endsAt)}</bdi>} />
      </Box>
      <Box
        component="dl"
        aria-label={broadcastCopy.countsLabel}
        sx={{ display: 'flex', flexWrap: 'wrap', columnGap: `${tokens.spaceLg}px`, rowGap: `${tokens.spaceSm}px`, m: 0 }}
      >
        <CountField label={broadcastCopy.recipientCount} value={row.recipientCount} />
        <CountField label={broadcastCopy.deliveredCount} value={row.deliveredCount} />
        <CountField label={broadcastCopy.readCount} value={row.readCount} />
      </Box>
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', m: 0 }}>
        <Field
          label={broadcastCopy.createdBy}
          value={row.createdByEmail ? <bdi dir="ltr">{row.createdByEmail}</bdi> : broadcastCopy.unknownActor}
        />
        {row.linkUrl && <Field label={broadcastCopy.linkShown} value={<bdi dir="ltr">{row.linkUrl}</bdi>} />}
        {row.withdrawnAt && <Field label={broadcastCopy.withdrawnAt} value={<bdi>{formatServerInstant(row.withdrawnAt)}</bdi>} />}
        {row.withdrawReason && <Field label={broadcastCopy.withdrawReasonLabel} value={<bdi>{row.withdrawReason}</bdi>} />}
      </Box>
      {onWithdraw && (
        <Box>
          <Button variant="outlined" color="error" onClick={onWithdraw}>{broadcastCopy.withdraw}</Button>
        </Box>
      )}
    </Box>
  )
}

function CountField({ label, value }: { label: string; value: string }) {
  return (
    <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1 }}>
      <Typography component="dt" variant="subtitle2" sx={{ fontWeight: 600 }}>{label}</Typography>
      <Typography component="dd" sx={{ m: 0, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
        {formatExactCount(value)}
      </Typography>
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

import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Chip from '@mui/material/Chip'
import Dialog from '@mui/material/Dialog'
import DialogActions from '@mui/material/DialogActions'
import DialogContent from '@mui/material/DialogContent'
import DialogTitle from '@mui/material/DialogTitle'
import TextField from '@mui/material/TextField'
import Typography from '@mui/material/Typography'
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { tokens } from '../theme/tokens.ts'
import { subscriberCopy } from './copy.ts'
import {
  SubscriptionCodeError,
  type SubscriberDirectoryGateway,
  type SubscriptionSessionBinding,
} from './SubscriberDirectoryGateway.ts'
import {
  codeTtlDaysMax,
  codeTtlDaysMin,
  createIssueRequestKey,
  defaultCodeTtlDays,
  durationDaysMax,
  durationDaysMin,
  formatEstimatedExpiry,
  parseIntegerDays,
  type IssuedSubscriptionCode,
  type SubscriptionCodePage,
  type SubscriptionCodeRow,
  type SubscriptionCodeStatus,
} from './subscriptionCodes.ts'
import { formatExactCount, formatServerInstant } from './subscriptionFormat.ts'

interface Envelope {
  shopId: string
  shopName: string
  durationDays: number
  codeTtlDays: number
  requestKey: string
}

type IssuedMeta = Omit<IssuedSubscriptionCode, 'code'>

type IssuePhase =
  | { step: 'form'; duration: string; ttl: string; rangeError: boolean }
  | { step: 'review'; envelope: Envelope }
  | { step: 'pending'; envelope: Envelope }
  | { step: 'issued'; envelope: Envelope; result: IssuedMeta }
  | { step: 'replayed'; envelope: Envelope; result: IssuedMeta }
  | { step: 'timeout'; envelope: Envelope }
  | { step: 'unknown'; envelope: Envelope }
  | { step: 'unavailable'; envelope: Envelope }
  | { step: 'conflict'; envelope: Envelope }
  | { step: 'not_found'; envelope: Envelope }
  | { step: 'failed'; envelope: Envelope }

function formPhase(): IssuePhase {
  return {
    step: 'form',
    duration: '',
    ttl: String(defaultCodeTtlDays),
    rangeError: false,
  }
}

function withoutCode(result: IssuedSubscriptionCode): IssuedMeta {
  const { code: _code, ...meta } = result
  void _code
  return meta
}

export function SubscriptionCodesPanel({
  shopId,
  shopName,
  gateway,
  onAccessLost,
}: {
  shopId: string
  shopName: string
  gateway: SubscriberDirectoryGateway
  onAccessLost: () => void
}) {
  const [open, setOpen] = useState(false)
  const [phase, setPhase] = useState<IssuePhase>(formPhase)
  const [copied, setCopied] = useState(false)
  const [copyError, setCopyError] = useState<string | null>(null)
  const [copyPending, setCopyPending] = useState(false)
  const [secret, setSecret] = useState<string | null>(null)
  const secretRef = useRef<string | null>(null)
  const issueRef = useRef(0)
  const issuingRef = useRef(false)
  const copyGen = useRef(0)
  const revalidateGen = useRef(0)
  const bindGen = useRef(0)
  const mountedRef = useRef(true)
  const bindingRef = useRef<SubscriptionSessionBinding | null>(null)
  const [historyCursor, setHistoryCursor] = useState<string | null>(null)
  const [historyPrevious, setHistoryPrevious] = useState<Array<string | null>>([])
  const [historyRefresh, setHistoryRefresh] = useState(0)
  const historyKey = `${shopId}\u0000${historyCursor ?? ''}\u0000${historyRefresh}`
  const [seenHistoryKey, setSeenHistoryKey] = useState(historyKey)
  const [seenShopId, setSeenShopId] = useState(shopId)
  const [history, setHistory] = useState<SubscriptionCodePage | null>(null)
  const [historyPhase, setHistoryPhase] = useState<'loading' | 'ready' | 'error'>('loading')
  const [bindPhase, setBindPhase] = useState<'pending' | 'ready' | 'failed'>('pending')
  const [bindAttempt, setBindAttempt] = useState(0)
  const [seenGateway, setSeenGateway] = useState(gateway)
  const [seenBindAttempt, setSeenBindAttempt] = useState(bindAttempt)
  const historyRef = useRef(0)
  const dropAccessRef = useRef<() => void>(() => {})
  if (seenShopId !== shopId) {
    setSeenShopId(shopId)
    setSecret(null)
    setCopied(false)
    setCopyError(null)
    setCopyPending(false)
    setOpen(false)
    setPhase(formPhase())
    setBindPhase('pending')
  }
  if (seenGateway !== gateway) {
    setSeenGateway(gateway)
    setBindPhase('pending')
  }
  if (seenBindAttempt !== bindAttempt) {
    setSeenBindAttempt(bindAttempt)
    setBindPhase('pending')
  }
  if (seenHistoryKey !== historyKey) {
    setSeenHistoryKey(historyKey)
    setHistoryPhase('loading')
    setHistory(null)
  }

  function storeSecret(next: string | null) {
    secretRef.current = next
    setSecret(next)
  }

  function purgeSecret() {
    storeSecret(null)
    setCopied(false)
    setCopyError(null)
    setCopyPending(false)
  }

  function closeIssue() {
    issueRef.current += 1
    copyGen.current += 1
    purgeSecret()
    setOpen(false)
    setPhase(formPhase())
  }

  function lostAccess() {
    dropAccessRef.current()
  }

  useLayoutEffect(() => {
    issueRef.current += 1
    copyGen.current += 1
    revalidateGen.current += 1
    issuingRef.current = false
    secretRef.current = null
  }, [shopId])

  useLayoutEffect(() => {
    dropAccessRef.current = () => {
      issueRef.current += 1
      copyGen.current += 1
      revalidateGen.current += 1
      historyRef.current += 1
      secretRef.current = null
      setSecret(null)
      setCopied(false)
      setCopyError(null)
      setCopyPending(false)
      setOpen(false)
      setHistory(null)
      const current = bindingRef.current
      bindingRef.current = null
      if (current) gateway.releaseBoundSession(current)
      onAccessLost()
    }
  }, [gateway, onAccessLost])

  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      issueRef.current += 1
      copyGen.current += 1
      revalidateGen.current += 1
      historyRef.current += 1
      issuingRef.current = false
      secretRef.current = null
    }
  }, [])

  useEffect(() => {
    const generation = ++bindGen.current
    let unsubscribe = () => {}
    let held: SubscriptionSessionBinding | null = null
    void gateway.bindSelectedShopSession().then(
      (next) => {
        if (generation !== bindGen.current || !mountedRef.current) {
          gateway.releaseBoundSession(next)
          return
        }
        held = next
        bindingRef.current = next
        setBindPhase('ready')
        unsubscribe = gateway.watchBoundSession(next, () => {
          if (generation !== bindGen.current || !mountedRef.current) return
          dropAccessRef.current()
        })
      },
      (error: unknown) => {
        if (generation !== bindGen.current || !mountedRef.current) return
        if (error instanceof SubscriptionCodeError && error.code === 'access_lost') {
          dropAccessRef.current()
          return
        }
        setBindPhase('failed')
      },
    )
    return () => {
      bindGen.current += 1
      issuingRef.current = false
      unsubscribe()
      const current = held ?? bindingRef.current
      bindingRef.current = null
      if (current) gateway.releaseBoundSession(current)
    }
  }, [gateway, shopId, bindAttempt])

  useEffect(() => {
    function onPageHide() {
      copyGen.current += 1
      issueRef.current += 1
      issuingRef.current = false
      purgeSecret()
      setOpen(false)
      setPhase(formPhase())
    }
    async function revalidate() {
      const generation = ++revalidateGen.current
      const current = bindingRef.current
      if (current === null) return
      try {
        await gateway.assertBoundSession(current)
      } catch (error: unknown) {
        if (generation !== revalidateGen.current || !mountedRef.current) return
        if (error instanceof SubscriptionCodeError && error.code === 'access_lost') {
          dropAccessRef.current()
        }
      }
    }
    function onVisible() {
      if (document.visibilityState === 'visible') void revalidate()
    }
    function onFocus() {
      void revalidate()
    }
    window.addEventListener('pagehide', onPageHide)
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      revalidateGen.current += 1
      window.removeEventListener('pagehide', onPageHide)
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [gateway])

  useEffect(() => {
    const requestId = ++historyRef.current
    const requestShop = shopId
    const requestCursor = historyCursor
    void gateway.listSubscriptionCodes(requestShop, requestCursor).then(
      (page) => {
        if (requestId !== historyRef.current || !mountedRef.current) return
        if (page.shopId !== requestShop) return
        setHistory(page)
        setHistoryPhase('ready')
      },
      (error: unknown) => {
        if (requestId !== historyRef.current || !mountedRef.current) return
        if (error instanceof SubscriptionCodeError && error.code === 'access_lost') {
          dropAccessRef.current()
          return
        }
        if (error instanceof SubscriptionCodeError && error.code === 'stale_cursor' && requestCursor !== null) {
          setHistoryCursor(null)
          setHistoryPrevious([])
          return
        }
        setHistoryPhase('error')
      },
    )
    return () => {
      historyRef.current += 1
    }
  }, [gateway, shopId, historyCursor, historyRefresh])

  async function submitIssue(envelope: Envelope) {
    if (issuingRef.current) return
    const currentBinding = bindingRef.current
    if (currentBinding === null) return
    issuingRef.current = true
    const requestId = ++issueRef.current
    setPhase({ step: 'pending', envelope })
    try {
      await gateway.assertBoundSession(currentBinding)
      if (requestId !== issueRef.current || !mountedRef.current) return
      if (bindingRef.current?.id !== currentBinding.id) return
      if (envelope.shopId !== shopId) return
      const result = await gateway.issueSubscriptionCode({
        shopId: envelope.shopId,
        durationDays: envelope.durationDays,
        codeTtlDays: envelope.codeTtlDays,
        requestKey: envelope.requestKey,
      }, currentBinding)
      if (requestId !== issueRef.current || !mountedRef.current) return
      if (bindingRef.current?.id !== currentBinding.id) return
      if (envelope.shopId !== shopId) return
      if (result.status === 'issued' && result.code) {
        storeSecret(result.code)
        setPhase({ step: 'issued', envelope, result: withoutCode(result) })
      } else {
        storeSecret(null)
        setPhase({ step: 'replayed', envelope, result: withoutCode(result) })
      }
      setHistoryCursor(null)
      setHistoryPrevious([])
      setHistoryRefresh((value) => value + 1)
    } catch (error: unknown) {
      if (requestId !== issueRef.current || !mountedRef.current) return
      storeSecret(null)
      if (error instanceof SubscriptionCodeError && error.code === 'access_lost') {
        lostAccess()
        return
      }
      if (error instanceof SubscriptionCodeError && error.code === 'timeout') {
        setPhase({ step: 'timeout', envelope })
        return
      }
      if (error instanceof SubscriptionCodeError && error.code === 'request_conflict') {
        setPhase({ step: 'conflict', envelope })
        return
      }
      if (error instanceof SubscriptionCodeError && error.code === 'not_found') {
        setPhase({ step: 'not_found', envelope })
        return
      }
      if (error instanceof SubscriptionCodeError && error.code === 'unavailable') {
        setPhase({ step: 'unavailable', envelope })
        return
      }
      setPhase({ step: 'unknown', envelope })
    } finally {
      if (requestId === issueRef.current) issuingRef.current = false
    }
  }

  function startReview() {
    if (phase.step !== 'form') return
    try {
      const durationDays = parseIntegerDays(phase.duration, durationDaysMin, durationDaysMax)
      const codeTtlDays = parseIntegerDays(phase.ttl, codeTtlDaysMin, codeTtlDaysMax)
      setPhase({
        step: 'review',
        envelope: {
          shopId,
          shopName,
          durationDays,
          codeTtlDays,
          requestKey: createIssueRequestKey(),
        },
      })
    } catch {
      setPhase({ ...phase, rangeError: true })
    }
  }

  async function copyCode() {
    const actionId = ++copyGen.current
    const code = secretRef.current
    const currentBinding = bindingRef.current
    if (code === null || currentBinding === null || phase.step !== 'issued') return
    setCopyPending(true)
    try {
      try {
        await gateway.authorizeCopy(currentBinding, shopId)
      } catch (error: unknown) {
        if (actionId !== copyGen.current || !mountedRef.current) return
        purgeSecret()
        if (error instanceof SubscriptionCodeError && error.code === 'access_lost') {
          setCopyError(subscriberCopy.copyBlocked)
          lostAccess()
          return
        }
        setCopyError(subscriberCopy.copyFailed)
        return
      }
      if (actionId !== copyGen.current || !mountedRef.current) return
      if (secretRef.current !== code) return
      if (bindingRef.current?.id !== currentBinding.id) return
      try {
        await navigator.clipboard.writeText(code)
      } catch {
        if (actionId !== copyGen.current || !mountedRef.current) return
        setCopyError(subscriberCopy.copyFailed)
        return
      }
      if (actionId !== copyGen.current || !mountedRef.current) return
      if (secretRef.current !== code) return
      if (bindingRef.current?.id !== currentBinding.id) return
      setCopied(true)
      setCopyError(null)
    } finally {
      if (actionId === copyGen.current) setCopyPending(false)
    }
  }

  const busy = phase.step === 'pending'
  const bound = bindPhase === 'ready'
  const canRetrySame = phase.step === 'timeout' || phase.step === 'unknown' || phase.step === 'unavailable'

  return (
    <Box sx={{ display: 'grid', gap: `${tokens.spaceMd}px`, minWidth: 0 }}>
      {bindPhase === 'pending' && (
        <Typography role="status">{subscriberCopy.bindPending}</Typography>
      )}
      {bindPhase === 'failed' && (
        <>
          <Typography role="alert">{subscriberCopy.bindFailed}</Typography>
          <Button
            variant="contained"
            onClick={() => {
              setBindPhase('pending')
              setBindAttempt((value) => value + 1)
            }}
          >
            {subscriberCopy.bindRetry}
          </Button>
        </>
      )}
      <Button variant="contained" disabled={!bound} onClick={() => setOpen(true)}>
        {subscriberCopy.issueAction}
      </Button>

      <Box sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, minWidth: 0 }}>
        <Typography component="h4" variant="subtitle1" sx={{ fontWeight: 700 }}>
          {subscriberCopy.historyTitle}
        </Typography>
        <Typography sx={{ lineHeight: 1.6 }}>{subscriberCopy.historyIntro}</Typography>
        {historyPhase === 'loading' && (
          <Typography role="status">{subscriberCopy.historyLoading}</Typography>
        )}
        {historyPhase === 'error' && (
          <>
            <Typography role="alert">{subscriberCopy.historyError}</Typography>
            <Button
              variant="contained"
              onClick={() => {
                setHistoryCursor(null)
                setHistoryPrevious([])
                setHistoryRefresh((value) => value + 1)
              }}
            >
              {subscriberCopy.retry}
            </Button>
          </>
        )}
        {historyPhase === 'ready' && history && (
          <>
            <Typography>
              {subscriberCopy.historyCount}:{' '}
              <Box component="span" dir="ltr" sx={{ fontVariantNumeric: 'tabular-nums' }}>
                {formatExactCount(history.rowCount)}
              </Box>
            </Typography>
            {history.rows.length === 0 ? (
              <Typography>{subscriberCopy.historyEmpty}</Typography>
            ) : (
              <Box component="ul" sx={{ listStyle: 'none', p: 0, m: 0, display: 'grid', gap: `${tokens.spaceSm}px` }}>
                {history.rows.map((row) => (
                  <HistoryCard key={row.id} row={row} />
                ))}
              </Box>
            )}
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: `${tokens.spaceSm}px` }}>
              <Button
                variant="outlined"
                disabled={historyPrevious.length === 0}
                onClick={() => {
                  const previous = [...historyPrevious]
                  const cursor = previous.pop() ?? null
                  setHistoryPrevious(previous)
                  setHistoryCursor(cursor)
                }}
              >
                {subscriberCopy.previousPage}
              </Button>
              <Button
                variant="outlined"
                disabled={history.nextCursor === null}
                onClick={() => {
                  if (history.nextCursor === null) return
                  setHistoryPrevious((current) => [...current, historyCursor])
                  setHistoryCursor(history.nextCursor)
                }}
              >
                {subscriberCopy.nextPage}
              </Button>
            </Box>
          </>
        )}
      </Box>

      <Dialog
        open={open}
        onClose={closeIssue}
        fullWidth
        maxWidth="sm"
        aria-labelledby="subscription-issue-title"
      >
        <DialogTitle id="subscription-issue-title" sx={{ lineHeight: 1.4 }}>
          {phase.step === 'review' || phase.step === 'pending'
            ? subscriberCopy.reviewTitle
            : phase.step === 'issued'
              ? subscriberCopy.issuedTitle
              : phase.step === 'replayed'
                ? subscriberCopy.replayTitle
                : subscriberCopy.issueTitle}
        </DialogTitle>
        <DialogContent
          role="region"
          aria-label={subscriberCopy.issueTitle}
          tabIndex={0}
          sx={{
            display: 'grid',
            gap: `${tokens.spaceMd}px`,
            '&:focus-visible': { outline: '2px solid', outlineColor: 'primary.main', outlineOffset: -4 },
          }}
        >
          {phase.step === 'form' && (
            <>
              <TextField
                label={subscriberCopy.durationLabel}
                helperText={subscriberCopy.durationHelp}
                value={phase.duration}
                onChange={(event) => setPhase({ ...phase, duration: event.target.value, rangeError: false })}
                slotProps={{ htmlInput: { inputMode: 'numeric', autoComplete: 'off' } }}
                error={phase.rangeError}
              />
              <TextField
                label={subscriberCopy.ttlLabel}
                helperText={subscriberCopy.ttlHelp}
                value={phase.ttl}
                onChange={(event) => setPhase({ ...phase, ttl: event.target.value, rangeError: false })}
                slotProps={{ htmlInput: { inputMode: 'numeric', autoComplete: 'off' } }}
                error={phase.rangeError}
              />
              {phase.rangeError && (
                <Typography role="alert">{subscriberCopy.rangeError}</Typography>
              )}
            </>
          )}
          {(phase.step === 'review' || phase.step === 'pending') && (
            <ReviewFields
              shopName={phase.envelope.shopName}
              durationDays={phase.envelope.durationDays}
              ttlDays={phase.envelope.codeTtlDays}
            />
          )}
          {phase.step === 'pending' && (
            <Typography role="status">{subscriberCopy.issuing}</Typography>
          )}
          {phase.step === 'issued' && secret && (
            <>
              <Typography>{subscriberCopy.issuedOnce}</Typography>
              <Typography
                dir="ltr"
                sx={{
                  fontFamily: 'ui-monospace, Consolas, monospace',
                  fontVariantNumeric: 'tabular-nums',
                  overflowWrap: 'anywhere',
                  letterSpacing: '0.08em',
                }}
              >
                {secret}
              </Typography>
              <Typography>
                {subscriberCopy.authoritativeExpiry}: <TimeValue value={phase.result.codeExpiresAt} />
              </Typography>
              {copied && <Typography role="status">{subscriberCopy.copied}</Typography>}
              {copyError && <Typography role="alert">{copyError}</Typography>}
            </>
          )}
          {phase.step === 'issued' && !secret && copyError && (
            <Typography role="alert">{copyError}</Typography>
          )}
          {phase.step === 'replayed' && (
            <>
              <Typography>{subscriberCopy.replayBody}</Typography>
              <Typography>
                {subscriberCopy.authoritativeExpiry}: <TimeValue value={phase.result.codeExpiresAt} />
              </Typography>
            </>
          )}
          {phase.step === 'timeout' && (
            <Typography role="alert">{subscriberCopy.timeoutBody}</Typography>
          )}
          {phase.step === 'unknown' && (
            <Typography role="alert">{subscriberCopy.issueUnknown}</Typography>
          )}
          {phase.step === 'unavailable' && (
            <Typography role="alert">{subscriberCopy.issueUnavailable}</Typography>
          )}
          {phase.step === 'conflict' && (
            <Typography role="alert">{subscriberCopy.issueConflict}</Typography>
          )}
          {phase.step === 'not_found' && (
            <Typography role="alert">{subscriberCopy.issueNotFound}</Typography>
          )}
          {phase.step === 'failed' && (
            <Typography role="alert">{subscriberCopy.issueError}</Typography>
          )}
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2, flexWrap: 'wrap', gap: 1 }}>
          {phase.step === 'form' && (
            <Button variant="contained" disabled={!bound} onClick={startReview}>
              {subscriberCopy.reviewTitle}
            </Button>
          )}
          {phase.step === 'review' && (
            <>
              <Button
                variant="outlined"
                onClick={() => setPhase({
                  step: 'form',
                  duration: String(phase.envelope.durationDays),
                  ttl: String(phase.envelope.codeTtlDays),
                  rangeError: false,
                })}
              >
                {subscriberCopy.backToForm}
              </Button>
              <Button
                variant="contained"
                disabled={busy || !bound}
                onClick={() => void submitIssue(phase.envelope)}
              >
                {subscriberCopy.confirmIssue}
              </Button>
            </>
          )}
          {phase.step === 'issued' && secret && (
            <Button
              variant="contained"
              disabled={copyPending}
              onClick={() => void copyCode()}
            >
              {subscriberCopy.copyCode}
            </Button>
          )}
          {canRetrySame && (
            <Button
              variant="contained"
              disabled={!bound}
              onClick={() => void submitIssue(phase.envelope)}
            >
              {subscriberCopy.retrySame}
            </Button>
          )}
          <Button variant="outlined" onClick={closeIssue}>
            {subscriberCopy.close}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}

function ReviewFields({
  shopName,
  durationDays,
  ttlDays,
}: {
  shopName: string
  durationDays: number
  ttlDays: number
}) {
  return (
    <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, m: 0 }}>
      <Field label={subscriberCopy.reviewShop} value={shopName} />
      <Field label={subscriberCopy.reviewDuration} value={subscriberCopy.daysValue(durationDays)} />
      <Field label={subscriberCopy.reviewTtl} value={subscriberCopy.daysValue(ttlDays)} />
      <Field label={subscriberCopy.estimatedExpiry} value={formatEstimatedExpiry(ttlDays)} />
      <Typography sx={{ lineHeight: 1.6 }}>{subscriberCopy.estimatedNote}</Typography>
      <Typography sx={{ lineHeight: 1.6 }}>{subscriberCopy.reviewEffect}</Typography>
    </Box>
  )
}

function HistoryCard({ row }: { row: SubscriptionCodeRow }) {
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
      <Chip color={statusColor(row.codeStatus)} variant="outlined" label={statusLabel(row.codeStatus)} />
      <Box component="dl" sx={{ display: 'grid', gap: `${tokens.spaceSm}px`, m: 0 }}>
        <Field label={subscriberCopy.columnIssuedAt} value={<TimeValue value={row.issuedAt} />} />
        <Field label={subscriberCopy.columnDuration} value={<Box component="span" dir="ltr">{row.durationDays}</Box>} />
        <Field label={subscriberCopy.columnTtl} value={<Box component="span" dir="ltr">{row.codeTtlDays}</Box>} />
        <Field label={subscriberCopy.columnCodeExpiry} value={<TimeValue value={row.codeExpiresAt} />} />
        <Field
          label={subscriberCopy.columnIssuedVia}
          value={row.issuedVia === 'platform_admin' ? subscriberCopy.issuedViaAdmin : subscriberCopy.issuedViaService}
        />
        <Field
          label={subscriberCopy.columnRedeemedAt}
          value={row.redeemedAt ? <TimeValue value={row.redeemedAt} /> : subscriberCopy.missingDate}
        />
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

function TimeValue({ value }: { value: string }) {
  return (
    <Typography component="span" sx={{ fontVariantNumeric: 'tabular-nums', overflowWrap: 'anywhere' }}>
      {formatServerInstant(value)}
    </Typography>
  )
}

function statusLabel(status: SubscriptionCodeStatus): string {
  if (status === 'unused') return subscriberCopy.statusUnused
  if (status === 'redeemed') return subscriberCopy.statusRedeemed
  return subscriberCopy.statusExpired
}

function statusColor(status: SubscriptionCodeStatus): 'success' | 'primary' | 'default' {
  if (status === 'unused') return 'primary'
  if (status === 'redeemed') return 'success'
  return 'default'
}

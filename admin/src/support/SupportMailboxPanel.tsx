import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import ButtonGroup from '@mui/material/ButtonGroup'
import Chip from '@mui/material/Chip'
import CircularProgress from '@mui/material/CircularProgress'
import Stack from '@mui/material/Stack'
import TextField from '@mui/material/TextField'
import Typography from '@mui/material/Typography'
import { useCallback, useEffect, useRef, useState } from 'react'
import { tokens } from '../theme/tokens.ts'
import {
  SupportError,
  isExactShopIdentifier,
  normalizeSupportReply,
  type SupportGateway,
  type SupportInquiryAdminRow,
  type SupportStatusFilter,
  type SupportTriageTarget,
} from './SupportGateway.ts'
import {
  supportCategoryLabel,
  supportCopy,
  supportFilterLabel,
  supportRowDate,
  supportStatusLabel,
} from './copy.ts'

const filterOrder: SupportStatusFilter[] = ['all', 'new', 'in_progress', 'answered', 'closed']

export function SupportMailboxPanel({
  gateway,
  onAccessLost,
}: {
  gateway: SupportGateway
  onAccessLost?: () => void
}) {
  const [statusFilter, setStatusFilter] = useState<SupportStatusFilter>('all')
  const [searchDraft, setSearchDraft] = useState('')
  const [appliedSearch, setAppliedSearch] = useState('')
  const [rows, setRows] = useState<SupportInquiryAdminRow[] | null>(null)
  const [cursor, setCursor] = useState<{ at: string; id: string } | null>(null)
  const [snapshotAt, setSnapshotAt] = useState<string | null>(null)
  const [listFailed, setListFailed] = useState(false)
  const [pageFailed, setPageFailed] = useState(false)
  const [staleNotice, setStaleNotice] = useState(false)
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [replyDraft, setReplyDraft] = useState('')
  const [triageBusyId, setTriageBusyId] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<{ kind: 'success' | 'error'; text: string } | null>(null)
  const requestGen = useRef(0)
  const pendingWrite = useRef<{
    id: string
    to: SupportTriageTarget
    replyAr: string | null
    key: string
  } | null>(null)

  /** Returns true when the error was fully handled (access loss or stale
   * notice) and the caller must not show its own error state. */
  const applyError = useCallback(
    (error: unknown): boolean => {
      if (error instanceof SupportError && error.code === 'access_lost') {
        onAccessLost?.()
        return true
      }
      if (error instanceof SupportError && error.code === 'stale_cursor') {
        setStaleNotice(true)
        return true
      }
      return false
    },
    [onAccessLost],
  )

  const load = useCallback(async () => {
    const gen = ++requestGen.current
    setLoading(true)
    setListFailed(false)
    setPageFailed(false)
    setStaleNotice(false)
    try {
      const page = await gateway.list({
        status: statusFilter,
        search: appliedSearch,
        cursorAt: null,
        cursorId: null,
      })
      if (gen !== requestGen.current) return
      setRows(page.inquiries)
      setCursor(
        page.nextCursorAt !== null && page.nextCursorId !== null
          ? { at: page.nextCursorAt, id: page.nextCursorId }
          : null,
      )
      setSnapshotAt(page.snapshotAt)
    } catch (error) {
      if (gen !== requestGen.current) return
      if (applyError(error)) return
      setListFailed(true)
    } finally {
      if (gen === requestGen.current) setLoading(false)
    }
  }, [gateway, statusFilter, appliedSearch, applyError])

  useEffect(() => {
    void load()
  }, [load])

  const changeFilter = (next: SupportStatusFilter) => {
    if (next === statusFilter) return
    setStatusFilter(next)
    setRows(null)
    setCursor(null)
    setFeedback(null)
    setEditingId(null)
    setReplyDraft('')
  }

  const applySearch = () => {
    const next = searchDraft.trim()
    if (next === appliedSearch) {
      void load()
      return
    }
    setAppliedSearch(next)
    setRows(null)
    setCursor(null)
    setEditingId(null)
    setReplyDraft('')
  }

  const loadMore = async () => {
    if (cursor === null || loadingMore) return
    const gen = requestGen.current
    setLoadingMore(true)
    setPageFailed(false)
    setStaleNotice(false)
    try {
      const page = await gateway.list({
        status: statusFilter,
        search: appliedSearch,
        cursorAt: cursor.at,
        cursorId: cursor.id,
      })
      if (gen !== requestGen.current) return
      setRows((current) => [...(current ?? []), ...page.inquiries])
      setCursor(
        page.nextCursorAt !== null && page.nextCursorId !== null
          ? { at: page.nextCursorAt, id: page.nextCursorId }
          : null,
      )
      setSnapshotAt(page.snapshotAt)
    } catch (error) {
      if (gen !== requestGen.current) return
      if (applyError(error)) return
      setPageFailed(true)
    } finally {
      if (gen === requestGen.current) setLoadingMore(false)
    }
  }

  const runTriage = async (
    row: SupportInquiryAdminRow,
    to: SupportTriageTarget,
    replyAr: string | null,
  ) => {
    if (triageBusyId !== null) return
    const previous = pendingWrite.current
    // A minted key only fits the exact action it was created for; any change
    // to the action (or the reply draft) starts a fresh key, while an
    // unchanged retry of a failed request reuses it.
    const reuseKey =
      previous !== null
      && previous.id === row.id
      && previous.to === to
      && previous.replyAr === replyAr
    const key = reuseKey && previous !== null ? previous.key : crypto.randomUUID()
    pendingWrite.current = { id: row.id, to, replyAr, key }
    setTriageBusyId(row.id)
    setFeedback(null)
    try {
      const result = await gateway.updateInquiryStatus({
        inquiryId: row.id,
        to,
        replyAr,
        idempotencyKey: key,
      })
      pendingWrite.current = null
      setFeedback({
        kind: 'success',
        text: result.saved ? supportCopy.triageSaved : supportCopy.triageReplayed,
      })
      setEditingId(null)
      setReplyDraft('')
      await load()
    } catch (error) {
      const code = error instanceof SupportError ? error.code : 'unavailable'
      if (code === 'access_lost') {
        pendingWrite.current = null
        onAccessLost?.()
        return
      }
      if (code === 'unavailable') {
        // The server may still commit this request; the same key and payload
        // must be reused on the next identical attempt.
        setFeedback({ kind: 'error', text: supportCopy.triageError })
        return
      }
      pendingWrite.current = null
      if (code === 'invalid_transition') {
        setFeedback({ kind: 'error', text: supportCopy.invalidTransition })
        setStaleNotice(true)
      } else if (code === 'not_found') {
        setFeedback({ kind: 'error', text: supportCopy.notFound })
        setStaleNotice(true)
      } else if (code === 'invalid') {
        setFeedback({ kind: 'error', text: supportCopy.invalidReply })
      } else {
        setFeedback({ kind: 'error', text: supportCopy.triageError })
      }
    } finally {
      setTriageBusyId(null)
    }
  }

  const submitAnswer = (row: SupportInquiryAdminRow) => {
    const reply = normalizeSupportReply(replyDraft)
    if (reply === null) {
      setFeedback({ kind: 'error', text: supportCopy.invalidReply })
      return
    }
    void runTriage(row, 'answered', reply)
  }

  const closeInquiry = (row: SupportInquiryAdminRow) => {
    void runTriage(row, 'closed', null)
  }

  if (loading && rows === null) {
    return (
      <Box sx={{ display: 'grid', placeItems: 'center', py: 6 }} data-testid="support-loading">
        <CircularProgress aria-label={supportCopy.loadingMore} />
      </Box>
    )
  }

  if (listFailed && rows === null) {
    return (
      <Alert
        severity="error"
        action={<Button onClick={() => void load()}>{supportCopy.retry}</Button>}
      >
        {supportCopy.loadError}
      </Alert>
    )
  }

  return (
    <Stack spacing={2} sx={{ minWidth: 0 }}>
      <Typography component="h2" variant="h5" sx={{ fontWeight: 700 }}>
        {supportCopy.title}
      </Typography>
      <Typography sx={{ lineHeight: 1.6 }}>{supportCopy.intro}</Typography>
      <Typography variant="body2" color="text.secondary">
        {supportCopy.limitNote}
      </Typography>

      {feedback && (
        <Alert
          severity={feedback.kind}
          role="status"
          data-testid="support-feedback"
          onClose={feedback.kind === 'success' ? () => setFeedback(null) : undefined}
        >
          {feedback.text}
        </Alert>
      )}
      {staleNotice && (
        <Alert severity="warning" role="status" data-testid="support-stale">
          {supportCopy.staleList}
        </Alert>
      )}

      <Box
        component="section"
        aria-label={supportCopy.statusFilter}
        sx={{
          p: 2,
          borderRadius: '16px',
          border: 1,
          borderColor: 'divider',
          bgcolor: 'background.paper',
          display: 'grid',
          gap: `${tokens.spaceMd}px`,
        }}
      >
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={1}
          sx={{ alignItems: { sm: 'center' } }}
        >
          <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
            {supportCopy.statusFilter}
          </Typography>
          <ButtonGroup variant="outlined" size="small" aria-label={supportCopy.statusFilter}>
            {filterOrder.map((value) => (
              <Button
                key={value}
                data-testid={`support-filter-${value}`}
                variant={statusFilter === value ? 'contained' : 'outlined'}
                onClick={() => changeFilter(value)}
                disabled={loading || loadingMore}
              >
                {supportFilterLabel[value]}
              </Button>
            ))}
          </ButtonGroup>
        </Stack>
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={1}
          sx={{ alignItems: { sm: 'center' } }}
        >
          <TextField
            data-testid="support-search"
            label={supportCopy.searchLabel}
            value={searchDraft}
            onChange={(e) => setSearchDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') applySearch()
            }}
            slotProps={{ htmlInput: { dir: 'ltr' } }}
            helperText={isExactShopIdentifier(searchDraft) ? undefined : supportCopy.invalidSearch}
            sx={{ minWidth: { sm: 320 }, maxWidth: { sm: 420 } }}
            size="small"
          />
          <Button variant="outlined" onClick={applySearch} disabled={loading || loadingMore}>
            {supportCopy.searchApply}
          </Button>
          <Button variant="outlined" onClick={() => void load()} disabled={loading || loadingMore}>
            {supportCopy.refresh}
          </Button>
        </Stack>
      </Box>

      {snapshotAt && (
        <Typography variant="body2" color="text.secondary" data-testid="support-snapshot">
          {supportCopy.snapshot}:{' '}
          <span dir="ltr">{supportRowDate(snapshotAt, 'UTC')}</span>
        </Typography>
      )}

      {rows !== null && rows.length === 0 ? (
        <Alert severity="info" data-testid="support-empty">
          {supportCopy.empty}
        </Alert>
      ) : null}

      <Stack spacing={2}>
        {(rows ?? []).map((row) => (
          <Box
            key={row.id}
            data-testid={`support-row-${row.id}`}
            sx={{
              p: 2,
              borderRadius: '16px',
              border: 1,
              borderColor: 'divider',
              bgcolor: 'background.paper',
              display: 'grid',
              gap: `${tokens.spaceSm}px`,
            }}
          >
            <Stack
              direction="row"
              spacing={1}
              sx={{ alignItems: 'center', flexWrap: 'wrap' }}
            >
              <Typography component="h3" variant="subtitle1" sx={{ fontWeight: 700 }}>
                {row.shopName}
              </Typography>
              <Chip size="small" label={supportStatusLabel[row.status]} data-testid={`support-status-${row.status}`} />
              {row.category && (
                <Chip
                  size="small"
                  variant="outlined"
                  label={supportCategoryLabel[row.category]}
                />
              )}
            </Stack>
            <Typography variant="body2" color="text.secondary">
              {supportCopy.shopLabel}:{' '}
              <span dir="ltr" data-testid={`support-shop-id-${row.id}`}>
                {row.shopId}
              </span>
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {supportCopy.registered}:{' '}
              <span dir="ltr">{supportRowDate(row.shopCreatedAt, row.shopTimeZone)}</span>
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {supportRowDate(row.createdAt, row.shopTimeZone)}
            </Typography>
            <Typography sx={{ lineHeight: 1.7, whiteSpace: 'pre-wrap' }} data-testid="support-body">
              {row.bodyAr}
            </Typography>
            {row.replyAr ? (
              <Box
                sx={{
                  p: 1.5,
                  borderRadius: '12px',
                  bgcolor: 'action.selected',
                }}
                data-testid="support-reply"
              >
                <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
                  {supportCopy.replyLabel}
                </Typography>
                <Typography sx={{ lineHeight: 1.7, whiteSpace: 'pre-wrap' }}>{row.replyAr}</Typography>
              </Box>
            ) : row.status === 'answered' ? null : (
              <Typography variant="body2" color="text.secondary">
                {supportCopy.noReply}
              </Typography>
            )}

            {triageBusyId === row.id && (
              <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                <CircularProgress size={16} />
                <Typography variant="body2">{supportCopy.triageSaving}</Typography>
              </Stack>
            )}

            {row.status === 'new' && triageBusyId !== row.id && (
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                <Button
                  variant="contained"
                  data-testid={`support-triage-start-${row.id}`}
                  onClick={() => void runTriage(row, 'in_progress', null)}
                  disabled={triageBusyId !== null}
                >
                  {supportCopy.startTriage}
                </Button>
              </Stack>
            )}

            {row.status === 'in_progress' && (
              <Stack spacing={1}>
                <TextField
                  data-testid="support-reply-field"
                  label={supportCopy.replyField}
                  value={editingId === row.id ? replyDraft : ''}
                  onChange={(e) => {
                    setEditingId(row.id)
                    setReplyDraft(e.target.value)
                  }}
                  multiline
                  minRows={3}
                  helperText={
                    editingId === row.id
                      ? Array.from(replyDraft.trim()).length > 1000
                        ? supportCopy.invalidReply
                        : undefined
                      : undefined
                  }
                  error={
                    editingId === row.id
                      && Array.from(replyDraft.trim()).length > 1000
                  }
                  disabled={triageBusyId !== null}
                />
                <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                  <Button
                    variant="contained"
                    data-testid={`support-triage-answer-${row.id}`}
                    onClick={() => submitAnswer(row)}
                    disabled={triageBusyId !== null || editingId !== row.id}
                  >
                    {supportCopy.sendReply}
                  </Button>
                </Stack>
              </Stack>
            )}

            {row.status === 'answered' && triageBusyId !== row.id && (
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
                <Button
                  variant="outlined"
                  data-testid={`support-triage-close-${row.id}`}
                  onClick={() => closeInquiry(row)}
                  disabled={triageBusyId !== null}
                >
                  {supportCopy.closeInquiry}
                </Button>
              </Stack>
            )}
          </Box>
        ))}
      </Stack>

      {pageFailed && (
        <Alert
          severity="error"
          action={<Button onClick={() => void loadMore()}>{supportCopy.retry}</Button>}
        >
          {supportCopy.listFailed}
        </Alert>
      )}

      {loadingMore && (
        <Typography variant="body2" data-testid="support-loading-more">
          {supportCopy.loadingMore}
        </Typography>
      )}

      {cursor !== null && !loadingMore && !pageFailed && (
        <Button
          variant="outlined"
          data-testid="support-load-more"
          onClick={() => void loadMore()}
        >
          {supportCopy.loadMore}
        </Button>
      )}
    </Stack>
  )
}

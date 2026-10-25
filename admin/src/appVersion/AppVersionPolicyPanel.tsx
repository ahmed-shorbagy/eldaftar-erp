import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Stack from '@mui/material/Stack'
import TextField from '@mui/material/TextField'
import Typography from '@mui/material/Typography'
import { useCallback, useEffect, useRef, useState } from 'react'
import { tokens } from '../theme/tokens.ts'
import {
  AppVersionError,
  type AppVersionGateway,
  type AppVersionPlatform,
  type AppVersionPolicyRow,
} from './AppVersionGateway.ts'
import { appVersionCopy } from './copy.ts'

const platforms: AppVersionPlatform[] = ['android', 'ios', 'windows']

const labels: Record<AppVersionPlatform, string> = {
  android: appVersionCopy.android,
  ios: appVersionCopy.ios,
  windows: appVersionCopy.windows,
}

type Draft = {
  minVersion: string
  messageAr: string
  updateUrl: string
}

function draftFromRow(row?: AppVersionPolicyRow): Draft {
  return {
    minVersion: row?.minVersion ?? '',
    messageAr: row?.messageAr ?? '',
    updateUrl: row?.updateUrl ?? '',
  }
}

export function AppVersionPolicyPanel({
  gateway,
  onAccessLost,
}: {
  gateway: AppVersionGateway
  onAccessLost?: () => void
}) {
  const [rows, setRows] = useState<AppVersionPolicyRow[] | null>(null)
  const [drafts, setDrafts] = useState<Record<AppVersionPlatform, Draft>>({
    android: draftFromRow(),
    ios: draftFromRow(),
    windows: draftFromRow(),
  })
  const [loadError, setLoadError] = useState(false)
  const [busyPlatform, setBusyPlatform] = useState<AppVersionPlatform | null>(null)
  const [feedback, setFeedback] = useState<Record<AppVersionPlatform, string | null>>({
    android: null,
    ios: null,
    windows: null,
  })
  const [fieldError, setFieldError] = useState<Record<AppVersionPlatform, string | null>>({
    android: null,
    ios: null,
    windows: null,
  })
  const requestGen = useRef(0)

  const applyRows = useCallback((next: AppVersionPolicyRow[]) => {
    setRows(next)
    setDrafts({
      android: draftFromRow(next.find((r) => r.platform === 'android')),
      ios: draftFromRow(next.find((r) => r.platform === 'ios')),
      windows: draftFromRow(next.find((r) => r.platform === 'windows')),
    })
  }, [])

  const load = useCallback(async () => {
    const gen = ++requestGen.current
    setLoadError(false)
    try {
      const next = await gateway.list()
      if (gen !== requestGen.current) return
      applyRows(next)
    } catch (error) {
      if (gen !== requestGen.current) return
      if (error instanceof AppVersionError && error.code === 'unauthorized') {
        onAccessLost?.()
        return
      }
      setLoadError(true)
    }
  }, [applyRows, gateway, onAccessLost])

  useEffect(() => {
    void load()
  }, [load])

  const save = async (platform: AppVersionPlatform, clear: boolean) => {
    if (busyPlatform) return
    const draft = drafts[platform]
    let minVersion: string | null = null
    let messageAr = ''
    let updateUrl: string | null = null
    if (!clear) {
      minVersion = draft.minVersion.trim()
      messageAr = draft.messageAr.trim()
      updateUrl = draft.updateUrl.trim() || null
      if (!/^\d+\.\d+\.\d+$/.test(minVersion)) {
        setFieldError((prev) => ({ ...prev, [platform]: appVersionCopy.invalidVersion }))
        return
      }
      if (messageAr.length === 0) {
        setFieldError((prev) => ({ ...prev, [platform]: appVersionCopy.invalidMessage }))
        return
      }
      if (updateUrl !== null && !/^https:\/\//i.test(updateUrl)) {
        setFieldError((prev) => ({ ...prev, [platform]: appVersionCopy.invalidUrl }))
        return
      }
    }
    setBusyPlatform(platform)
    setFieldError((prev) => ({ ...prev, [platform]: null }))
    setFeedback((prev) => ({ ...prev, [platform]: null }))
    const gen = requestGen.current
    try {
      const result = await gateway.set({
        platform,
        minVersion,
        messageAr,
        updateUrl,
      })
      if (gen !== requestGen.current) return
      setRows((prev) => {
        const base = prev ?? []
        const others = base.filter((row) => row.platform !== platform)
        return [...others, result].sort((a, b) => a.platform.localeCompare(b.platform))
      })
      setDrafts((prev) => ({
        ...prev,
        [platform]: draftFromRow(result),
      }))
      setFeedback((prev) => ({
        ...prev,
        [platform]:
          result.status === 'unchanged'
            ? appVersionCopy.unchanged
            : clear
              ? appVersionCopy.cleared
              : appVersionCopy.saved,
      }))
    } catch (error) {
      if (gen !== requestGen.current) return
      if (error instanceof AppVersionError && error.code === 'unauthorized') {
        onAccessLost?.()
        return
      }
      setFeedback((prev) => ({ ...prev, [platform]: appVersionCopy.saveError }))
    } finally {
      setBusyPlatform(null)
    }
  }

  if (loadError && rows === null) {
    return (
      <Alert
        severity="error"
        action={<Button onClick={() => void load()}>{appVersionCopy.retry}</Button>}
      >
        {appVersionCopy.loadError}
      </Alert>
    )
  }

  return (
    <Stack spacing={2} sx={{ minWidth: 0 }}>
      <Typography component="h2" variant="h5" sx={{ fontWeight: 700 }}>
        {appVersionCopy.title}
      </Typography>
      <Typography sx={{ lineHeight: 1.6 }}>{appVersionCopy.intro}</Typography>
      {platforms.map((platform) => {
        const draft = drafts[platform]
        const current = rows?.find((row) => row.platform === platform)
        const busy = busyPlatform === platform
        return (
          <Box
            key={platform}
            component="section"
            aria-label={labels[platform]}
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
            <Typography component="h3" variant="h6" sx={{ fontWeight: 700 }}>
              {labels[platform]}
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {current?.minVersion
                ? `${appVersionCopy.currentMin}: ${current.minVersion}`
                : appVersionCopy.noMinimum}
            </Typography>
            <TextField
              label={appVersionCopy.minVersion}
              helperText={appVersionCopy.minVersionHint}
              value={draft.minVersion}
              onChange={(event) =>
                setDrafts((prev) => ({
                  ...prev,
                  [platform]: { ...prev[platform], minVersion: event.target.value },
                }))
              }
              slotProps={{
                htmlInput: {
                  dir: 'ltr',
                  'aria-label': `${labels[platform]} ${appVersionCopy.minVersion}`,
                },
              }}
              disabled={busy}
            />
            <TextField
              label={appVersionCopy.message}
              helperText={appVersionCopy.messageHint}
              value={draft.messageAr}
              onChange={(event) =>
                setDrafts((prev) => ({
                  ...prev,
                  [platform]: { ...prev[platform], messageAr: event.target.value },
                }))
              }
              multiline
              minRows={2}
              disabled={busy}
            />
            <TextField
              label={appVersionCopy.updateUrl}
              helperText={appVersionCopy.updateUrlHint}
              value={draft.updateUrl}
              onChange={(event) =>
                setDrafts((prev) => ({
                  ...prev,
                  [platform]: { ...prev[platform], updateUrl: event.target.value },
                }))
              }
              slotProps={{ htmlInput: { dir: 'ltr' } }}
              disabled={busy}
            />
            {fieldError[platform] && <Alert severity="error">{fieldError[platform]}</Alert>}
            {feedback[platform] && (
              <Alert severity={feedback[platform] === appVersionCopy.saveError ? 'error' : 'success'}>
                {feedback[platform]}
              </Alert>
            )}
            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1}>
              <Button
                variant="contained"
                disabled={busy}
                onClick={() => void save(platform, false)}
                sx={{ minHeight: 48 }}
              >
                {busy ? appVersionCopy.saving : appVersionCopy.save}
              </Button>
              <Button
                variant="outlined"
                disabled={busy}
                onClick={() => void save(platform, true)}
                sx={{ minHeight: 48 }}
              >
                {busy ? appVersionCopy.clearing : appVersionCopy.clear}
              </Button>
            </Stack>
          </Box>
        )
      })}
    </Stack>
  )
}

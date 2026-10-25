import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Stack from '@mui/material/Stack'
import Typography from '@mui/material/Typography'
import { useRef, useState } from 'react'
import { tokens } from '../theme/tokens.ts'
import {
  SubscriberContactError,
  type SubscriberContactGateway,
  type SubscriberContactRow,
} from './SubscriberContactGateway.ts'
import { subscriberCopy } from './copy.ts'

export function SubscriberContactReveal({
  shopId,
  gateway,
  onAccessLost,
}: {
  shopId: string
  gateway: SubscriberContactGateway
  onAccessLost?: () => void
}) {
  const [row, setRow] = useState<SubscriberContactRow | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const gen = useRef(0)

  const reveal = async () => {
    if (busy) return
    setBusy(true)
    setError(null)
    const requestId = ++gen.current
    try {
      const next = await gateway.reveal(shopId)
      if (requestId !== gen.current) return
      setRow(next)
    } catch (caught) {
      if (requestId !== gen.current) return
      if (caught instanceof SubscriberContactError && caught.code === 'unauthorized') {
        onAccessLost?.()
        return
      }
      if (caught instanceof SubscriberContactError && caught.code === 'forbidden') {
        setError(subscriberCopy.contactForbidden)
        return
      }
      setError(subscriberCopy.contactError)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Box
      component="section"
      aria-label={subscriberCopy.contactSection}
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
      <Typography component="h3" variant="subtitle1" sx={{ fontWeight: 700 }}>
        {subscriberCopy.contactSection}
      </Typography>
      {row === null ? (
        <>
          <Typography color="text.secondary">{subscriberCopy.contactMasked}</Typography>
          <Button
            variant="contained"
            disabled={busy}
            onClick={() => void reveal()}
            sx={{ minHeight: 48 }}
          >
            {busy ? subscriberCopy.contactRevealing : subscriberCopy.contactReveal}
          </Button>
        </>
      ) : (
        <Stack spacing={1}>
          <Typography>
            {subscriberCopy.contactPhone}:{' '}
            <Box component="span" dir="ltr">
              {row.phone}
            </Box>
          </Typography>
          <Typography>
            {subscriberCopy.contactCountry}:{' '}
            <Box component="span" dir="ltr">
              {row.countryCode}
            </Box>
          </Typography>
          <Typography>
            {subscriberCopy.contactLocation}: {row.locationDisplayAr ?? subscriberCopy.contactMissingLocation}
          </Typography>
        </Stack>
      )}
      {error && <Alert severity="error">{error}</Alert>}
    </Box>
  )
}

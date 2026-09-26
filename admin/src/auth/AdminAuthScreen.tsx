import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import TextField from '@mui/material/TextField'
import Typography from '@mui/material/Typography'
import { useState, type FormEvent } from 'react'
import type { AdminAccess, AdminAuthGateway } from './AdminAuthGateway.ts'

export function AdminAuthScreen({
  status,
  gateway,
}: {
  status: AdminAccess
  gateway: AdminAuthGateway | null
}) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(false)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (busy || gateway === null) return
    setBusy(true)
    setError(false)
    try {
      await gateway.signIn(email, password)
    } catch {
      setError(true)
    } finally {
      setBusy(false)
    }
  }

  const message = status === 'checking'
    ? 'جارٍ التحقق من الجلسة…'
    : status === 'unavailable'
      ? 'خدمة الإدارة غير متاحة الآن. حاول مجددًا.'
      : status === 'denied'
        ? 'ليس لهذا الحساب صلاحية إدارة المنصة.'
        : null

  return (
    <Box lang="ar" dir="rtl" sx={{ minHeight: '100vh', bgcolor: 'background.default', color: 'text.primary', display: 'grid', placeItems: 'center', p: 3 }}>
      <Box component="main" sx={{ width: '100%', maxWidth: 440, bgcolor: 'background.paper', border: 1, borderColor: 'divider', borderRadius: 3, p: 3 }}>
        <Typography component="h1" variant="h5" sx={{ mb: 1 }}>إدارة الدفتر</Typography>
        <Typography sx={{ mb: 3 }}>سجّل الدخول بالبريد الإلكتروني وكلمة المرور.</Typography>
        <Box component="form" onSubmit={submit} sx={{ display: 'grid', gap: 2 }}>
          <TextField label="البريد الإلكتروني" type="email" required value={email} onChange={event => setEmail(event.target.value)} slotProps={{ htmlInput: { dir: 'ltr' } }} />
          <TextField label="كلمة المرور" type="password" required value={password} onChange={event => setPassword(event.target.value)} />
          {message && <Typography role="status" color={status === 'checking' ? 'text.secondary' : 'error'}>{message}</Typography>}
          {error && <Typography role="alert" color="error">تعذر تسجيل الدخول. تحقق من البيانات وحاول مجددًا.</Typography>}
          <Button type="submit" variant="contained" disabled={busy || gateway === null || status === 'checking'}>
            {busy ? 'جارٍ تسجيل الدخول…' : 'دخول'}
          </Button>
        </Box>
      </Box>
    </Box>
  )
}

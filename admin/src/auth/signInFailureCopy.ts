// U19 (owner answer 2026-11-11, ADR 0047 D3): say why sign-in failed. A
// valid account without platform-admin access reaches the `denied` status.
export function signInFailureCopy(error: unknown): string {
  const code = typeof error === 'object' && error !== null && 'code' in error
    ? String((error as { code?: unknown }).code ?? '')
    : ''
  const status = typeof error === 'object' && error !== null && 'status' in error
    ? Number((error as { status?: unknown }).status)
    : NaN
  if (code === 'invalid_credentials' || code === 'user_not_found') {
    return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.'
  }
  if (code === 'email_not_confirmed') return 'هذا البريد الإلكتروني لم يُفعَّل بعد.'
  if (code === 'over_request_rate_limit' || code === 'over_email_send_rate_limit' || status === 429) {
    return 'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.'
  }
  if (code === 'user_banned') return 'هذا الحساب موقوف.'
  if (Number.isNaN(status) || status === 0 || status >= 500) {
    return 'تعذر الاتصال بالخادم. تحقق من الاتصال وحاول مجددًا.'
  }
  return 'تعذر تسجيل الدخول. تحقق من البيانات وحاول مجددًا.'
}

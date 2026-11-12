import { render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { AdminAuthScreen } from './AdminAuthScreen.tsx'
import { signInFailureCopy } from './signInFailureCopy.ts'

test('platform-admin sign-in stays email and password without a confirmation gate', () => {
  render(<AdminAuthScreen status="signedOut" gateway={null} />)

  expect(screen.getByRole('heading', { name: 'إدارة الدفتر' })).toBeInTheDocument()
  expect(screen.getByText('سجّل الدخول بالبريد الإلكتروني وكلمة المرور.')).toBeInTheDocument()
  expect(screen.getByLabelText(/البريد الإلكتروني/)).toHaveAttribute('type', 'email')
  expect(screen.getByLabelText(/كلمة المرور/)).toHaveAttribute('type', 'password')
  expect(screen.queryByLabelText(/هاتف|جوال/)).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: /حساب جديد|إنشاء حساب/ })).not.toBeInTheDocument()
  expect(screen.queryByText(/مؤكد|أكد بريدك|تم التحقق/)).not.toBeInTheDocument()
  expect(screen.getByRole('main').closest('[dir="rtl"]')).not.toBeNull()
  expect(screen.getByLabelText(/البريد الإلكتروني/).closest('[dir="ltr"]')).not.toBeNull()
})

test('a valid account without admin access is told so (U19)', () => {
  render(<AdminAuthScreen status="denied" gateway={null} />)
  expect(screen.getByRole('alert')).toHaveTextContent('هذا الحساب ليس له صلاحية الإدارة')
})

test('sign-in failures name their cause', () => {
  expect(signInFailureCopy({ code: 'invalid_credentials', status: 400 }))
    .toBe('البريد الإلكتروني أو كلمة المرور غير صحيحة.')
  expect(signInFailureCopy({ code: 'email_not_confirmed', status: 400 }))
    .toBe('هذا البريد الإلكتروني لم يُفعَّل بعد.')
  expect(signInFailureCopy({ status: 429 })).toContain('محاولات كثيرة')
  expect(signInFailureCopy(new TypeError('Failed to fetch'))).toContain('تعذر الاتصال بالخادم')
  expect(signInFailureCopy({ code: 'something_else', status: 400 }))
    .toBe('تعذر تسجيل الدخول. تحقق من البيانات وحاول مجددًا.')
})

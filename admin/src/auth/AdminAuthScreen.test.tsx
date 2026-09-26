import { render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { AdminAuthScreen } from './AdminAuthScreen.tsx'

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

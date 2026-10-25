import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import {
  SubscriberContactError,
  type SubscriberContactGateway,
} from './SubscriberContactGateway.ts'
import { SubscriberContactReveal } from './SubscriberContactReveal.tsx'
import { subscriberCopy } from './copy.ts'

function gateway(overrides: Partial<SubscriberContactGateway> = {}): SubscriberContactGateway {
  return {
    async reveal() {
      return {
        shopId: 'c3100000-0000-4000-8000-000000000001',
        phone: '+201099988877',
        countryCode: 'EG',
        locationDisplayAr: 'الجيزة',
      }
    },
    ...overrides,
  }
}

test('reveals phone and location after explicit action', async () => {
  const user = userEvent.setup()
  render(
    <SubscriberContactReveal
      shopId="c3100000-0000-4000-8000-000000000001"
      gateway={gateway()}
    />,
  )
  expect(screen.getByText(subscriberCopy.contactMasked)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.contactReveal }))
  expect(await screen.findByText(/\+201099988877/)).toBeInTheDocument()
  expect(screen.getByText(/الجيزة/)).toBeInTheDocument()
})

test('shows forbidden Arabic state without calling access loss', async () => {
  const user = userEvent.setup()
  const onAccessLost = vi.fn()
  render(
    <SubscriberContactReveal
      shopId="c3100000-0000-4000-8000-000000000001"
      gateway={gateway({
        async reveal() {
          throw new SubscriberContactError('forbidden')
        },
      })}
      onAccessLost={onAccessLost}
    />,
  )
  await user.click(screen.getByRole('button', { name: subscriberCopy.contactReveal }))
  expect(await screen.findByText(subscriberCopy.contactForbidden)).toBeInTheDocument()
  expect(onAccessLost).not.toHaveBeenCalled()
})

test('session loss notifies access lost', async () => {
  const user = userEvent.setup()
  const onAccessLost = vi.fn()
  render(
    <SubscriberContactReveal
      shopId="c3100000-0000-4000-8000-000000000001"
      gateway={gateway({
        async reveal() {
          throw new SubscriberContactError('unauthorized')
        },
      })}
      onAccessLost={onAccessLost}
    />,
  )
  await user.click(screen.getByRole('button', { name: subscriberCopy.contactReveal }))
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
})

import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { ThemeProvider } from '@mui/material/styles'
import { CacheProvider } from '@emotion/react'
import { subscriberCopy } from './copy.ts'
import { SubscriptionCodeError, type SubscriberDirectoryGateway } from './SubscriberDirectoryGateway.ts'
import { SubscriptionCodesPanel } from './SubscriptionCodesPanel.tsx'
import type { IssuedSubscriptionCode, SubscriptionCodePage, SubscriptionCodeRow } from './subscriptionCodes.ts'
import { rtlCache } from '../theme/rtlCache.ts'
import { createAppTheme } from '../theme/theme.ts'

/** ADR 0048: duration presets, code revocation and share. */

vi.setConfig({ testTimeout: 20_000 })

const shopId = 'c2100000-0000-4000-8000-000000000001'
const codeId = 'c2400000-0000-4000-8000-000000000001'
const requestKey = 'c2300000-0000-4000-8000-000000000011'
const secret = 'ABCDEFABCDEFABCDEFABCDEFABCDEFAB'

const unusedRow: SubscriptionCodeRow = {
  id: codeId,
  issuedAt: '2026-10-22T00:30:00.000Z',
  durationDays: 30,
  codeTtlDays: 30,
  codeExpiresAt: '2026-11-21T00:00:00.000Z',
  issuedVia: 'platform_admin',
  codeStatus: 'unused',
  redeemedAt: null,
  revokedAt: null,
  revokeReason: null,
}

function page(rows: SubscriptionCodeRow[] = [unusedRow]): SubscriptionCodePage {
  return {
    snapshotAt: '2026-10-22T00:30:00.000Z',
    shopId,
    shopName: 'متجر إصدار',
    rowCount: String(rows.length),
    pageSize: 20,
    rows,
    nextCursor: null,
  }
}

const issued: IssuedSubscriptionCode = {
  status: 'issued',
  code: secret,
  shopId,
  durationDays: 30,
  codeExpiresAt: '2026-11-21T00:00:00.000Z',
  requestKey,
  issuedVia: 'platform_admin',
}

function gateway(overrides: Partial<SubscriberDirectoryGateway> = {}): SubscriberDirectoryGateway {
  return {
    async list() { throw new Error('unused') },
    async get() { throw new Error('unused') },
    async listSubscriptionCodes() { return page() },
    async issueSubscriptionCode() { return issued },
    async revokeSubscriptionCode() { throw new Error('unused') },
    async bindSelectedShopSession() { return { id: 'lease-1' } },
    async assertBoundSession() {},
    async authorizeCopy() {},
    watchBoundSession() { return () => {} },
    releaseBoundSession() {},
    ...overrides,
  }
}

function renderPanel(next: SubscriberDirectoryGateway) {
  return render(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel shopId={shopId} shopName="متجر إصدار" gateway={next} onAccessLost={vi.fn()} />
      </ThemeProvider>
    </CacheProvider>,
  )
}

const originalRandom = crypto.randomUUID
const originalShare = Object.getOwnPropertyDescriptor(navigator, 'share')

afterEach(() => {
  crypto.randomUUID = originalRandom
  if (originalShare) Object.defineProperty(navigator, 'share', originalShare)
  else delete (navigator as { share?: unknown }).share
})

async function waitUntilBound() {
  await waitFor(() => {
    expect(screen.getByRole('button', { name: subscriberCopy.issueAction })).toBeEnabled()
  })
}

async function openIssue(user: ReturnType<typeof userEvent.setup>) {
  await waitUntilBound()
  await user.click(screen.getByRole('button', { name: subscriberCopy.issueAction }))
  return screen.findByRole('dialog')
}

async function openRevoke(user: ReturnType<typeof userEvent.setup>) {
  await waitUntilBound()
  await user.click(await screen.findByRole('button', { name: subscriberCopy.revokeAction }))
  return screen.findByRole('dialog')
}

test('duration presets fill the day count and the issue uses it', async () => {
  const issue = vi.fn().mockResolvedValue({ ...issued, durationDays: 180 })
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway({ issueSubscriptionCode: issue }))
  const dialog = await openIssue(user)
  const field = within(dialog).getByLabelText(subscriberCopy.durationLabel)
  expect(within(dialog).getByRole('button', { name: subscriberCopy.presetCustom })).toHaveAttribute('aria-pressed', 'true')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetYear1 }))
  expect(field).toHaveValue('360')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth3 }))
  expect(field).toHaveValue('90')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth6 }))
  expect(field).toHaveValue('180')
  expect(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth6 })).toHaveAttribute('aria-pressed', 'true')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.reviewTitle }))
  expect(screen.getByText(subscriberCopy.daysValue(180))).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  await waitFor(() => expect(issue).toHaveBeenCalledTimes(1))
  expect(issue.mock.calls[0]?.[0]).toMatchObject({ durationDays: 180 })
})

test('typing a custom count switches the selection to manual, and manual clears the field', async () => {
  const user = userEvent.setup()
  renderPanel(gateway())
  const dialog = await openIssue(user)
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth1 }))
  const field = within(dialog).getByLabelText(subscriberCopy.durationLabel)
  await user.type(field, '5')
  expect(field).toHaveValue('305')
  expect(within(dialog).getByRole('button', { name: subscriberCopy.presetCustom })).toHaveAttribute('aria-pressed', 'true')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetYear1 }))
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetCustom }))
  expect(field).toHaveValue('')
})

test('revoking an unused code needs a valid reason and refreshes history', async () => {
  crypto.randomUUID = () => 'c2300000-0000-4000-8000-000000000077'
  const revoke = vi.fn().mockResolvedValue({
    status: 'revoked', codeId, shopId, revokedAt: '2026-10-23T00:00:00.000Z',
  })
  const list = vi.fn().mockResolvedValue(page())
  const user = userEvent.setup()
  renderPanel(gateway({ listSubscriptionCodes: list, revokeSubscriptionCode: revoke }))
  const dialog = await openRevoke(user)
  expect(within(dialog).getByText(subscriberCopy.revokeIntro)).toBeInTheDocument()
  const reason = within(dialog).getByLabelText(subscriberCopy.revokeReasonLabel)
  await user.type(reason, 'ab')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.revokeConfirm }))
  expect(within(dialog).getByText(subscriberCopy.revokeReasonError)).toBeInTheDocument()
  expect(revoke).not.toHaveBeenCalled()
  await user.type(within(dialog).getByLabelText(subscriberCopy.revokeReasonLabel), 'c رقم خطأ ')
  const before = list.mock.calls.length
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.revokeConfirm }))
  expect(await within(dialog).findByText(subscriberCopy.revokeDone)).toBeInTheDocument()
  expect(revoke).toHaveBeenCalledTimes(1)
  expect(revoke.mock.calls[0]?.[0]).toEqual({
    codeId,
    shopId,
    reason: 'abc رقم خطأ',
    requestKey: 'c2300000-0000-4000-8000-000000000077',
  })
  await waitFor(() => expect(list.mock.calls.length).toBeGreaterThan(before))
})

test('a revoke timeout retries with the same request key', async () => {
  let key = 0
  crypto.randomUUID = () => `c2300000-0000-4000-8000-00000000008${key++}`
  const revoke = vi.fn()
    .mockRejectedValueOnce(new SubscriptionCodeError('timeout'))
    .mockResolvedValueOnce({ status: 'replayed', codeId, shopId, revokedAt: '2026-10-23T00:00:00.000Z' })
  const user = userEvent.setup()
  renderPanel(gateway({ revokeSubscriptionCode: revoke }))
  const dialog = await openRevoke(user)
  await user.type(within(dialog).getByLabelText(subscriberCopy.revokeReasonLabel), 'سبب واضح')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.revokeConfirm }))
  expect(await within(dialog).findByText(subscriberCopy.revokeTimeout)).toBeInTheDocument()
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.retrySame }))
  expect(await within(dialog).findByText(subscriberCopy.revokeReplayed)).toBeInTheDocument()
  expect(revoke).toHaveBeenCalledTimes(2)
  expect(revoke.mock.calls[1]?.[0].requestKey).toBe(revoke.mock.calls[0]?.[0].requestKey)
})

test('a code redeemed before the revocation is reported honestly', async () => {
  const revoke = vi.fn().mockResolvedValue({ status: 'redeemed', codeId, shopId, revokedAt: null })
  const user = userEvent.setup()
  renderPanel(gateway({ revokeSubscriptionCode: revoke }))
  const dialog = await openRevoke(user)
  await user.type(within(dialog).getByLabelText(subscriberCopy.revokeReasonLabel), 'سبب واضح')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.revokeConfirm }))
  expect(await within(dialog).findByText(subscriberCopy.revokeRedeemed)).toBeInTheDocument()
})

test('revoke access loss clears the panel and reports it', async () => {
  const onAccessLost = vi.fn()
  const user = userEvent.setup()
  render(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel
          shopId={shopId}
          shopName="متجر إصدار"
          gateway={gateway({
            async revokeSubscriptionCode() { throw new SubscriptionCodeError('access_lost') },
          })}
          onAccessLost={onAccessLost}
        />
      </ThemeProvider>
    </CacheProvider>,
  )
  const dialog = await openRevoke(user)
  await user.type(within(dialog).getByLabelText(subscriberCopy.revokeReasonLabel), 'سبب واضح')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.revokeConfirm }))
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
})

test('revoked rows show time and reason, and only unused rows offer revocation', async () => {
  renderPanel(gateway({
    async listSubscriptionCodes() {
      return page([
        {
          ...unusedRow,
          codeStatus: 'revoked',
          revokedAt: '2026-10-23T00:00:00.000Z',
          revokeReason: 'أُرسل إلى رقم خطأ',
        },
        {
          ...unusedRow,
          id: 'c2400000-0000-4000-8000-000000000002',
          issuedAt: '2026-10-21T00:30:00.000Z',
          codeStatus: 'redeemed',
          redeemedAt: '2026-10-22T00:00:00.000Z',
        },
      ])
    },
  }))
  expect(await screen.findByText('أُرسل إلى رقم خطأ')).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.statusRevoked)).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.columnRevokedAt)).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: subscriberCopy.revokeAction })).not.toBeInTheDocument()
})

test('share is offered where supported and sends the Arabic code text', async () => {
  crypto.randomUUID = () => requestKey
  const share = vi.fn().mockResolvedValue(undefined)
  Object.defineProperty(navigator, 'share', { configurable: true, value: share })
  const user = userEvent.setup()
  renderPanel(gateway({ async listSubscriptionCodes() { return page([]) } }))
  const dialog = await openIssue(user)
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth1 }))
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.reviewTitle }))
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.shareCode }))
  await waitFor(() => expect(share).toHaveBeenCalledWith({ text: subscriberCopy.shareText(30, secret) }))
  expect(screen.queryByText(subscriberCopy.shareFailed)).not.toBeInTheDocument()
})

test('a cancelled share is not reported as a failure', async () => {
  crypto.randomUUID = () => requestKey
  const share = vi.fn().mockRejectedValue(new DOMException('cancelled', 'AbortError'))
  Object.defineProperty(navigator, 'share', { configurable: true, value: share })
  const user = userEvent.setup()
  renderPanel(gateway({ async listSubscriptionCodes() { return page([]) } }))
  const dialog = await openIssue(user)
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth1 }))
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.reviewTitle }))
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  await user.click(await screen.findByRole('button', { name: subscriberCopy.shareCode }))
  await waitFor(() => expect(share).toHaveBeenCalled())
  expect(screen.queryByText(subscriberCopy.shareFailed)).not.toBeInTheDocument()
  expect(screen.getByText(secret)).toBeInTheDocument()
})

test('no share button without the Web Share API', async () => {
  crypto.randomUUID = () => requestKey
  delete (navigator as { share?: unknown }).share
  const user = userEvent.setup()
  renderPanel(gateway({ async listSubscriptionCodes() { return page([]) } }))
  const dialog = await openIssue(user)
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.presetMonth1 }))
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.reviewTitle }))
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: subscriberCopy.shareCode })).not.toBeInTheDocument()
})

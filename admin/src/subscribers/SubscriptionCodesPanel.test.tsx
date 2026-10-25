import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { ThemeProvider } from '@mui/material/styles'
import { CacheProvider } from '@emotion/react'
import { subscriberCopy } from './copy.ts'
import { SubscriptionCodeError, type SubscriberDirectoryGateway } from './SubscriberDirectoryGateway.ts'
import { SubscriptionCodesPanel } from './SubscriptionCodesPanel.tsx'
import type { IssuedSubscriptionCode, SubscriptionCodePage } from './subscriptionCodes.ts'
import { rtlCache } from '../theme/rtlCache.ts'
import { createAppTheme } from '../theme/theme.ts'

const shopId = 'c2100000-0000-4000-8000-000000000001'
const requestKey = 'c2300000-0000-4000-8000-000000000011'
const secret = 'ABCDEFABCDEFABCDEFABCDEFABCDEFAB'
const synthetic = 'SYNTHETICDISPLAYCODE000000000000'

const emptyHistory: SubscriptionCodePage = {
  snapshotAt: '2026-10-22T00:30:00.000Z',
  shopId,
  shopName: 'متجر إصدار',
  rowCount: '0',
  pageSize: 20,
  rows: [],
  nextCursor: null,
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

function page(overrides: Partial<SubscriptionCodePage> = {}): SubscriptionCodePage {
  return {
    ...emptyHistory,
    rowCount: '1',
    rows: [{
      id: 'c2400000-0000-4000-8000-000000000001',
      issuedAt: '2026-10-22T00:30:00.000Z',
      durationDays: 30,
      codeTtlDays: 30,
      codeExpiresAt: '2026-11-21T00:00:00.000Z',
      issuedVia: 'platform_admin',
      codeStatus: 'unused',
      redeemedAt: null,
    }],
    ...overrides,
  }
}

function gateway(overrides: Partial<SubscriberDirectoryGateway> = {}): SubscriberDirectoryGateway {
  return {
    async list() { throw new Error('unused') },
    async get() { throw new Error('unused') },
    async listSubscriptionCodes() { return emptyHistory },
    async issueSubscriptionCode() { return issued },
    async bindSelectedShopSession() { return { id: 'lease-1' } },
    async assertBoundSession() {},
    async authorizeCopy() {},
    watchBoundSession() { return () => {} },
    releaseBoundSession() {},
    ...overrides,
  }
}

function renderPanel(
  next: SubscriberDirectoryGateway,
  onAccessLost = vi.fn(),
  nextShopId = shopId,
) {
  return render(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel
          shopId={nextShopId}
          shopName="متجر إصدار"
          gateway={next}
          onAccessLost={onAccessLost}
        />
      </ThemeProvider>
    </CacheProvider>,
  )
}

const originalRandom = crypto.randomUUID
const originalClipboard = navigator.clipboard

afterEach(() => {
  crypto.randomUUID = originalRandom
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: originalClipboard })
  vi.unstubAllGlobals()
})

async function waitUntilBound() {
  await waitFor(() => {
    expect(screen.getByRole('button', { name: subscriberCopy.issueAction })).toBeEnabled()
  })
}

async function fillAndReview(user: ReturnType<typeof userEvent.setup>) {
  await waitUntilBound()
  await user.click(screen.getByRole('button', { name: subscriberCopy.issueAction }))
  const dialog = await screen.findByRole('dialog')
  await user.type(within(dialog).getByLabelText(subscriberCopy.durationLabel), '30')
  await user.click(within(dialog).getByRole('button', { name: subscriberCopy.reviewTitle }))
  return dialog
}

test('shows the secret once with an explicit copy action and never writes storage or logs', async () => {
  crypto.randomUUID = () => requestKey
  const writeText = vi.fn().mockResolvedValue(undefined)
  const setItem = vi.spyOn(Storage.prototype, 'setItem')
  const log = vi.spyOn(console, 'log')
  const info = vi.spyOn(console, 'info')
  const debug = vi.spyOn(console, 'debug')
  const warn = vi.spyOn(console, 'warn')
  const user = userEvent.setup()
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText },
  })
  renderPanel(gateway())
  await fillAndReview(user)
  expect(screen.getByText('متجر إصدار')).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.reviewEffect)).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.estimatedNote)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(screen.getByText(subscriberCopy.issuedOnce)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.copyCode }))
  await waitFor(() => expect(writeText).toHaveBeenCalledWith(secret))
  expect(await screen.findByText(subscriberCopy.copied)).toBeInTheDocument()
  expect(setItem).not.toHaveBeenCalled()
  expect(JSON.stringify(log.mock.calls)).not.toContain(secret)
  expect(JSON.stringify(info.mock.calls)).not.toContain(secret)
  expect(JSON.stringify(debug.mock.calls)).not.toContain(secret)
  expect(JSON.stringify(warn.mock.calls)).not.toContain(secret)
  expect(window.location.href).not.toContain(secret)
})

test('dismissal clears the secret from the session view', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway())
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.close }))
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  expect(screen.queryByText(secret)).not.toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.issueAction }))
  expect(screen.queryByText(secret)).not.toBeInTheDocument()
})

test('access loss during copy clears the secret and reports it', async () => {
  crypto.randomUUID = () => requestKey
  const onAccessLost = vi.fn()
  const user = userEvent.setup()
  render(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel
          shopId={shopId}
          shopName="متجر إصدار"
          gateway={gateway({
            async authorizeCopy() {
              throw new SubscriptionCodeError('access_lost')
            },
          })}
          onAccessLost={onAccessLost}
        />
      </ThemeProvider>
    </CacheProvider>,
  )
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.copyCode }))
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
})

test('a late issue response is ignored after close', async () => {
  crypto.randomUUID = () => requestKey
  let resolveIssue: ((value: IssuedSubscriptionCode) => void) | undefined
  const user = userEvent.setup()
  renderPanel(gateway({
    issueSubscriptionCode: () => new Promise((resolve) => { resolveIssue = resolve }),
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.issuing)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.close }))
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  resolveIssue?.(issued)
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
})

test('duplicate confirm is ignored while the first request is in flight', async () => {
  crypto.randomUUID = () => requestKey
  const calls: string[] = []
  let resolveIssue: ((value: IssuedSubscriptionCode) => void) | undefined
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode(input) {
      calls.push(input.requestKey)
      return new Promise((resolve) => { resolveIssue = resolve })
    },
  }))
  await fillAndReview(user)
  const confirm = screen.getByRole('button', { name: subscriberCopy.confirmIssue })
  await user.click(confirm)
  await user.click(confirm)
  expect(await screen.findByText(subscriberCopy.issuing)).toBeInTheDocument()
  expect(calls).toEqual([requestKey])
  resolveIssue?.(issued)
  expect(await screen.findByText(secret)).toBeInTheDocument()
})

test('timeout freezes the envelope and retry reuses the same key', async () => {
  crypto.randomUUID = () => requestKey
  const keys: string[] = []
  let fail = true
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode(input) {
      keys.push(input.requestKey)
      if (fail) throw new SubscriptionCodeError('timeout')
      return issued
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.timeoutBody)).toBeInTheDocument()
  fail = false
  await user.click(screen.getByRole('button', { name: subscriberCopy.retrySame }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(keys).toEqual([requestKey, requestKey])
})

test('replay confirms issuance without recovering or issuing another code', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode() {
      return { ...issued, status: 'replayed', code: null }
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.replayBody)).toBeInTheDocument()
  expect(screen.queryByText(secret)).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: subscriberCopy.copyCode })).not.toBeInTheDocument()
})

test('range errors stay on the form', async () => {
  const user = userEvent.setup()
  const issue = vi.fn()
  renderPanel(gateway({ issueSubscriptionCode: issue }))
  await waitUntilBound()
  await user.click(screen.getByRole('button', { name: subscriberCopy.issueAction }))
  await user.type(screen.getByLabelText(subscriberCopy.durationLabel), '3661')
  await user.click(screen.getByRole('button', { name: subscriberCopy.reviewTitle }))
  expect(await screen.findByText(subscriberCopy.rangeError)).toBeInTheDocument()
  expect(issue).not.toHaveBeenCalled()
})

test('history paging and retry after failure', async () => {
  const user = userEvent.setup()
  const seen: Array<string | null> = []
  let fail = true
  renderPanel(gateway({
    async listSubscriptionCodes(_shopId, cursor) {
      seen.push(cursor)
      if (fail) throw new SubscriptionCodeError('unavailable')
      if (cursor === null) return page({ nextCursor: 'cursor-1', rowCount: '2' })
      return page({
        nextCursor: null,
        rowCount: '2',
        rows: [{
          id: 'c2400000-0000-4000-8000-000000000002',
          issuedAt: '2026-10-21T00:30:00.000Z',
          durationDays: 15,
          codeTtlDays: 30,
          codeExpiresAt: '2026-11-20T00:00:00.000Z',
          issuedVia: 'service_role',
          codeStatus: 'redeemed',
          redeemedAt: '2026-10-22T08:00:00.000Z',
        }],
      })
    },
  }))
  expect(await screen.findByText(subscriberCopy.historyError)).toBeInTheDocument()
  fail = false
  await user.click(screen.getByRole('button', { name: subscriberCopy.retry }))
  expect(await screen.findByText(subscriberCopy.statusUnused)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.nextPage }))
  expect(await screen.findByText(subscriberCopy.statusRedeemed)).toBeInTheDocument()
  expect(seen.at(-1)).toBe('cursor-1')
})

test('synthetic display text is allowed in the issued view', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode() {
      return { ...issued, code: synthetic }
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(synthetic)).toBeInTheDocument()
})

test('copy after dismissal does not write the clipboard', async () => {
  crypto.randomUUID = () => requestKey
  let resolveAssert: (() => void) | undefined
  const writeText = vi.fn().mockResolvedValue(undefined)
  const user = userEvent.setup()
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText },
  })
  renderPanel(gateway({
    authorizeCopy: () => new Promise((resolve) => {
      resolveAssert = () => resolve()
    }),
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.copyCode }))
  await waitFor(() => expect(resolveAssert).toBeDefined())
  await user.click(screen.getByRole('button', { name: subscriberCopy.close }))
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  resolveAssert?.()
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
  expect(writeText).toHaveBeenCalledTimes(0)
})

test('replaced session while copy check pending does not write the clipboard', async () => {
  crypto.randomUUID = () => requestKey
  let resolveAssert: (() => void) | undefined
  let lose: (() => void) | undefined
  const writeText = vi.fn().mockResolvedValue(undefined)
  const onAccessLost = vi.fn()
  const user = userEvent.setup()
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText },
  })
  renderPanel(gateway({
    watchBoundSession(_binding, onLost) {
      lose = onLost
      return () => {
        lose = undefined
      }
    },
    authorizeCopy: () => new Promise((resolve) => {
      resolveAssert = () => resolve()
    }),
  }), onAccessLost)
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.copyCode }))
  await waitFor(() => expect(resolveAssert).toBeDefined())
  lose?.()
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
  resolveAssert?.()
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
  expect(writeText).toHaveBeenCalledTimes(0)
})

test('copy authorization error clears the visible secret', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway({
    async authorizeCopy() {
      throw new SubscriptionCodeError('unavailable')
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: subscriberCopy.copyCode }))
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
  expect(await screen.findByText(subscriberCopy.copyFailed)).toBeInTheDocument()
})

test('invalid issue payload keeps the frozen envelope for the same key', async () => {
  crypto.randomUUID = () => requestKey
  const keys: string[] = []
  let fail = true
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode(input) {
      keys.push(input.requestKey)
      if (fail) throw new SubscriptionCodeError('invalid_response')
      return issued
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.issueUnknown)).toBeInTheDocument()
  fail = false
  await user.click(screen.getByRole('button', { name: subscriberCopy.retrySame }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(keys).toEqual([requestKey, requestKey])
})

test('request conflict and not-found stay distinct from an unknown outcome', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway({
    async issueSubscriptionCode() {
      throw new SubscriptionCodeError('request_conflict')
    },
  }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.issueConflict)).toBeInTheDocument()
  expect(screen.queryByText(subscriberCopy.issueUnknown)).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: subscriberCopy.retrySame })).not.toBeInTheDocument()
})

test('changing the selected shop purges a visible secret', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  const next = gateway()
  const view = renderPanel(next)
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  view.rerender(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel
          shopId="c2100000-0000-4000-8000-000000000099"
          shopName="متجر آخر"
          gateway={next}
          onAccessLost={vi.fn()}
        />
      </ThemeProvider>
    </CacheProvider>,
  )
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
})

test('a history page for another shop is ignored', async () => {
  renderPanel(gateway({
    async listSubscriptionCodes() {
      return page({
        shopId: 'c2100000-0000-4000-8000-000000000099',
        shopName: 'متجر آخر',
      })
    },
  }))
  expect(await screen.findByText(subscriberCopy.historyLoading)).toBeInTheDocument()
  expect(screen.queryByText('متجر آخر')).not.toBeInTheDocument()
  expect(screen.queryByText(subscriberCopy.statusUnused)).not.toBeInTheDocument()
})

test('a late history result cannot overwrite a newer selected shop or resurrect a secret', async () => {
  crypto.randomUUID = () => requestKey
  let resolveFirst: ((value: SubscriptionCodePage) => void) | undefined
  const user = userEvent.setup()
  const hanging = gateway({
    listSubscriptionCodes: () => new Promise((resolve) => {
      resolveFirst = resolve
    }),
  })
  const view = renderPanel(hanging)
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  const other = gateway({
    async listSubscriptionCodes() {
      return page({
        shopId: 'c2100000-0000-4000-8000-000000000099',
        shopName: 'متجر لاحق',
        rows: [{
          id: 'c2400000-0000-4000-8000-000000000099',
          issuedAt: '2026-10-21T00:30:00.000Z',
          durationDays: 15,
          codeTtlDays: 30,
          codeExpiresAt: '2026-11-20T00:00:00.000Z',
          issuedVia: 'service_role',
          codeStatus: 'redeemed',
          redeemedAt: '2026-10-22T08:00:00.000Z',
        }],
      })
    },
  })
  view.rerender(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <SubscriptionCodesPanel
          shopId="c2100000-0000-4000-8000-000000000099"
          shopName="متجر لاحق"
          gateway={other}
          onAccessLost={vi.fn()}
        />
      </ThemeProvider>
    </CacheProvider>,
  )
  expect(await screen.findByText(subscriberCopy.statusRedeemed)).toBeInTheDocument()
  resolveFirst?.(page({ shopName: 'متجر إصدار' }))
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
  expect(screen.queryByText(subscriberCopy.statusUnused)).not.toBeInTheDocument()
})

test('pagehide purges the visible secret', async () => {
  crypto.randomUUID = () => requestKey
  const user = userEvent.setup()
  renderPanel(gateway())
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  window.dispatchEvent(new Event('pagehide'))
  await waitFor(() => expect(screen.queryByText(secret)).not.toBeInTheDocument())
})

test('unavailable bind shows Arabic failure and retry restores issuance', async () => {
  let fail = true
  const user = userEvent.setup()
  const bind = vi.fn(async () => {
    if (fail) throw new SubscriptionCodeError('unavailable')
    return { id: 'lease-retry' }
  })
  const issue = vi.fn(async () => issued)
  crypto.randomUUID = () => requestKey
  renderPanel(gateway({
    bindSelectedShopSession: bind,
    issueSubscriptionCode: issue,
  }))
  expect(await screen.findByRole('alert')).toHaveTextContent(subscriberCopy.bindFailed)
  expect(screen.getByRole('button', { name: subscriberCopy.issueAction })).toBeDisabled()
  fail = false
  await user.click(screen.getByRole('button', { name: subscriberCopy.bindRetry }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(issue).toHaveBeenCalledTimes(1)
})

test('pagehide during a pending issue resets latches and a later review does not restore the old secret', async () => {
  crypto.randomUUID = () => requestKey
  let resolveIssue: ((value: IssuedSubscriptionCode) => void) | undefined
  const issue = vi.fn(() => new Promise<IssuedSubscriptionCode>((resolve) => {
    resolveIssue = resolve
  }))
  const user = userEvent.setup()
  renderPanel(gateway({ issueSubscriptionCode: issue }))
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.issuing)).toBeInTheDocument()
  window.dispatchEvent(new Event('pagehide'))
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
  expect(screen.queryByText(secret)).not.toBeInTheDocument()
  await fillAndReview(user)
  await user.click(screen.getByRole('button', { name: subscriberCopy.confirmIssue }))
  expect(await screen.findByText(subscriberCopy.issuing)).toBeInTheDocument()
  resolveIssue?.(issued)
  expect(await screen.findByText(secret)).toBeInTheDocument()
  expect(issue).toHaveBeenCalledTimes(2)
})


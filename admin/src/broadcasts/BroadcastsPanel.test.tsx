import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, expect, test, vi } from 'vitest'
import { ThemeProvider } from '@mui/material/styles'
import { CacheProvider } from '@emotion/react'
import { rtlCache } from '../theme/rtlCache.ts'
import { createAppTheme } from '../theme/theme.ts'
import {
  BroadcastError,
  type BroadcastGateway,
  type BroadcastPage,
  type BroadcastRow,
} from './BroadcastGateway.ts'
import { BroadcastsPanel } from './BroadcastsPanel.tsx'
import { broadcastCopy, segmentLabel, stateLabel } from './copy.ts'

// The compose flows type full messages; allow for a loaded test runner.
vi.setConfig({ testTimeout: 20_000 })

const shopId = 'b1100000-0000-4000-8000-000000000001'
const keyA = 'b1200000-0000-4000-8000-00000000000a'

const activeRow: BroadcastRow = {
  id: 'b1000000-0000-4000-8000-000000000001',
  createdAt: '2026-11-13T10:00:00.000Z',
  createdByEmail: 'admin@example.test',
  segment: 'expiring',
  segmentDays: 7,
  segmentShopId: null,
  segmentShopName: null,
  titleAr: 'تجديد الاشتراك',
  bodyAr: 'اشتراكك ينتهي قريبًا.',
  linkUrl: null,
  startsAt: '2026-11-13T10:00:00.000Z',
  endsAt: '2026-12-13T10:00:00.000Z',
  state: 'active',
  recipientCount: '12',
  deliveredCount: '5',
  readCount: '2',
  withdrawnAt: null,
  withdrawReason: null,
}

function listPage(rows: BroadcastRow[] = [activeRow]): BroadcastPage {
  return { snapshotAt: '2026-11-13T10:00:00.000Z', pageSize: 20, rows, nextCursor: null }
}

function gateway(overrides: Partial<BroadcastGateway> = {}): BroadcastGateway {
  return {
    async list() { return listPage() },
    async preview() { return { snapshotAt: '2026-11-13T10:00:00.000Z', recipientCount: '12' } },
    async send() {
      return {
        status: 'sent',
        broadcastId: 'b1000000-0000-4000-8000-000000000009',
        recipientCount: '12',
        startsAt: '2026-11-13T10:00:00.000Z',
        endsAt: '2026-12-13T10:00:00.000Z',
      }
    },
    async withdraw(id) {
      return { status: 'withdrawn', broadcastId: id, withdrawnAt: '2026-11-14T00:00:00.000Z' }
    },
    ...overrides,
  }
}

function renderPanel(next: BroadcastGateway, onAccessLost = vi.fn(), initialShopId: string | null = null) {
  return render(
    <CacheProvider value={rtlCache}>
      <ThemeProvider theme={createAppTheme('light')}>
        <BroadcastsPanel gateway={next} onAccessLost={onAccessLost} initialShopId={initialShopId} />
      </ThemeProvider>
    </CacheProvider>,
  )
}

const originalRandom = crypto.randomUUID
afterEach(() => {
  crypto.randomUUID = originalRandom
})

async function fillMessage(user: ReturnType<typeof userEvent.setup>, dialog: HTMLElement) {
  await user.type(within(dialog).getByLabelText(broadcastCopy.titleLabel), 'تجديد الاشتراك')
  await user.type(within(dialog).getByLabelText(broadcastCopy.bodyLabel), 'اشتراكك ينتهي قريبًا.')
}

test('lists sent messages with state, audience and counts', async () => {
  renderPanel(gateway())
  const list = await screen.findByRole('list', { name: broadcastCopy.listLabel })
  expect(within(list).getByText('تجديد الاشتراك')).toBeInTheDocument()
  expect(within(list).getByText(stateLabel.active)).toBeInTheDocument()
  expect(within(list).getByText('اشتراكات سارية تنتهي خلال 7 يومًا')).toBeInTheDocument()
  const delivered = within(list).getByText(broadcastCopy.deliveredCount)
  expect(delivered.nextElementSibling?.textContent).toMatch(/^(٥|5)$/)
  const read = within(list).getByText(broadcastCopy.readCount)
  expect(read.nextElementSibling?.textContent).toMatch(/^(٢|2)$/)
})

test('compose validates, previews the audience, and sends with the confirmed count', async () => {
  crypto.randomUUID = () => keyA
  const preview = vi.fn().mockResolvedValue({ snapshotAt: '2026-11-13T10:00:00.000Z', recipientCount: '12' })
  const send = vi.fn().mockResolvedValue({
    status: 'sent',
    broadcastId: 'b1000000-0000-4000-8000-000000000009',
    recipientCount: '12',
    startsAt: '2026-11-13T10:00:00.000Z',
    endsAt: '2026-12-13T10:00:00.000Z',
  })
  const list = vi.fn().mockResolvedValue(listPage([]))
  const user = userEvent.setup()
  renderPanel(gateway({ preview, send, list }))
  await user.click(await screen.findByRole('button', { name: broadcastCopy.compose }))
  const dialog = await screen.findByRole('dialog')
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  expect(within(dialog).getByText(broadcastCopy.titleError)).toBeInTheDocument()
  expect(within(dialog).getByText(broadcastCopy.bodyError)).toBeInTheDocument()
  expect(preview).not.toHaveBeenCalled()

  await user.click(within(dialog).getByLabelText(broadcastCopy.segmentLabel))
  await user.click(await screen.findByRole('option', { name: segmentLabel.expiring }))
  await fillMessage(user, dialog)
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  await waitFor(() => expect(preview).toHaveBeenCalledWith({ segment: 'expiring', days: 7, shopId: null }))
  expect(await within(dialog).findByText(broadcastCopy.reviewNote)).toBeInTheDocument()
  expect(within(dialog).getByTestId('broadcast-recipient-count')).toHaveTextContent(/١٢|12/)

  const before = list.mock.calls.length
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.confirmSend }))
  expect(await within(dialog).findByText(/أُرسلت الرسالة إلى/)).toBeInTheDocument()
  expect(send).toHaveBeenCalledTimes(1)
  expect(send.mock.calls[0]?.[0]).toMatchObject({
    requestKey: keyA,
    expectedCount: 12,
    segment: 'expiring',
    days: 7,
    shopId: null,
    titleAr: 'تجديد الاشتراك',
    bodyAr: 'اشتراكك ينتهي قريبًا.',
    linkUrl: null,
    startsAt: null,
    endsAt: null,
  })
  await waitFor(() => expect(list.mock.calls.length).toBeGreaterThan(before))
})

test('a changed audience sends nothing and asks for a fresh review', async () => {
  let key = 0
  crypto.randomUUID = () => `b1200000-0000-4000-8000-00000000001${key++}`
  const preview = vi.fn()
    .mockResolvedValueOnce({ snapshotAt: '2026-11-13T10:00:00.000Z', recipientCount: '12' })
    .mockResolvedValueOnce({ snapshotAt: '2026-11-13T10:01:00.000Z', recipientCount: '13' })
  const send = vi.fn()
    .mockRejectedValueOnce(new BroadcastError('audience_changed'))
    .mockResolvedValueOnce({
      status: 'sent',
      broadcastId: 'b1000000-0000-4000-8000-000000000009',
      recipientCount: '13',
      startsAt: '2026-11-13T10:00:00.000Z',
      endsAt: '2026-12-13T10:00:00.000Z',
    })
  const user = userEvent.setup()
  renderPanel(gateway({ preview, send }))
  await user.click(await screen.findByRole('button', { name: broadcastCopy.compose }))
  const dialog = await screen.findByRole('dialog')
  await fillMessage(user, dialog)
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  await user.click(await within(dialog).findByRole('button', { name: broadcastCopy.confirmSend }))
  expect(await within(dialog).findByText(broadcastCopy.audienceChanged)).toBeInTheDocument()
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.reviewAgain }))
  await waitFor(() => expect(within(dialog).getByTestId('broadcast-recipient-count')).toHaveTextContent(/١٣|13/))
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.confirmSend }))
  expect(await within(dialog).findByText(/أُرسلت الرسالة إلى/)).toBeInTheDocument()
  expect(send.mock.calls[1]?.[0].expectedCount).toBe(13)
})

test('a send timeout retries with the same request key', async () => {
  let key = 0
  crypto.randomUUID = () => `b1200000-0000-4000-8000-00000000002${key++}`
  const send = vi.fn()
    .mockRejectedValueOnce(new BroadcastError('timeout'))
    .mockResolvedValueOnce({
      status: 'replayed',
      broadcastId: 'b1000000-0000-4000-8000-000000000009',
      recipientCount: '12',
      startsAt: '2026-11-13T10:00:00.000Z',
      endsAt: '2026-12-13T10:00:00.000Z',
    })
  const user = userEvent.setup()
  renderPanel(gateway({ send }))
  await user.click(await screen.findByRole('button', { name: broadcastCopy.compose }))
  const dialog = await screen.findByRole('dialog')
  await fillMessage(user, dialog)
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  await user.click(await within(dialog).findByRole('button', { name: broadcastCopy.confirmSend }))
  expect(await within(dialog).findByText(broadcastCopy.sendTimeout)).toBeInTheDocument()
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.retrySame }))
  expect(await within(dialog).findByText(broadcastCopy.replayed, { exact: false })).toBeInTheDocument()
  expect(send).toHaveBeenCalledTimes(2)
  expect(send.mock.calls[1]?.[0].requestKey).toBe(send.mock.calls[0]?.[0].requestKey)
})

test('a shop link opens the composer for that shop', async () => {
  const preview = vi.fn().mockResolvedValue({ snapshotAt: '2026-11-13T10:00:00.000Z', recipientCount: '1' })
  const user = userEvent.setup()
  renderPanel(gateway({ preview }), vi.fn(), shopId)
  const dialog = await screen.findByRole('dialog')
  expect(within(dialog).getByLabelText(broadcastCopy.shopIdLabel)).toHaveValue(shopId)
  await fillMessage(user, dialog)
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  await waitFor(() => expect(preview).toHaveBeenCalledWith({ segment: 'shop', days: null, shopId }))
})

test('an unknown shop in preview is shown on the field', async () => {
  const user = userEvent.setup()
  renderPanel(gateway({ async preview() { throw new BroadcastError('not_found') } }), vi.fn(), shopId)
  const dialog = await screen.findByRole('dialog')
  await fillMessage(user, dialog)
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.review }))
  expect(await within(dialog).findByText(broadcastCopy.previewNotFound)).toBeInTheDocument()
  expect(within(dialog).getByText(broadcastCopy.shopIdError)).toBeInTheDocument()
})

test('withdrawing asks for a reason and refreshes the list', async () => {
  const withdraw = vi.fn().mockResolvedValue({
    status: 'withdrawn',
    broadcastId: activeRow.id,
    withdrawnAt: '2026-11-14T00:00:00.000Z',
  })
  const list = vi.fn().mockResolvedValue(listPage())
  const user = userEvent.setup()
  renderPanel(gateway({ withdraw, list }))
  await user.click(await screen.findByRole('button', { name: broadcastCopy.withdraw }))
  const dialog = await screen.findByRole('dialog')
  await user.type(within(dialog).getByLabelText(broadcastCopy.withdrawReason), 'خط')
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.confirmWithdraw }))
  expect(within(dialog).getByText(broadcastCopy.withdrawReasonError)).toBeInTheDocument()
  expect(withdraw).not.toHaveBeenCalled()
  await user.type(within(dialog).getByLabelText(broadcastCopy.withdrawReason), 'أ بالخطأ')
  const before = list.mock.calls.length
  await user.click(within(dialog).getByRole('button', { name: broadcastCopy.confirmWithdraw }))
  expect(await within(dialog).findByText(broadcastCopy.withdrawn)).toBeInTheDocument()
  expect(withdraw).toHaveBeenCalledWith(activeRow.id, 'خطأ بالخطأ')
  await waitFor(() => expect(list.mock.calls.length).toBeGreaterThan(before))
})

test('withdrawn messages show the reason and offer no withdrawal', async () => {
  renderPanel(gateway({
    async list() {
      return listPage([{
        ...activeRow,
        state: 'withdrawn',
        withdrawnAt: '2026-11-14T00:00:00.000Z',
        withdrawReason: 'أُرسلت بالخطأ',
      }])
    },
  }))
  expect(await screen.findByText('أُرسلت بالخطأ')).toBeInTheDocument()
  expect(screen.getByText(stateLabel.withdrawn)).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: broadcastCopy.withdraw })).not.toBeInTheDocument()
})

test('lost access clears the panel and reports it', async () => {
  const onAccessLost = vi.fn()
  renderPanel(gateway({ async list() { throw new BroadcastError('unauthorized') } }), onAccessLost)
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
  expect(screen.queryByText(broadcastCopy.title)).not.toBeInTheDocument()
})

test('a list failure offers a retry', async () => {
  const list = vi.fn()
    .mockRejectedValueOnce(new BroadcastError('unavailable'))
    .mockResolvedValueOnce(listPage())
  const user = userEvent.setup()
  renderPanel(gateway({ list }))
  expect(await screen.findByText(broadcastCopy.loadError)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: broadcastCopy.retry }))
  expect(await screen.findByText('تجديد الاشتراك')).toBeInTheDocument()
})

import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import type {
  SupportGateway,
  SupportInquiryAdminRow,
  SupportInquiryPage,
  SupportListInput,
  SupportUpdateInput,
  SupportUpdateResult,
} from './SupportGateway.ts'
import { SupportError, normalizeSupportReply } from './SupportGateway.ts'
import { SupportMailboxPanel } from './SupportMailboxPanel.tsx'
import { supportCopy, supportStatusLabel } from './copy.ts'

const shopId = 'a1100000-0000-4000-8000-000000000001'
const inquiryId = 'e1100000-0000-4000-8000-000000000001'

function adminRow(overrides: Partial<SupportInquiryAdminRow> = {}): SupportInquiryAdminRow {
  return {
    id: inquiryId,
    shopId,
    shopName: 'متجر الدعم',
    category: 'technical',
    bodyAr: 'سؤال عن تجديد الاشتراك والميزانية الشهرية',
    status: 'new',
    replyAr: null,
    createdAt: '2026-10-27T09:00:00.000Z',
    updatedAt: '2026-10-27T09:00:00.000Z',
    answeredAt: null,
    closedAt: null,
    shopCreatedAt: '2026-01-01T00:00:00.000Z',
    shopTimeZone: 'Africa/Cairo',
    ...overrides,
  }
}

class FakeSupportGateway implements SupportGateway {
  pages: SupportInquiryPage[] = []
  updates: SupportUpdateInput[] = []
  failures: Array<'stale' | 'invalid_transition' | 'not_found' | 'unavailable' | 'access_lost'> = []

  listCalls: SupportListInput[] = []
  private updateResult: SupportUpdateResult = {
    inquiryId: inquiryId,
    status: 'in_progress',
    replyAr: null,
    saved: true,
  }

  constructor(initial: SupportInquiryAdminRow[] = [adminRow()]) {
    this.pages = [pageOf(initial)]
  }

  setPages(pages: SupportInquiryPage[]) {
    this.pages = pages
  }

  async list(input: SupportListInput): Promise<SupportInquiryPage> {
    this.listCalls.push(input)
    if (this.failures.length > 0) {
      return failWith(this.failures.shift()!)
    }
    return this.pages.shift() ?? emptyPage()
  }

  async updateInquiryStatus(input: SupportUpdateInput): Promise<SupportUpdateResult> {
    this.updates.push(input)
    if (this.failures.length > 0) {
      return failWith(this.failures.shift()!)
    }
    return this.updateResult
  }

  setUpdateResult(result: SupportUpdateResult) {
    this.updateResult = result
  }
}

function failWith(code: 'stale' | 'invalid_transition' | 'not_found' | 'unavailable' | 'access_lost'): never {
  const mapped = {
    stale: 'stale_cursor',
    invalid_transition: 'invalid_transition',
    not_found: 'not_found',
    unavailable: 'unavailable',
    access_lost: 'access_lost',
  } as const
  throw new SupportError(mapped[code])
}

function pageOf(rows: SupportInquiryAdminRow[], more = false): SupportInquiryPage {
  return {
    inquiries: rows,
    nextCursorAt: more ? '2026-10-26T09:00:00.000Z' : null,
    nextCursorId: more ? 'e1000000-0000-4000-8000-000000000009' : null,
    snapshotAt: '2026-10-27T09:30:00.000Z',
  }
}

function emptyPage(): SupportInquiryPage {
  return pageOf([])
}

test('normalizeSupportReply mirrors the server rule', () => {
  expect(normalizeSupportReply('  ردّ وافٍ على استفسار المالك  ')).toBe(
    'ردّ وافٍ على استفسار المالك',
  )
  expect(normalizeSupportReply('سطر أول من الرد\nوسطر ثانٍ للتفصيل')).not.toBeNull()
  expect(normalizeSupportReply('قصير')).toBeNull()
  expect(normalizeSupportReply('ط'.repeat(1000))).not.toBeNull()
  expect(normalizeSupportReply('ط'.repeat(1001))).toBeNull()
  expect(normalizeSupportReply('رد يحتوي\tعلى تباعد')).toBeNull()
  expect(normalizeSupportReply('رد يحتوي\rعلى CR')).toBeNull()
})

async function openPanel(gateway: SupportGateway, onAccessLost?: () => void) {
  render(<SupportMailboxPanel gateway={gateway} onAccessLost={onAccessLost} />)
  await waitFor(() => expect(screen.queryByTestId('support-loading')).toBeNull())
}

test('renders rows with bounded shop context and saved reply', async () => {
  const gateway = new FakeSupportGateway([
    adminRow({
      status: 'closed',
      replyAr: 'تم حل المشكلة وتجديد الاشتراك بنجاح.',
      answeredAt: '2026-10-27T10:00:00.000Z',
      closedAt: '2026-10-27T11:00:00.000Z',
    }),
  ])
  await openPanel(gateway)
  expect(screen.getByText('متجر الدعم')).toBeInTheDocument()
  expect(screen.getByTestId('support-status-closed')).toHaveTextContent(
    supportStatusLabel.closed,
  )
  expect(screen.getByText('مشكلة تقنية')).toBeInTheDocument()
  expect(screen.getByText(/تم حل المشكلة/)).toBeInTheDocument()
  expect(screen.getByTestId('support-snapshot')).toBeInTheDocument()
  expect(screen.queryByTestId('support-triage-close-' + inquiryId)).toBeNull()
})

test('filter buttons reload with the selected status', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway([])
  await openPanel(gateway)
  expect(gateway.listCalls[0]?.status).toBe('all')
  await user.click(screen.getByTestId('support-filter-new'))
  await waitFor(() => expect(gateway.listCalls.at(-1)?.status).toBe('new'))
})

test('search passes the trimmed exact identifier', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway([adminRow()])
  await openPanel(gateway)
  await user.type(screen.getByLabelText(supportCopy.searchLabel), ` ${shopId} `)
  await user.click(screen.getByRole('button', { name: supportCopy.searchApply }))
  await waitFor(() => expect(gateway.listCalls.at(-1)?.search).toBe(shopId))
})

test('triage start moves a new inquiry to in progress and reloads', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway()
  await openPanel(gateway)
  await user.click(screen.getByTestId(`support-triage-start-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(1))
  expect(gateway.updates[0]).toMatchObject({
    inquiryId,
    to: 'in_progress',
    replyAr: null,
  })
  expect(gateway.updates[0]!.idempotencyKey).toMatch(
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  )
  expect(await screen.findByTestId('support-feedback')).toHaveTextContent(
    supportCopy.triageSaved,
  )
  // The panel reloads after a confirmed write.
  expect(gateway.listCalls.length).toBeGreaterThan(1)
})

test('an answered write requires a valid reply and keeps the draft on retryable failures', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway([adminRow({ status: 'in_progress' })])
  await openPanel(gateway)
  const field = screen.getByLabelText(supportCopy.replyField)
  await user.type(field, 'قصير')
  await user.click(screen.getByTestId(`support-triage-answer-${inquiryId}`))
  expect(screen.getByTestId('support-feedback')).toHaveTextContent(supportCopy.invalidReply)
  expect(gateway.updates).toHaveLength(0)

  gateway.failures = ['unavailable']
  await user.clear(field)
  await user.type(field, 'تم مراجعة الاستفسار وسيجيب فريق الاشتراك قريبًا.')
  await user.click(screen.getByTestId(`support-triage-answer-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(1))
  expect(screen.getByTestId('support-feedback')).toHaveTextContent(supportCopy.triageError)
  // The draft survives the retryable failure.
  expect(screen.getByLabelText(supportCopy.replyField)).toHaveValue(
    'تم مراجعة الاستفسار وسيجيب فريق الاشتراك قريبًا.',
  )

  await user.click(screen.getByTestId(`support-triage-answer-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(2))
  expect(gateway.updates[0]!.idempotencyKey).toBe(gateway.updates[1]!.idempotencyKey)
})

test('a definitive failure drops the key so the retry mints a new one', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway([adminRow({ status: 'in_progress' })])
  await openPanel(gateway)
  const field = screen.getByLabelText(supportCopy.replyField)
  await user.type(field, 'تم مراجعة الاستفسار وسيجيب فريق الاشتراك قريبًا.')
  gateway.failures = ['invalid_transition']
  await user.click(screen.getByTestId(`support-triage-answer-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(1))
  expect(screen.getByTestId('support-stale')).toBeInTheDocument()
  gateway.failures = []
  await user.click(screen.getByTestId(`support-triage-answer-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(2))
  expect(gateway.updates[0]!.idempotencyKey).not.toBe(gateway.updates[1]!.idempotencyKey)
})

test('closing an answered inquiry sends a null reply', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway([
    adminRow({ status: 'answered', replyAr: 'تم الرد على الاستفسار من الفريق.' }),
  ])
  gateway.setUpdateResult({ inquiryId, status: 'closed', replyAr: null, saved: true })
  await openPanel(gateway)
  await user.click(screen.getByTestId(`support-triage-close-${inquiryId}`))
  await waitFor(() => expect(gateway.updates).toHaveLength(1))
  expect(gateway.updates[0]).toMatchObject({ to: 'closed', replyAr: null })
})

test('access loss is reported to the shell', async () => {
  const onAccessLost = vi.fn()
  const gateway = new FakeSupportGateway([adminRow()])
  gateway.failures = ['access_lost']
  await openPanel(gateway, onAccessLost)
  await waitFor(() => expect(onAccessLost).toHaveBeenCalled())
})

test('load more pages with the keyset cursor', async () => {
  const user = userEvent.setup()
  const older = adminRow({
    id: 'e1200000-0000-4000-8000-000000000002',
    status: 'in_progress',
  })
  const gateway = new FakeSupportGateway([adminRow()])
  gateway.setPages([pageOf([adminRow()], true), pageOf([older])])
  await openPanel(gateway)
  await user.click(screen.getByTestId('support-load-more'))
  await waitFor(() => expect(screen.getByTestId(`support-row-${older.id}`)).toBeInTheDocument())
  expect(gateway.listCalls.at(-1)).toMatchObject({
    cursorAt: '2026-10-26T09:00:00.000Z',
    cursorId: 'e1000000-0000-4000-8000-000000000009',
  })
})

test('a failed page load keeps rows and offers a retry', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway()
  gateway.setPages([
    pageOf([adminRow()], true),
    emptyPage(),
  ])
  await openPanel(gateway)
  gateway.failures = ['unavailable']
  await user.click(screen.getByTestId('support-load-more'))
  await waitFor(() => expect(screen.getByRole('button', { name: supportCopy.retry })).toBeInTheDocument())
  expect(screen.getByTestId(`support-row-${inquiryId}`)).toBeInTheDocument()
  gateway.failures = []
  await user.click(screen.getByRole('button', { name: supportCopy.retry }))
  await waitFor(() =>
    expect(screen.queryByRole('button', { name: supportCopy.retry })).toBeNull(),
  )
})

test('a stale cursor shows the refresh notice instead of dropping content', async () => {
  const user = userEvent.setup()
  const gateway = new FakeSupportGateway()
  gateway.setPages([pageOf([adminRow()], true), emptyPage()])
  await openPanel(gateway)
  gateway.failures = ['stale']
  await user.click(screen.getByTestId('support-load-more'))
  await waitFor(() => expect(screen.getByTestId('support-stale')).toBeInTheDocument())
  expect(screen.getByTestId(`support-row-${inquiryId}`)).toBeInTheDocument()
})

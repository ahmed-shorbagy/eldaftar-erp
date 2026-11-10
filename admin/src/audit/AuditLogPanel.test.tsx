import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'
import { AuditError, type AuditEvent, type AuditGateway, type AuditPage, type AuditQuery } from './AuditGateway.ts'
import { auditActionLabel, auditCopy, auditFamilyLabel } from './copy.ts'

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null = 'light'
  read(): string | null {
    return this.value
  }
  write(value: string): void {
    this.value = value
  }
}

class StableAuth implements AdminAuthGateway {
  status: AdminAccess = 'admin'
  refresh = vi.fn(async (): Promise<void> => {})
  subscribe(): () => void {
    return () => {}
  }
  async signIn(): Promise<void> {}
  async signOut(): Promise<void> {}
}

const adminOne = 'a7000000-0000-4000-8000-0000000000a1'
const adminTwo = 'a7000000-0000-4000-8000-0000000000a2'
const shopId = 'a7100000-0000-4000-8000-000000000001'

function event(n: number, overrides: Partial<AuditEvent> = {}): AuditEvent {
  return {
    eventKey: `platform:a7200000-0000-4000-8000-${String(n).padStart(12, '0')}`,
    occurredAt: '2026-11-10T10:00:00.000Z',
    family: 'help',
    action: 'help_topic_created',
    actorUserId: adminOne,
    actorEmail: 'one@example.test',
    shopId: null,
    shopName: null,
    details: { titleAr: `موضوع ${n}`, published: true },
    ...overrides,
  }
}

function pageOf(rows: AuditEvent[], nextCursor: string | null = null): AuditPage {
  return {
    snapshotAt: '2026-11-10T10:00:00.000Z',
    pageSize: 25,
    rows,
    nextCursor,
    admins: [
      { userId: adminOne, email: 'one@example.test' },
      { userId: adminTwo, email: 'two@example.test' },
    ],
  }
}

function renderAudit(gateway: AuditGateway) {
  const auth = new StableAuth()
  window.history.replaceState(null, '', '/audit')
  render(
    <App
      supabaseStatus="ready"
      authGateway={auth}
      auditGateway={gateway}
      overviewGateway={null}
      subscriberGateway={null}
      contactGateway={null}
      appVersionGateway={null}
      helpGateway={null}
      supportGateway={null}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  return auth
}

test('lists admin actions with actor, time, summary and a shop link', async () => {
  const user = userEvent.setup()
  renderAudit({
    list: async () => pageOf([
      event(1, {
        eventKey: 'code:a7200000-0000-4000-8000-000000000009',
        family: 'codes',
        action: 'subscription_code_issued',
        actorEmail: 'two@example.test',
        shopId,
        shopName: 'متجر السجل',
        details: { durationDays: 30 },
      }),
      event(2),
    ]),
  })
  expect(await screen.findByRole('heading', { level: 2, name: auditCopy.title })).toBeInTheDocument()
  expect(screen.getByRole('link', { name: auditCopy.navLabel })).toHaveAttribute('aria-current', 'page')
  const list = screen.getByRole('list', { name: auditCopy.listLabel })
  const items = within(list).getAllByRole('listitem')
  expect(items).toHaveLength(2)
  expect(within(items[0]).getByRole('heading', { name: auditActionLabel.subscription_code_issued })).toBeInTheDocument()
  expect(within(items[0]).getByText('مدة الاشتراك 30 يومًا')).toBeInTheDocument()
  expect(within(items[0]).getByText('two@example.test')).toBeInTheDocument()
  const shopLink = within(items[0]).getByRole('link', { name: auditCopy.openShop('متجر السجل') })
  expect(shopLink).toHaveAttribute('href', `/subscribers/${shopId}`)
  expect(within(items[1]).getByText('«موضوع 2» — منشور')).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: auditCopy.loadMore })).not.toBeInTheDocument()

  await user.click(shopLink)
  expect(window.location.pathname).toBe(`/subscribers/${shopId}`)
})

test('family and admin filters reload from the first page', async () => {
  const user = userEvent.setup()
  const seen: AuditQuery[] = []
  renderAudit({
    list: async (query) => {
      seen.push(query)
      return pageOf([event(seen.length)])
    },
  })
  await screen.findByRole('list', { name: auditCopy.listLabel })
  await user.click(screen.getByRole('button', { name: auditFamilyLabel.support }))
  await waitFor(() => expect(seen.at(-1)).toEqual({ family: 'support', actorUserId: null, cursor: null }))
  expect(screen.getByRole('button', { name: auditFamilyLabel.support })).toHaveAttribute('aria-pressed', 'true')

  await user.click(screen.getByRole('combobox', { name: auditCopy.actorLabel }))
  await user.click(await screen.findByRole('option', { name: 'two@example.test' }))
  await waitFor(() => expect(seen.at(-1)).toEqual({ family: 'support', actorUserId: adminTwo, cursor: null }))
})

test('load more appends the next page and stops at the end', async () => {
  const user = userEvent.setup()
  const seen: AuditQuery[] = []
  renderAudit({
    list: async (query) => {
      seen.push(query)
      return query.cursor === null
        ? pageOf([event(1), event(2)], 'v1|2026-11-10 10:00:00.000000|platform:a7200000-0000-4000-8000-000000000002')
        : pageOf([event(3)])
    },
  })
  await screen.findByRole('list', { name: auditCopy.listLabel })
  await user.click(screen.getByRole('button', { name: auditCopy.loadMore }))
  await waitFor(() => {
    expect(within(screen.getByRole('list', { name: auditCopy.listLabel })).getAllByRole('listitem')).toHaveLength(3)
  })
  expect(seen.at(-1)?.cursor).toBe('v1|2026-11-10 10:00:00.000000|platform:a7200000-0000-4000-8000-000000000002')
  expect(screen.queryByRole('button', { name: auditCopy.loadMore })).not.toBeInTheDocument()
})

test('an empty history, a failure with retry, and access loss', async () => {
  const user = userEvent.setup()
  let mode: 'fail' | 'empty' = 'fail'
  renderAudit({
    list: async () => {
      if (mode === 'fail') throw new AuditError('unavailable')
      return pageOf([])
    },
  })
  expect(await screen.findByText(auditCopy.loadError)).toBeInTheDocument()
  mode = 'empty'
  await user.click(screen.getByRole('button', { name: auditCopy.retry }))
  expect(await screen.findByText(auditCopy.empty)).toBeInTheDocument()
})

test('access loss removes the history and rechecks the session', async () => {
  const auth = renderAudit({ list: async () => { throw new AuditError('unauthorized') } })
  await waitFor(() => expect(auth.refresh).toHaveBeenCalled())
  expect(screen.queryByRole('heading', { level: 2, name: auditCopy.title })).not.toBeInTheDocument()
})

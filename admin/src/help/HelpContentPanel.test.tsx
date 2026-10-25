import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { App } from '../App.tsx'
import type { AdminAccess, AdminAuthGateway } from '../auth/AdminAuthGateway.ts'
import { ThemeController } from '../theme/themeController.ts'
import type { ThemePreferenceStore } from '../theme/themePreference.ts'
import type { HelpGateway, HelpTopicRow, PlatformAnnouncementRow } from './HelpGateway.ts'
import { helpCopy } from './copy.ts'

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  value: string | null
  constructor(value: string | null = 'light') {
    this.value = value
  }
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

function gateway(overrides: Partial<HelpGateway> = {}): HelpGateway {
  return {
    async listCatalog() {
      return [] as HelpTopicRow[]
    },
    async upsertTopic(input) {
      return {
        id: input.id ?? 't1',
        titleAr: input.titleAr,
        sortOrder: input.sortOrder,
        published: input.published,
        articles: [],
        status: 'saved',
      }
    },
    async upsertArticle(input) {
      return {
        id: input.id ?? 'a1',
        topicId: input.topicId,
        titleAr: input.titleAr,
        bodyAr: input.bodyAr,
        sortOrder: input.sortOrder,
        published: input.published,
        status: 'saved',
      }
    },
    async getAnnouncement(): Promise<PlatformAnnouncementRow> {
      return { titleAr: '', bodyAr: '', linkUrl: null, published: false }
    },
    async setAnnouncement(input) {
      return { ...input, status: 'saved' }
    },
    ...overrides,
  }
}

async function openHelp(helpGateway: HelpGateway) {
  render(
    <App
      supabaseStatus="ready"
      authGateway={new StableAuth()}
      subscriberGateway={null}
      appVersionGateway={null}
      helpGateway={helpGateway}
      themeController={new ThemeController(new MemoryThemePreferenceStore())}
    />,
  )
  await userEvent.click(screen.getByRole('button', { name: helpCopy.navLabel }))
  expect(await screen.findByRole('heading', { name: helpCopy.title })).toBeInTheDocument()
}

test('publishes an announcement and creates a topic', async () => {
  const user = userEvent.setup()
  const sets: unknown[] = []
  const topics: unknown[] = []
  await openHelp(
    gateway({
      async setAnnouncement(input) {
        sets.push(input)
        return { ...input, status: 'saved' }
      },
      async upsertTopic(input) {
        topics.push(input)
        return {
          id: 't1',
          titleAr: input.titleAr,
          sortOrder: input.sortOrder,
          published: input.published,
          articles: [],
          status: 'saved',
        }
      },
      async listCatalog() {
        return topics.length === 0
          ? []
          : [
              {
                id: 't1',
                titleAr: 'موضوع',
                sortOrder: 1,
                published: true,
                articles: [],
              },
            ]
      },
    }),
  )
  await user.type(screen.getByLabelText(helpCopy.announcementTitleField), 'تنبيه')
  await user.type(screen.getByLabelText(helpCopy.announcementBody), 'نص')
  await user.click(screen.getByRole('button', { name: helpCopy.saveAnnouncement }))
  await waitFor(() => expect(sets).toHaveLength(1))
  expect(sets[0]).toMatchObject({
    titleAr: 'تنبيه',
    bodyAr: 'نص',
    published: true,
  })
  await user.type(screen.getAllByLabelText(helpCopy.topicTitle)[0]!, 'موضوع')
  await user.click(screen.getByRole('button', { name: helpCopy.addTopic }))
  await waitFor(() => expect(topics).toHaveLength(1))
  expect(await screen.findByText(helpCopy.saved)).toBeInTheDocument()
})

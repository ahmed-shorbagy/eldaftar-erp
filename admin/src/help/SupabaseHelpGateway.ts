import type { SupabaseClient } from '@supabase/supabase-js'
import {
  HelpError,
  parseAnnouncement,
  parseHelpCatalog,
  type HelpArticleRow,
  type HelpGateway,
  type HelpTopicRow,
  type HelpUpsertStatus,
  type PlatformAnnouncementRow,
} from './HelpGateway.ts'

export class SupabaseHelpGateway implements HelpGateway {
  private readonly client: SupabaseClient

  constructor(client: SupabaseClient) {
    this.client = client
  }

  async listCatalog(): Promise<HelpTopicRow[]> {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_list_help_catalog_v1')
      if (error) throw mapError(error.message)
      return parseHelpCatalog(data)
    })
  }

  async upsertTopic(input: {
    id: string | null
    titleAr: string
    sortOrder: number
    published: boolean
  }): Promise<HelpTopicRow & { status: HelpUpsertStatus }> {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_upsert_help_topic_v1', {
        p_id: input.id,
        p_title_ar: input.titleAr,
        p_sort_order: input.sortOrder,
        p_published: input.published,
      })
      if (error) throw mapError(error.message)
      if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        throw new HelpError('invalid')
      }
      const row = data as Record<string, unknown>
      const status = row.status
      if (status !== 'saved' && status !== 'unchanged') throw new HelpError('invalid')
      return {
        id: String(row.id),
        titleAr: String(row.title_ar),
        sortOrder: Number(row.sort_order),
        published: Boolean(row.published),
        articles: [],
        status,
      }
    })
  }

  async upsertArticle(input: {
    id: string | null
    topicId: string
    titleAr: string
    bodyAr: string
    sortOrder: number
    published: boolean
  }): Promise<HelpArticleRow & { status: HelpUpsertStatus; topicId: string }> {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_upsert_help_article_v1', {
        p_id: input.id,
        p_topic_id: input.topicId,
        p_title_ar: input.titleAr,
        p_body_ar: input.bodyAr,
        p_sort_order: input.sortOrder,
        p_published: input.published,
      })
      if (error) throw mapError(error.message)
      if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        throw new HelpError('invalid')
      }
      const row = data as Record<string, unknown>
      const status = row.status
      if (status !== 'saved' && status !== 'unchanged') throw new HelpError('invalid')
      return {
        id: String(row.id),
        topicId: String(row.topic_id),
        titleAr: String(row.title_ar),
        bodyAr: String(row.body_ar),
        sortOrder: Number(row.sort_order),
        published: Boolean(row.published),
        status,
      }
    })
  }

  async getAnnouncement(): Promise<PlatformAnnouncementRow> {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_get_platform_announcement_v1')
      if (error) throw mapError(error.message)
      return parseAnnouncement(data)
    })
  }

  async setAnnouncement(input: {
    titleAr: string
    bodyAr: string
    linkUrl: string | null
    published: boolean
  }): Promise<PlatformAnnouncementRow & { status: HelpUpsertStatus }> {
    return this.guarded(async () => {
      const { data, error } = await this.client.rpc('admin_set_platform_announcement_v1', {
        p_title_ar: input.titleAr,
        p_body_ar: input.bodyAr,
        p_link_url: input.linkUrl,
        p_published: input.published,
      })
      if (error) throw mapError(error.message)
      const base = parseAnnouncement(data)
      if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        throw new HelpError('invalid')
      }
      const status = (data as Record<string, unknown>).status
      if (status !== 'saved' && status !== 'unchanged') throw new HelpError('invalid')
      return { ...base, status }
    })
  }

  private async guarded<T>(run: () => Promise<T>): Promise<T> {
    const before = await this.client.auth.getSession()
    const userId = before.data.session?.user.id
    if (!userId) throw new HelpError('unauthorized')
    const result = await run()
    const after = await this.client.auth.getSession()
    if (after.data.session?.user.id !== userId) {
      throw new HelpError('unauthorized')
    }
    return result
  }
}

function mapError(message: string | undefined): HelpError {
  const text = (message ?? '').toLowerCase()
  if (
    text.includes('forbidden')
    || text.includes('unauthenticated')
    || text.includes('session_expired')
    || text.includes('42501')
  ) {
    return new HelpError('unauthorized')
  }
  if (text.includes('invalid') || text.includes('22023')) {
    return new HelpError('invalid')
  }
  return new HelpError('unavailable')
}

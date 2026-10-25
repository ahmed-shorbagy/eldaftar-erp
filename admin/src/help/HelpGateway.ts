export type HelpArticleRow = {
  id: string
  titleAr: string
  bodyAr: string
  sortOrder: number
  published: boolean
}

export type HelpTopicRow = {
  id: string
  titleAr: string
  sortOrder: number
  published: boolean
  articles: HelpArticleRow[]
}

export type PlatformAnnouncementRow = {
  titleAr: string
  bodyAr: string
  linkUrl: string | null
  published: boolean
}

export type HelpUpsertStatus = 'saved' | 'unchanged'

export type HelpGateway = {
  listCatalog(): Promise<HelpTopicRow[]>
  upsertTopic(input: {
    id: string | null
    titleAr: string
    sortOrder: number
    published: boolean
  }): Promise<HelpTopicRow & { status: HelpUpsertStatus }>
  upsertArticle(input: {
    id: string | null
    topicId: string
    titleAr: string
    bodyAr: string
    sortOrder: number
    published: boolean
  }): Promise<HelpArticleRow & { status: HelpUpsertStatus; topicId: string }>
  getAnnouncement(): Promise<PlatformAnnouncementRow>
  setAnnouncement(input: {
    titleAr: string
    bodyAr: string
    linkUrl: string | null
    published: boolean
  }): Promise<PlatformAnnouncementRow & { status: HelpUpsertStatus }>
}

export class HelpError extends Error {
  readonly code: 'unauthorized' | 'invalid' | 'unavailable'

  constructor(code: 'unauthorized' | 'invalid' | 'unavailable') {
    super(code)
    this.code = code
  }
}

export function parseHelpCatalog(value: unknown): HelpTopicRow[] {
  if (!Array.isArray(value)) throw new HelpError('invalid')
  return value.map(parseTopic)
}

function parseTopic(value: unknown): HelpTopicRow {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HelpError('invalid')
  }
  const row = value as Record<string, unknown>
  if (typeof row.id !== 'string' || typeof row.title_ar !== 'string') {
    throw new HelpError('invalid')
  }
  if (typeof row.sort_order !== 'number' || typeof row.published !== 'boolean') {
    throw new HelpError('invalid')
  }
  if (!Array.isArray(row.articles)) throw new HelpError('invalid')
  return {
    id: row.id,
    titleAr: row.title_ar,
    sortOrder: row.sort_order,
    published: row.published,
    articles: row.articles.map(parseArticle),
  }
}

function parseArticle(value: unknown): HelpArticleRow {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HelpError('invalid')
  }
  const row = value as Record<string, unknown>
  if (typeof row.id !== 'string' || typeof row.title_ar !== 'string') {
    throw new HelpError('invalid')
  }
  if (typeof row.body_ar !== 'string') throw new HelpError('invalid')
  if (typeof row.sort_order !== 'number' || typeof row.published !== 'boolean') {
    throw new HelpError('invalid')
  }
  return {
    id: row.id,
    titleAr: row.title_ar,
    bodyAr: row.body_ar,
    sortOrder: row.sort_order,
    published: row.published,
  }
}

export function parseAnnouncement(value: unknown): PlatformAnnouncementRow {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HelpError('invalid')
  }
  const row = value as Record<string, unknown>
  if (typeof row.title_ar !== 'string' || typeof row.body_ar !== 'string') {
    throw new HelpError('invalid')
  }
  if (typeof row.published !== 'boolean') throw new HelpError('invalid')
  const link = row.link_url
  if (link !== null && typeof link !== 'string') throw new HelpError('invalid')
  return {
    titleAr: row.title_ar,
    bodyAr: row.body_ar,
    linkUrl: link,
    published: row.published,
  }
}

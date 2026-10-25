export type AppVersionPlatform = 'android' | 'ios' | 'windows'

export type AppVersionPolicyRow = {
  platform: AppVersionPlatform
  minVersion: string | null
  messageAr: string
  updateUrl: string | null
}

export type AppVersionSetInput = {
  platform: AppVersionPlatform
  minVersion: string | null
  messageAr: string
  updateUrl: string | null
}

export type AppVersionSetResult = AppVersionPolicyRow & {
  status: 'saved' | 'unchanged'
}

export type AppVersionGateway = {
  list(): Promise<AppVersionPolicyRow[]>
  set(input: AppVersionSetInput): Promise<AppVersionSetResult>
}

export class AppVersionError extends Error {
  readonly code: 'unauthorized' | 'invalid' | 'unavailable'

  constructor(code: 'unauthorized' | 'invalid' | 'unavailable') {
    super(code)
    this.code = code
  }
}

export function parseAppVersionPolicyList(value: unknown): AppVersionPolicyRow[] {
  if (!Array.isArray(value)) throw new AppVersionError('invalid')
  return value.map(parseRow)
}

function parseRow(value: unknown): AppVersionPolicyRow {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new AppVersionError('invalid')
  }
  const row = value as Record<string, unknown>
  const platform = row.platform
  if (platform !== 'android' && platform !== 'ios' && platform !== 'windows') {
    throw new AppVersionError('invalid')
  }
  const minVersion = row.min_version
  if (minVersion !== null && typeof minVersion !== 'string') {
    throw new AppVersionError('invalid')
  }
  if (typeof minVersion === 'string' && !/^\d+\.\d+\.\d+$/.test(minVersion)) {
    throw new AppVersionError('invalid')
  }
  const messageAr = row.message_ar
  if (typeof messageAr !== 'string') throw new AppVersionError('invalid')
  const updateUrl = row.update_url
  if (updateUrl !== null && typeof updateUrl !== 'string') {
    throw new AppVersionError('invalid')
  }
  return {
    platform,
    minVersion,
    messageAr,
    updateUrl,
  }
}

export function parseAppVersionSetResult(value: unknown): AppVersionSetResult {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new AppVersionError('invalid')
  }
  const row = value as Record<string, unknown>
  const status = row.status
  if (status !== 'saved' && status !== 'unchanged') {
    throw new AppVersionError('invalid')
  }
  const base = parseRow({
    platform: row.platform,
    min_version: row.min_version,
    message_ar: row.message_ar,
    update_url: row.update_url,
  })
  return { ...base, status }
}

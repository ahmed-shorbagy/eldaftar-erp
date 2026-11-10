import { parseExactCount } from '../subscribers/subscriptionFormat.ts'

export type OverviewPlatform = 'android' | 'ios' | 'windows'

/** Every count is an exact decimal string from the server (ADR 0045). */
export interface AdminOverview {
  snapshotAt: string
  subscriptions: { all: string; active: string; pending: string; expired: string }
  expiring: { within3Days: string; within7Days: string; within30Days: string }
  registrations: { last7Days: string; last30Days: string }
  support: { new: string; inProgress: string; answered: string }
  appVersions: Array<{ platform: OverviewPlatform; minVersion: string | null }>
  announcementPublished: boolean
}

export interface OverviewGateway {
  get(): Promise<AdminOverview>
}

export type OverviewErrorCode = 'unauthorized' | 'invalid' | 'unavailable'

export class OverviewError extends Error {
  readonly code: OverviewErrorCode

  constructor(code: OverviewErrorCode) {
    super(code)
    this.name = 'OverviewError'
    this.code = code
  }
}

const platforms: OverviewPlatform[] = ['android', 'ios', 'windows']
const versionPattern = /^[0-9]+\.[0-9]+\.[0-9]+$/

function record(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new OverviewError('invalid')
  }
  const actual = Object.keys(value).sort()
  const expected = [...keys].sort()
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new OverviewError('invalid')
  }
  return value as Record<string, unknown>
}

function count(value: unknown): string {
  if (typeof value !== 'string') throw new OverviewError('invalid')
  try {
    parseExactCount(value)
  } catch {
    throw new OverviewError('invalid')
  }
  return value
}

/** Strict parser: unknown keys, missing keys or malformed values are rejected. */
export function parseAdminOverview(input: unknown): AdminOverview {
  const top = record(input, [
    'snapshot_at',
    'subscriptions',
    'expiring',
    'registrations',
    'support',
    'app_versions',
    'announcement_published',
  ])
  if (typeof top.snapshot_at !== 'string' || Number.isNaN(Date.parse(top.snapshot_at))) {
    throw new OverviewError('invalid')
  }
  const subscriptions = record(top.subscriptions, ['all', 'active', 'pending', 'expired'])
  const expiring = record(top.expiring, ['within_3_days', 'within_7_days', 'within_30_days'])
  const registrations = record(top.registrations, ['last_7_days', 'last_30_days'])
  const support = record(top.support, ['new', 'in_progress', 'answered'])
  if (!Array.isArray(top.app_versions) || top.app_versions.length !== platforms.length) {
    throw new OverviewError('invalid')
  }
  const appVersions = top.app_versions.map((entry, index) => {
    const row = record(entry, ['platform', 'min_version'])
    if (row.platform !== platforms[index]) throw new OverviewError('invalid')
    if (row.min_version !== null && (typeof row.min_version !== 'string' || !versionPattern.test(row.min_version))) {
      throw new OverviewError('invalid')
    }
    return { platform: platforms[index], minVersion: row.min_version as string | null }
  })
  if (typeof top.announcement_published !== 'boolean') throw new OverviewError('invalid')
  return {
    snapshotAt: top.snapshot_at,
    subscriptions: {
      all: count(subscriptions.all),
      active: count(subscriptions.active),
      pending: count(subscriptions.pending),
      expired: count(subscriptions.expired),
    },
    expiring: {
      within3Days: count(expiring.within_3_days),
      within7Days: count(expiring.within_7_days),
      within30Days: count(expiring.within_30_days),
    },
    registrations: {
      last7Days: count(registrations.last_7_days),
      last30Days: count(registrations.last_30_days),
    },
    support: {
      new: count(support.new),
      inProgress: count(support.in_progress),
      answered: count(support.answered),
    },
    appVersions,
    announcementPublished: top.announcement_published,
  }
}

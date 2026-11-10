import { expect, test } from 'vitest'
import { OverviewError, parseAdminOverview } from './OverviewGateway.ts'
import { mapOverviewError } from './SupabaseOverviewGateway.ts'

function overviewPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    snapshot_at: '2026-11-10T10:00:00.000Z',
    subscriptions: { all: '12', active: '5', pending: '4', expired: '3' },
    expiring: { within_3_days: '1', within_7_days: '2', within_30_days: '4' },
    registrations: { last_7_days: '2', last_30_days: '6' },
    support: { new: '3', in_progress: '1', answered: '0' },
    app_versions: [
      { platform: 'android', min_version: '1.2.0' },
      { platform: 'ios', min_version: null },
      { platform: 'windows', min_version: null },
    ],
    announcement_published: true,
    ...overrides,
  }
}

test('parses every figure as an exact string', () => {
  const overview = parseAdminOverview(overviewPayload({
    subscriptions: { all: '90071992547409931', active: '5', pending: '4', expired: '3' },
  }))
  expect(overview.subscriptions.all).toBe('90071992547409931')
  expect(overview.expiring).toEqual({ within3Days: '1', within7Days: '2', within30Days: '4' })
  expect(overview.support).toEqual({ new: '3', inProgress: '1', answered: '0' })
  expect(overview.appVersions).toEqual([
    { platform: 'android', minVersion: '1.2.0' },
    { platform: 'ios', minVersion: null },
    { platform: 'windows', minVersion: null },
  ])
  expect(overview.announcementPublished).toBe(true)
})

test.each([
  ['an extra top-level key', overviewPayload({ shop_names: [] })],
  ['a missing section', (() => { const p = overviewPayload(); delete p.support; return p })()],
  ['a numeric count', overviewPayload({ registrations: { last_7_days: 2, last_30_days: '6' } })],
  ['a negative count', overviewPayload({ expiring: { within_3_days: '-1', within_7_days: '2', within_30_days: '4' } })],
  ['a leading-zero count', overviewPayload({ support: { new: '03', in_progress: '1', answered: '0' } })],
  ['platforms out of order', overviewPayload({ app_versions: [
    { platform: 'ios', min_version: null },
    { platform: 'android', min_version: null },
    { platform: 'windows', min_version: null },
  ] })],
  ['a malformed version', overviewPayload({ app_versions: [
    { platform: 'android', min_version: '1.2' },
    { platform: 'ios', min_version: null },
    { platform: 'windows', min_version: null },
  ] })],
  ['a bad snapshot time', overviewPayload({ snapshot_at: 'yesterday' })],
  ['a non-boolean announcement', overviewPayload({ announcement_published: 'true' })],
])('rejects %s', (_label, payload) => {
  expect(() => parseAdminOverview(payload)).toThrow(OverviewError)
})

test('maps server refusals to access loss and anything else to unavailable', () => {
  expect(mapOverviewError('forbidden').code).toBe('unauthorized')
  expect(mapOverviewError('session_expired').code).toBe('unauthorized')
  expect(mapOverviewError('unauthenticated').code).toBe('unauthorized')
  expect(mapOverviewError('network timeout').code).toBe('unavailable')
  expect(mapOverviewError(undefined).code).toBe('unavailable')
})

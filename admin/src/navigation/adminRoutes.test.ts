import { expect, test } from 'vitest'
import {
  defaultAdminRoute,
  formatAdminPath,
  parseAdminPath,
  subscribersRoute,
  type AdminRoute,
} from './adminRoutes.ts'

const shopId = 'a1100000-0000-4000-8000-000000000001'

function roundTrip(route: AdminRoute): AdminRoute | null {
  const formatted = formatAdminPath(route)
  const [path, query = ''] = formatted.split('?')
  return parseAdminPath(path, query ? `?${query}` : '')
}

test('every area round-trips through its path', () => {
  for (const route of [
    { area: 'overview' },
    subscribersRoute(),
    subscribersRoute('all', shopId),
    subscribersRoute('expiring_7'),
    subscribersRoute('expired', shopId),
    { area: 'appVersion' },
    { area: 'help' },
    { area: 'support' },
    { area: 'audit' },
  ] as AdminRoute[]) {
    expect(roundTrip(route)).toEqual(route)
  }
})

test('the root is the overview and the subscriber list keeps its filter in the query', () => {
  expect(defaultAdminRoute).toEqual({ area: 'overview' })
  expect(parseAdminPath('/')).toEqual({ area: 'overview' })
  expect(parseAdminPath('')).toEqual({ area: 'overview' })
  expect(parseAdminPath('/overview')).toEqual({ area: 'overview' })
  expect(formatAdminPath({ area: 'overview' })).toBe('/')
  expect(formatAdminPath(subscribersRoute('expiring_3'))).toBe('/subscribers?status=expiring_3')
  expect(formatAdminPath(subscribersRoute())).toBe('/subscribers')
  expect(parseAdminPath('/subscribers', '?status=pending')).toEqual(subscribersRoute('pending'))
})

test('an unknown status falls back to all instead of failing', () => {
  expect(parseAdminPath('/subscribers', '?status=expiring_8')).toEqual(subscribersRoute())
  expect(parseAdminPath('/subscribers/', '')).toEqual(subscribersRoute())
  expect(parseAdminPath('/help/')).toEqual({ area: 'help' })
})

test('subscriber detail ids must be UUIDs and are normalized to lower case', () => {
  expect(parseAdminPath(`/subscribers/${shopId.toUpperCase()}`)).toEqual(subscribersRoute('all', shopId))
  expect(parseAdminPath('/subscribers/not-a-shop')).toBeNull()
  expect(parseAdminPath('/subscribers/%E0%A4%A')).toBeNull()
})

test('unknown or over-long paths are rejected', () => {
  expect(parseAdminPath('/settings')).toBeNull()
  expect(parseAdminPath('/help/extra')).toBeNull()
  expect(parseAdminPath('/overview/extra')).toBeNull()
  expect(parseAdminPath(`/subscribers/${shopId}/codes`)).toBeNull()
})

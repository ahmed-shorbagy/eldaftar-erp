import {
  isSubscriberStatusFilter,
  type SubscriberStatusFilter,
} from '../subscribers/SubscriberDirectoryGateway.ts'

/**
 * URL routes for the platform-admin client. History-API paths keep refresh,
 * back/forward and shared links working. Hosting must rewrite unknown paths to
 * `index.html` (single-page fallback); Vite's dev server already does.
 */
export type AdminArea = 'overview' | 'subscribers' | 'appVersion' | 'help' | 'support'

export type AdminRoute =
  | { area: 'overview' }
  | { area: 'subscribers'; shopId: string | null; status: SubscriberStatusFilter }
  | { area: 'appVersion' }
  | { area: 'help' }
  | { area: 'support' }

export const defaultAdminRoute: AdminRoute = { area: 'overview' }

export function subscribersRoute(
  status: SubscriberStatusFilter = 'all',
  shopId: string | null = null,
): AdminRoute {
  return { area: 'subscribers', shopId, status }
}

const areaSegments: Record<AdminArea, string> = {
  overview: 'overview',
  subscribers: 'subscribers',
  appVersion: 'app-version',
  help: 'help',
  support: 'support',
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Returns the route for a pathname and query string, or null when the path is
 * unknown. An unknown `status` value falls back to `all`.
 */
export function parseAdminPath(pathname: string, search = ''): AdminRoute | null {
  const segments = pathname.split('/').filter((segment) => segment.length > 0)
  if (segments.length === 0) return defaultAdminRoute
  const [first, second, ...rest] = segments
  if (rest.length > 0) return null
  if (first === areaSegments.subscribers) {
    const requested = new URLSearchParams(search).get('status')
    const status = isSubscriberStatusFilter(requested) ? requested : 'all'
    if (second === undefined) return subscribersRoute(status)
    let decoded: string
    try {
      decoded = decodeURIComponent(second)
    } catch {
      return null
    }
    return uuidPattern.test(decoded) ? subscribersRoute(status, decoded.toLowerCase()) : null
  }
  if (second !== undefined) return null
  if (first === areaSegments.overview) return { area: 'overview' }
  if (first === areaSegments.appVersion) return { area: 'appVersion' }
  if (first === areaSegments.help) return { area: 'help' }
  if (first === areaSegments.support) return { area: 'support' }
  return null
}

/** Path plus query string for a route. */
export function formatAdminPath(route: AdminRoute): string {
  if (route.area === 'overview') return '/'
  if (route.area === 'subscribers') {
    const base = route.shopId === null
      ? `/${areaSegments.subscribers}`
      : `/${areaSegments.subscribers}/${encodeURIComponent(route.shopId)}`
    return route.status === 'all' ? base : `${base}?status=${route.status}`
  }
  return `/${areaSegments[route.area]}`
}

export function sameAdminRoute(a: AdminRoute, b: AdminRoute): boolean {
  return formatAdminPath(a) === formatAdminPath(b)
}

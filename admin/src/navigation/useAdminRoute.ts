import { useCallback, useEffect, useState } from 'react'
import {
  defaultAdminRoute,
  formatAdminPath,
  parseAdminPath,
  sameAdminRoute,
  type AdminRoute,
} from './adminRoutes.ts'

function currentLocation(): string {
  return window.location.pathname + window.location.search
}

function readRoute(): AdminRoute {
  return parseAdminPath(window.location.pathname, window.location.search) ?? defaultAdminRoute
}

/**
 * Keeps the current admin route in sync with the browser URL. Unknown paths
 * are replaced with the default route so the address bar never shows a page
 * that does not exist.
 */
export function useAdminRoute(): {
  route: AdminRoute
  navigate: (next: AdminRoute, options?: { replace?: boolean }) => void
} {
  const [route, setRoute] = useState<AdminRoute>(readRoute)

  useEffect(() => {
    const canonical = formatAdminPath(readRoute())
    if (currentLocation() !== canonical) {
      window.history.replaceState(window.history.state, '', canonical)
    }
    const onPopState = () => {
      const next = parseAdminPath(window.location.pathname, window.location.search)
      if (next === null) {
        window.history.replaceState(window.history.state, '', formatAdminPath(defaultAdminRoute))
      }
      setRoute(next ?? defaultAdminRoute)
    }
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [])

  const navigate = useCallback((next: AdminRoute, options?: { replace?: boolean }) => {
    const path = formatAdminPath(next)
    if (currentLocation() !== path) {
      if (options?.replace) window.history.replaceState(null, '', path)
      else window.history.pushState(null, '', path)
    }
    setRoute((current) => (sameAdminRoute(current, next) ? current : next))
  }, [])

  return { route, navigate }
}

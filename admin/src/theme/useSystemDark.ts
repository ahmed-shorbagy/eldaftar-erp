import { useEffect, useState } from 'react'

const darkSchemeQuery = '(prefers-color-scheme: dark)'

function systemPrefersDark(): boolean {
  if (typeof window.matchMedia !== 'function') {
    return false
  }
  return window.matchMedia(darkSchemeQuery).matches
}

export function useSystemDark(): boolean {
  const [dark, setDark] = useState(systemPrefersDark)

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') {
      return
    }
    const media = window.matchMedia(darkSchemeQuery)
    const onChange = () => {
      setDark(media.matches)
    }
    media.addEventListener('change', onChange)
    return () => {
      media.removeEventListener('change', onChange)
    }
  }, [])

  return dark
}

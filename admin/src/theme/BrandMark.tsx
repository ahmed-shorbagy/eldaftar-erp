import { useTheme } from '@mui/material/styles'

/** Open ledger, gold diamond and accounts; matches the shared SVG geometry. */
export function BrandMark({ size = 28 }: { size?: number }) {
  const { palette } = useTheme()
  const gold = palette.primary.main
  const surface = palette.background.default
  return <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden="true" data-testid="brand-mark">
    <rect x="1" y="1" width="62" height="62" rx="14" fill={surface} stroke={gold} strokeWidth="2" />
    <path d="M8 24 30 30 30 55 8 49Z" fill={gold} />
    <path d="M34 30 56 24 56 49 34 55Z" fill="none" stroke={gold} strokeWidth="2" strokeLinejoin="round" />
    <path d="m13 33 11 3m-11 3 11 3m-11 3 11 3" stroke={surface} strokeWidth="2" strokeLinecap="round" />
    <path d="M39 42h3v7h-3zM44 37h3v10h-3zM49 32h3v13h-3z" fill={gold} />
    <path d="m24 13 4-5h8l4 5-8 10zM24 13h16M28 8l4 15 4-15" fill="none" stroke={gold} strokeWidth="2" strokeLinejoin="round" />
  </svg>
}

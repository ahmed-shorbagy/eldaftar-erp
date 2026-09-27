import { tokens } from './tokens.ts'

/** Open ledger and gold ingot. Geometry matches `public/favicon.svg`. */
export function BrandMark({ size = 28 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      aria-hidden="true"
      data-testid="brand-mark"
    >
      <rect width="32" height="32" rx="8" fill={tokens.seed} />
      <path d="M6.5 10.2 L15 12.2 L15 23.2 L6.5 21.2 Z" fill={tokens.lightSurface} />
      <path d="M17 12.2 L25.5 10.2 L25.5 21.2 L17 23.2 Z" fill={tokens.lightSurface} />
      <rect x="15" y="12.2" width="2" height="11" fill={tokens.darkPrimaryContainer} />
      <path
        d="M8.3 15 H13.2"
        stroke={tokens.seed}
        strokeWidth="1.25"
        strokeLinecap="round"
      />
      <path
        d="M8.4 17.6 H12.4"
        stroke={tokens.seed}
        strokeWidth="1.25"
        strokeLinecap="round"
      />
      <rect x="18.7" y="15.4" width="5" height="3.1" rx="0.7" fill={tokens.brandGold} />
    </svg>
  )
}

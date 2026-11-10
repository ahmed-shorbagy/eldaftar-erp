import List from '@mui/material/List'
import ListItemButton from '@mui/material/ListItemButton'
import ListItemIcon from '@mui/material/ListItemIcon'
import ListItemText from '@mui/material/ListItemText'
import type { MouseEvent, ReactNode } from 'react'
import { tokens } from '../theme/tokens.ts'
import { shellCopy } from './copy.ts'

export interface AdminNavItem {
  key: string
  label: string
  href: string
  icon: ReactNode
  selected: boolean
}

/**
 * Section links shared by the desktop rail and the phone drawer. Items are real
 * links so a modified click (new tab/window) keeps working; a plain click is
 * handled in-app.
 */
export function AdminNavigation({
  items,
  onSelect,
}: {
  items: AdminNavItem[]
  onSelect: (key: string) => void
}) {
  const handleClick = (key: string) => (event: MouseEvent<HTMLAnchorElement>) => {
    if (
      event.defaultPrevented
      || event.button !== 0
      || event.metaKey
      || event.ctrlKey
      || event.shiftKey
      || event.altKey
    ) {
      return
    }
    event.preventDefault()
    onSelect(key)
  }

  return (
    <nav aria-label={shellCopy.navigationLabel}>
      <List disablePadding sx={{ display: 'grid', gap: 0.5 }}>
        {items.map((item) => (
          <li key={item.key}>
            <ListItemButton
              component="a"
              href={item.href}
              selected={item.selected}
              aria-current={item.selected ? 'page' : undefined}
              onClick={handleClick(item.key)}
              sx={{
                minHeight: tokens.minControlSize,
                borderRadius: `${tokens.fieldRadius}px`,
                px: 1.5,
                gap: 1.5,
                color: 'text.primary',
                '&.Mui-selected': { fontWeight: 700 },
                '&.Mui-focusVisible': {
                  outline: '2px solid',
                  outlineColor: 'primary.main',
                  outlineOffset: -2,
                },
              }}
            >
              <ListItemIcon sx={{ minWidth: 0, color: item.selected ? 'primary.main' : 'inherit' }}>
                {item.icon}
              </ListItemIcon>
              <ListItemText
                primary={item.label}
                slotProps={{
                  primary: {
                    sx: {
                      fontWeight: item.selected ? 700 : 500,
                      textAlign: 'start',
                      lineHeight: 1.5,
                    },
                  },
                }}
              />
            </ListItemButton>
          </li>
        ))}
      </List>
    </nav>
  )
}

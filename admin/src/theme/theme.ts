import { createTheme } from '@mui/material/styles'
import { tokens } from './tokens.ts'
import type { ResolvedTheme } from './themePreference.ts'

export function createAppTheme(mode: ResolvedTheme) {
  const isLight = mode === 'light'
  const surface = isLight ? tokens.lightSurface : tokens.darkSurface
  const onSurface = isLight ? tokens.lightOnSurface : tokens.darkOnSurface

  return createTheme({
    direction: 'rtl',
    breakpoints: {
      values: {
        xs: 0,
        sm: 600,
        md: tokens.wideBreakpoint,
        lg: 1200,
        xl: 1536,
      },
    },
    palette: {
      mode,
      primary: { main: tokens.seed },
      background: {
        default: surface,
        paper: surface,
      },
      text: {
        primary: onSurface,
      },
      divider: isLight ? tokens.lightOutline : tokens.darkOutline,
    },
    typography: {
      fontFamily: tokens.fontFamily,
    },
    components: {
      MuiCssBaseline: {
        styleOverrides: {
          html: { colorScheme: mode },
          body: {
            direction: 'rtl',
            backgroundColor: surface,
            color: onSurface,
          },
        },
      },
      MuiAppBar: {
        styleOverrides: {
          root: {
            backgroundImage: 'none',
            boxShadow: 'none',
          },
        },
      },
    },
  })
}

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
      primary: { main: isLight ? tokens.lightAccent : tokens.darkAccent, contrastText: isLight ? tokens.lightSurface : tokens.darkSurface },
      success: { main: isLight ? tokens.lightSuccess : tokens.darkSuccess },
      background: {
        default: surface,
        paper: isLight ? surface : tokens.darkCard,
      },
      text: {
        primary: onSurface,
      },
      divider: isLight ? tokens.lightOutline : tokens.darkOutline,
    },
    typography: {
      fontFamily: tokens.fontFamily,
      allVariants: { letterSpacing: 0, fontVariantNumeric: 'tabular-nums', lineHeight: 1.5 },
      h5: { fontSize: tokens.figureSize, fontWeight: 700 },
      h6: { fontSize: tokens.titleSize, fontWeight: 700 },
      subtitle1: { fontSize: tokens.bodySize, fontWeight: 700 },
      subtitle2: { fontSize: tokens.detailSize, fontWeight: 600 },
      body1: { fontSize: tokens.bodySize },
      body2: { fontSize: tokens.detailSize },
      caption: { fontSize: tokens.labelSize },
      button: { fontSize: tokens.detailSize, fontWeight: 600, textTransform: 'none' },
    },
    components: {
      MuiButton: {
        styleOverrides: { root: { minHeight: tokens.minControlSize, borderRadius: tokens.fieldRadius } },
      },
      MuiOutlinedInput: {
        styleOverrides: {
          root: { borderRadius: tokens.fieldRadius, minHeight: tokens.minControlSize, fontSize: tokens.bodySize },
          input: { padding: '16px', fontVariantNumeric: 'tabular-nums' },
        },
      },
      MuiFormHelperText: { styleOverrides: { root: { fontSize: tokens.labelSize, lineHeight: 1.5 } } },
      MuiDialog: { styleOverrides: { paper: { borderRadius: tokens.cardRadius, backgroundImage: 'none' } } },
      MuiIconButton: {
        styleOverrides: {
          root: { minWidth: tokens.minControlSize, minHeight: tokens.minControlSize },
        },
      },
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

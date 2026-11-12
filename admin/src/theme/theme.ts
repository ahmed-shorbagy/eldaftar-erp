import { alpha, createTheme } from '@mui/material/styles'
import { tokens } from './tokens.ts'
import type { ResolvedTheme } from './themePreference.ts'

export function createAppTheme(mode: ResolvedTheme) {
  const isLight = mode === 'light'
  const surface = isLight ? tokens.lightSurface : tokens.darkSurface
  const onSurface = isLight ? tokens.lightOnSurface : tokens.darkOnSurface
  const tableBorder = isLight ? tokens.lightTableBorder : tokens.darkTableBorder

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
      // M1: neutral notices use the brand accent, never MUI's default blue.
      info: { main: isLight ? tokens.lightAccent : tokens.darkAccent },
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
      // M1 messaging: inline notices match the Flutter AppBanner — a light
      // tint of the tone over the surface, a tone border, field radius, a
      // tone icon and 600-weight text in the main text colour.
      MuiAlert: {
        styleOverrides: {
          root: ({ theme, ownerState }) => {
            const tone = theme.palette[ownerState.severity ?? 'success'].main
            if (ownerState.variant === 'filled' || ownerState.variant === 'outlined') {
              return { borderRadius: tokens.fieldRadius }
            }
            return {
              borderRadius: tokens.fieldRadius,
              border: `1px solid ${alpha(tone, 0.55)}`,
              backgroundColor: alpha(tone, isLight ? 0.11 : 0.18),
              color: onSurface,
              alignItems: 'center',
              '& .MuiAlert-icon': { color: tone, opacity: 1 },
            }
          },
          message: { fontSize: tokens.detailSize, fontWeight: 600, lineHeight: 1.5 },
          action: { paddingTop: 0, alignItems: 'center' },
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
          // No `direction` here: stylis-plugin-rtl mirrors `direction: rtl`
          // into `ltr`, which made portaled dialogs and drawers lay out LTR.
          // The `dir="rtl"` attribute on <html> sets the direction instead.
          body: {
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
      MuiTable: {
        styleOverrides: {
          root: {
            borderCollapse: 'separate',
            borderSpacing: 0,
            border: `1px solid ${tableBorder}`,
          },
        },
      },
      MuiTableCell: {
        styleOverrides: {
          root: {
            borderColor: tableBorder,
            padding: '10px 12px',
          },
        },
      },
    },
  })
}

import { expect, test } from 'vitest'
import { createAppTheme } from './theme.ts'
import { tokens } from './tokens.ts'

function channel(value: number): number {
  const scaled = value / 255
  return scaled <= 0.03928
    ? scaled / 12.92
    : ((scaled + 0.055) / 1.055) ** 2.4
}

function luminance(hex: string): number {
  const color = Number.parseInt(hex.slice(1), 16)
  const red = channel((color >> 16) & 255)
  const green = channel((color >> 8) & 255)
  const blue = channel(color & 255)
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

function contrast(foreground: string, background: string): number {
  const lighter = Math.max(luminance(foreground), luminance(background))
  const darker = Math.min(luminance(foreground), luminance(background))
  return (lighter + 0.05) / (darker + 0.05)
}

test('light and dark themes stay right-to-left and readable', () => {
  const light = createAppTheme('light')
  const dark = createAppTheme('dark')

  expect(light.direction).toBe('rtl')
  expect(dark.direction).toBe('rtl')
  expect(light.palette.mode).toBe('light')
  expect(dark.palette.mode).toBe('dark')
  expect(light.palette.primary.main).toBe(tokens.seed)
  expect(light.palette.text.primary).toBe(tokens.lightOnSurface)
  expect(light.palette.background.default).toBe(tokens.lightSurface)
  expect(dark.palette.text.primary).toBe(tokens.darkOnSurface)
  expect(dark.palette.background.default).toBe(tokens.darkSurface)
  expect(light.breakpoints.values.md).toBe(tokens.wideBreakpoint)
  expect(contrast(tokens.lightOnSurface, tokens.lightSurface)).toBeGreaterThanOrEqual(
    4.5,
  )
  expect(contrast(tokens.darkOnSurface, tokens.darkSurface)).toBeGreaterThanOrEqual(
    4.5,
  )
  expect(
    contrast(tokens.lightOnPrimaryContainer, tokens.lightPrimaryContainer),
  ).toBeGreaterThanOrEqual(4.5)
  expect(
    contrast(tokens.darkOnPrimaryContainer, tokens.darkPrimaryContainer),
  ).toBeGreaterThanOrEqual(4.5)
})

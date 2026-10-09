import { argbFromRgb, Hct } from '@material/material-color-utilities'
import { describe, expect, it } from 'vitest'

import { ACCENT_L, ACCENT_MAX_C, MONOCHROME_ACCENT, oklchFromArgb, paletteFromPixels } from './wallpaper-palette'

const fill = (n: number, rgb: [number, number, number]) => Array.from({ length: n }, () => argbFromRgb(...rgb))
const rgbOf = (hex: string) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16))

describe('wallpaper palette (Material Celebi + Score)', () => {
  it('a solid blue image gives a blue accent', () => {
    const palette = paletteFromPixels(fill(112 * 70, [20, 60, 230]))
    const [r, g, b] = rgbOf(palette.seed)
    const hue = Hct.fromInt(argbFromRgb(r, g, b)).hue

    expect(palette.monochrome).toBe(false)
    expect(b).toBeGreaterThan(r + 60)
    expect(b).toBeGreaterThan(g + 30)
    expect(hue).toBeGreaterThan(240)
    expect(hue).toBeLessThan(300)
    expect(palette.swatches.length).toBeGreaterThanOrEqual(3)
    expect(palette.swatches.length).toBeLessThanOrEqual(5)
    expect(palette.swatches[0]).toBe(palette.seed)
    // Liquid Glass spec §6.2.4: accent L ≈ 0.63, chroma ≤ 0.15 (no neon on glass).
    const [L, C] = oklchFromArgb(argbFromRgb(r, g, b))
    expect(L).toBeCloseTo(ACCENT_L, 1)
    expect(C).toBeLessThanOrEqual(ACCENT_MAX_C + 0.01)
  })

  it('a grayscale image falls back to the neutral monochrome accent', () => {
    const pixels: number[] = []

    for (let i = 0; i < 112 * 70; i++) {
      const v = (i * 7) % 256
      pixels.push(argbFromRgb(v, v, v))
    }

    const palette = paletteFromPixels(pixels)
    expect(palette.monochrome).toBe(true)
    expect(palette.seed).toBe(MONOCHROME_ACCENT)
    expect(palette.swatches.length).toBeGreaterThanOrEqual(3)
  })

  it('ranks the dominant colours of a two-colour image as swatches', () => {
    const palette = paletteFromPixels([...fill(6000, [220, 30, 40]), ...fill(2000, [30, 170, 80])])
    const [r, g] = rgbOf(palette.seed)

    expect(r).toBeGreaterThan(g)
    expect(palette.swatches.some(hex => rgbOf(hex)[1] > rgbOf(hex)[0])).toBe(true)
  })
})

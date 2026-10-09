/**
 * Wallpaper palette (Material You-style "Warna dari wallpaper").
 *
 * The image is drawn ONCE into a small (≤112 px) offscreen canvas, its pixels
 * are quantized with Material's Celebi quantizer and ranked with Score (the
 * same pipeline Android uses for dynamic colour). The best-ranked colour,
 * normalised to a usable accent tone, becomes the seed; the next ranked ones
 * are offered as swatches. An image with no usable chroma (grayscale, near
 * black/white) falls back to the monochrome accent.
 *
 * This runs once per wallpaper change, never per frame.
 */

import { argbFromRgb, Hct, hexFromArgb, QuantizerCelebi, Score } from '@material/material-color-utilities'

/** The "Monokrom" accent preset; the neutral fallback for colourless images. */
export const MONOCHROME_ACCENT = '#A3A3A3'

export interface WallpaperPalette {
  /** The accent to use, #RRGGBB upper-case. */
  seed: string
  /** 3–5 suggested accents from the image (seed first). */
  swatches: string[]
  /** True when the image had no usable colour and the neutral fallback is used. */
  monochrome: boolean
}

const SAMPLE_EDGE = 112
const MAX_COLORS = 128

const hex = (argb: number) => hexFromArgb(argb).toUpperCase()

// ── OKLCH (Björn Ottosson) for the accent limits in the Liquid Glass spec ──
const toLin = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
const toGam = (c: number) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055)

export function oklchFromArgb(argb: number): [number, number, number] {
  const r = toLin(((argb >> 16) & 255) / 255)
  const g = toLin(((argb >> 8) & 255) / 255)
  const b = toLin((argb & 255) / 255)
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s

  return [L, Math.hypot(A, B), ((Math.atan2(B, A) * 180) / Math.PI + 360) % 360]
}

function rgbFromOklch(L: number, C: number, H: number): null | [number, number, number] {
  const h = (H * Math.PI) / 180
  const A = C * Math.cos(h)
  const B = C * Math.sin(h)
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3
  const lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
  ]

  if (lin.some(v => v < -1e-4 || v > 1 + 1e-4)) {
    return null
  }

  return lin.map(v => Math.round(Math.min(1, Math.max(0, toGam(Math.min(1, Math.max(0, v))))) * 255)) as [number, number, number]
}

/** Accent lightness / chroma limits (spec §6.2.4: not "neon" on glass). */
export const ACCENT_L = 0.63
export const ACCENT_MAX_C = 0.15
export const ACCENT_MIN_C = 0.08

/** Pull a ranked colour into an accent's range: same hue, L 0.63, C ≤ 0.15, in gamut. */
function toAccent(argb: number): number {
  const [, c, h] = oklchFromArgb(argb)

  for (let chroma = Math.min(ACCENT_MAX_C, Math.max(ACCENT_MIN_C, c)); chroma >= 0; chroma -= 0.005) {
    const rgb = rgbFromOklch(ACCENT_L, chroma, h)

    if (rgb) {
      return argbFromRgb(...rgb)
    }
  }

  return Hct.fromInt(argb).toInt()
}

const sameHex = (list: string[], value: string) => list.includes(value)

/** Palette from ARGB pixels (exported for tests and for non-DOM callers). */
export function paletteFromPixels(pixels: number[], desired = 5): WallpaperPalette {
  const opaque = pixels.filter(p => p >>> 24 === 0xff)

  if (opaque.length === 0) {
    return { seed: MONOCHROME_ACCENT, swatches: [MONOCHROME_ACCENT], monochrome: true }
  }

  const quantized = QuantizerCelebi.quantize(opaque, MAX_COLORS)
  // fallback 0 marks "nothing chromatic survived the filter".
  const ranked = Score.score(quantized, { desired, fallbackColorARGB: 0, filter: true }).filter(c => c !== 0)

  if (ranked.length === 0) {
    const swatches = [MONOCHROME_ACCENT, '#737373', '#D4D4D4']

    return { seed: MONOCHROME_ACCENT, swatches, monochrome: true }
  }

  const swatches: string[] = []

  for (const argb of ranked) {
    const h = hex(toAccent(argb))

    if (!sameHex(swatches, h)) {
      swatches.push(h)
    }
  }

  // Fewer than three distinct colours: pad with tones of the seed's hue.
  const seedHct = Hct.fromInt(toAccent(ranked[0]))

  for (const tone of [40, 70, 30, 80]) {
    if (swatches.length >= 3) {
      break
    }

    const h = hex(Hct.from(seedHct.hue, seedHct.chroma, tone).toInt())

    if (!sameHex(swatches, h)) {
      swatches.push(h)
    }
  }

  return { seed: swatches[0], swatches: swatches.slice(0, 5), monochrome: false }
}

export interface WallpaperSample {
  data: Uint8ClampedArray
  width: number
  height: number
}

let cached: null | { url: string; sample: Promise<null | WallpaperSample> } = null

/** Decode `url` and downscale it once (≤112 px); cached for the current wallpaper. */
export function sampleWallpaper(url: string): Promise<null | WallpaperSample> {
  if (cached?.url === url) {
    return cached.sample
  }

  const sample = (async () => {
    try {
      const img = new Image()
      img.decoding = 'async'
      img.src = url
      await img.decode()

      const scale = Math.min(1, SAMPLE_EDGE / Math.max(img.naturalWidth, img.naturalHeight, 1))
      const width = Math.max(1, Math.round(img.naturalWidth * scale))
      const height = Math.max(1, Math.round(img.naturalHeight * scale))

      const canvas: HTMLCanvasElement | OffscreenCanvas =
        typeof OffscreenCanvas !== 'undefined'
          ? new OffscreenCanvas(width, height)
          : Object.assign(document.createElement('canvas'), { height, width })

      const ctx = canvas.getContext('2d') as CanvasRenderingContext2D | null | OffscreenCanvasRenderingContext2D

      if (!ctx) {
        return null
      }

      ctx.drawImage(img, 0, 0, width, height)

      return { data: ctx.getImageData(0, 0, width, height).data, width, height }
    } catch {
      return null
    }
  })()

  cached = { url, sample }

  return sample
}

/** The palette of the wallpaper at `url` (null if undecodable). */
export async function wallpaperPalette(url: string): Promise<null | WallpaperPalette> {
  const sample = await sampleWallpaper(url)

  if (!sample) {
    return null
  }

  const pixels: number[] = []
  const { data } = sample

  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] === 255) {
      pixels.push(argbFromRgb(data[i], data[i + 1], data[i + 2]))
    }
  }

  return paletteFromPixels(pixels)
}

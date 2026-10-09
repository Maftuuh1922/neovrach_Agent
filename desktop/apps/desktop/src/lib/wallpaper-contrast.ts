/**
 * Text contrast over the wallpaper (rule: >= 4.5:1 everywhere).
 *
 * Every glass panel is a stack the browser composites in sRGB:
 *   wallpaper W → accent tint (t) → theme-coloured dim (d) → frame ground (kf)
 *   → panel fill F (theme surface mixed with the accent) at opacity k.
 * For each panel we look at the darkest and the brightest wallpaper pixels
 * under its rectangle (from the same ≤112 px downscale the palette uses) and
 * find the smallest fill opacity that keeps the theme's secondary text at
 * >= 4.5:1 against both. The result is written as a per-panel floor
 * (`--nv-floor-*`) that the CSS takes the max() of with the glass style's own
 * opacity, so a thin style still stays readable on a busy, bright or dark
 * wallpaper. Computed on wallpaper/setting/layout changes only, never per
 * frame.
 */

export type Rgb = [number, number, number]

export const MIN_CONTRAST = 4.5

/** WCAG relative luminance of an sRGB colour (0–255 channels). */
export function luminance([r, g, b]: Rgb): number {
  const lin = (c: number) => {
    const s = c / 255

    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  }

  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

export function contrast(a: Rgb, b: Rgb): number {
  const la = luminance(a)
  const lb = luminance(b)

  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

/** `top` at opacity `k` over `bottom` (what color-mix(…, transparent) + compositing does in sRGB). */
export const over = (top: Rgb, k: number, bottom: Rgb): Rgb =>
  [0, 1, 2].map(i => top[i] * k + bottom[i] * (1 - k)) as Rgb

export function parseColor(value: string): null | Rgb {
  const v = value.trim()
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(v)

  if (hex) {
    const h = hex[1].length === 3 ? [...hex[1]].map(c => c + c).join('') : hex[1]

    return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)) as Rgb
  }

  const rgb = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)/i.exec(v)

  return rgb ? [Number(rgb[1]), Number(rgb[2]), Number(rgb[3])] : null
}

export interface ContrastPalette {
  /** Theme surface used by the panel (after any style smoke). */
  surface: Rgb
  /** Theme chrome background (the dim colour and the frame ground). */
  chrome: Rgb
  accent: Rgb
  /** Text that must stay readable (the theme's secondary text). */
  text: Rgb
}

export interface LayerSettings {
  dim: number
  tint: number
  /** Accent share in the panel fill (style tint + wallpaper whisper), 0–1. */
  fillTint: number
}

/** The wallpaper pixel as seen under the frame ground (after tint + dim). */
export function backdropOf(w: Rgb, p: ContrastPalette, s: LayerSettings): Rgb {
  return over(p.chrome, s.dim, over(p.accent, s.tint, w))
}

/**
 * Smallest opacity k (0–1, 1% steps) for which `fill` at k over every given
 * backdrop keeps `text` at >= MIN_CONTRAST. Returns 1 when even solid fails
 * (cannot happen with a theme whose own text passes on its surface).
 */
export function minimumKeep(fill: Rgb, text: Rgb, backdrops: Rgb[], target = MIN_CONTRAST): number {
  for (let pct = 0; pct <= 100; pct++) {
    const k = pct / 100

    if (backdrops.every(b => contrast(over(fill, k, b), text) >= target)) {
      return k
    }
  }

  return 1
}

/** Darkest and brightest pixels of an RGBA buffer inside a pixel rectangle. */
export function extremesIn(
  data: ArrayLike<number>,
  width: number,
  height: number,
  rect: { x0: number; y0: number; x1: number; y1: number }
): Rgb[] {
  const x0 = Math.max(0, Math.floor(rect.x0))
  const y0 = Math.max(0, Math.floor(rect.y0))
  const x1 = Math.min(width, Math.ceil(rect.x1))
  const y1 = Math.min(height, Math.ceil(rect.y1))
  let dark: null | Rgb = null
  let bright: null | Rgb = null
  let lo = Infinity
  let hi = -Infinity

  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * width + x) * 4
      const px: Rgb = [data[i], data[i + 1], data[i + 2]]
      const l = luminance(px)

      if (l < lo) {
        lo = l
        dark = px
      }

      if (l > hi) {
        hi = l
        bright = px
      }
    }
  }

  return dark && bright ? [dark, bright] : []
}

export interface RegionStats {
  /** Darkest and brightest pixels. */
  extremes: Rgb[]
  /** Mean colour. */
  mean: Rgb
  /** Mean relative luminance (0–1). */
  luminance: number
  /** Luminance standard deviation, scaled to 0–1 ("there is detail under it"). */
  detail: number
}

/** Extremes, mean colour, mean luminance and detail of a pixel rectangle. */
export function regionStats(
  data: ArrayLike<number>,
  width: number,
  height: number,
  rect: { x0: number; y0: number; x1: number; y1: number }
): null | RegionStats {
  const x0 = Math.max(0, Math.floor(rect.x0))
  const y0 = Math.max(0, Math.floor(rect.y0))
  const x1 = Math.min(width, Math.ceil(rect.x1))
  const y1 = Math.min(height, Math.ceil(rect.y1))
  let n = 0
  let sl = 0
  let sl2 = 0
  const sum = [0, 0, 0]

  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * width + x) * 4
      const l = luminance([data[i], data[i + 1], data[i + 2]])
      n++
      sl += l
      sl2 += l * l
      sum[0] += data[i]
      sum[1] += data[i + 1]
      sum[2] += data[i + 2]
    }
  }

  if (!n) {
    return null
  }

  const mean = sl / n
  const std = Math.sqrt(Math.max(0, sl2 / n - mean * mean))

  return {
    extremes: extremesIn(data, width, height, rect),
    mean: sum.map(v => v / n) as Rgb,
    luminance: mean,
    detail: Math.min(1, std * 2)
  }
}

/**
 * Adaptive outer shadow (spec §2.1): stronger over detail (text, edges),
 * weaker over bright flat areas, deeper in dark mode; coloured by the
 * wallpaper under it (darkened), so it never introduces an off-palette tone.
 */
export function adaptiveShadow(stats: RegionStats, scheme: 'dark' | 'light'): string {
  const base = 0.06 + 0.22 * stats.detail - 0.08 * stats.luminance
  const alpha = scheme === 'dark' ? Math.min(0.35, Math.max(0.2, base + 0.14)) : Math.min(0.24, Math.max(0.1, base))
  const [r, g, b] = stats.mean.map(v => Math.round(v * 0.25))

  return `rgb(${r} ${g} ${b} / ${alpha.toFixed(2)})`
}

/**
 * Map a viewport rectangle to pixels of the downscaled image, following the
 * wallpaper layer: `background-size: cover`, centred, on a box that bleeds
 * `bleed` px past every viewport edge.
 */
export function viewportRectToImage(
  rect: { left: number; top: number; right: number; bottom: number },
  viewport: { width: number; height: number },
  image: { width: number; height: number },
  bleed: number
) {
  const boxW = viewport.width + bleed * 2
  const boxH = viewport.height + bleed * 2
  const scale = Math.max(boxW / image.width, boxH / image.height)
  const offX = (boxW - image.width * scale) / 2 - bleed
  const offY = (boxH - image.height * scale) / 2 - bleed

  return {
    x0: (rect.left - offX) / scale,
    y0: (rect.top - offY) / scale,
    x1: (rect.right - offX) / scale,
    y1: (rect.bottom - offY) / scale
  }
}

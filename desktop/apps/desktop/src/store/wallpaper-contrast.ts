/**
 * Keeps text >= 4.5:1 over the wallpaper: measures the wallpaper under each
 * glass panel and publishes the minimum fill opacity per panel as root
 * variables (`--nv-floor-frame|stage|sessions|context|bubble`), which the
 * glass CSS max()es with the style's own opacity. See lib/wallpaper-contrast.ts
 * for the model.
 *
 * Recomputed only when something that moves the answer changes: the image,
 * the sliders, the glass style, the accent, the light/dark scheme, or the
 * panel layout (ResizeObserver + window resize, debounced). Never per frame.
 */

import { $nvAppearance } from '@/components/neovarch/appearance'
import {
  adaptiveShadow,
  backdropOf,
  type ContrastPalette,
  extremesIn,
  minimumKeep,
  over,
  parseColor,
  regionStats,
  type Rgb,
  viewportRectToImage
} from '@/lib/wallpaper-contrast'
import { sampleWallpaper, type WallpaperSample } from '@/lib/wallpaper-palette'

import { $glassStyle, type GlassStyle } from './glass-style'
import { $appearance } from './translucency'
import { $wallpaper, $wallpaperUrl, type WallpaperSettings } from './wallpaper'

export const FLOOR_VARS = ['frame', 'stage', 'sessions', 'context', 'bubble'].map(id => `--nv-floor-${id}`)
export const SHADOW_VARS = ['stage', 'sessions', 'context'].map(id => `--nv-shadow-${id}`)

/** Accent share in a panel fill, mirroring the [data-nv-glass-style] CSS. */
export function fillTintFor(style: GlassStyle, w: Pick<WallpaperSettings, 'autoAccent'>): number {
  if (style === 'tanpa') {
    return 0
  }

  return style === 'warna' ? 0.22 : w.autoAccent ? 0.05 : 0
}

export interface RectLike {
  left: number
  top: number
  right: number
  bottom: number
}

export interface PanelRects {
  frame: RectLike[]
  stage: RectLike[]
  sessions: RectLike[]
  context: RectLike[]
}

export interface FloorInput {
  sample: WallpaperSample
  rects: PanelRects
  viewport: { width: number; height: number }
  settings: Pick<WallpaperSettings, 'autoAccent' | 'blur' | 'dim' | 'tint'>
  style: GlassStyle
  scheme: 'dark' | 'light'
  colors: { ink: Rgb; ink2: Rgb; text: Rgb; text2: Rgb; accent: Rgb; chrome: Rgb }
}

const mix = (a: Rgb, b: Rgb, t: number): Rgb => over(b, t, a)

/** Adaptive shadow colour per panel (spec §2.1). Pure: exported for tests. */
export function computeShadows(input: Pick<FloorInput, 'rects' | 'sample' | 'scheme' | 'settings' | 'viewport'>): Record<string, string> {
  const { sample, rects, viewport, settings, scheme } = input
  const out: Record<string, string> = {}

  for (const id of ['stage', 'sessions', 'context'] as const) {
    const r = rects[id][0]
    const stats = r
      ? regionStats(sample.data, sample.width, sample.height, viewportRectToImage(r, viewport, sample, settings.blur * 2))
      : null

    if (stats) {
      out[`--nv-shadow-${id}`] = adaptiveShadow(stats, scheme)
    }
  }

  return out
}

/** Floors (0–100, percent) for every panel. Pure: exported for tests. */
export function computeFloors(input: FloorInput): Record<string, number> {
  const { sample, rects, viewport, settings, style, scheme, colors } = input

  const smoke = (c: Rgb) => (style === 'gelap' && scheme === 'light' ? mix(c, colors.text, 0.25) : c)
  const tint = fillTintFor(style, settings)
  const fill = (c: Rgb) => mix(smoke(c), colors.accent, tint)
  const palette: ContrastPalette = { surface: colors.ink, chrome: colors.chrome, accent: colors.accent, text: colors.text2 }
  const layer = { dim: settings.dim, tint: settings.tint, fillTint: tint }

  const backdropsUnder = (list: RectLike[]): Rgb[] =>
    list.flatMap(r =>
      extremesIn(sample.data, sample.width, sample.height, viewportRectToImage(r, viewport, sample, settings.blur * 2))
    ).map(w => backdropOf(w, palette, layer))

  // Frame ground (command bar + rail text sits directly on it).
  const frameBackdrops = backdropsUnder(rects.frame.length ? rects.frame : [{ left: 0, top: 0, right: viewport.width, bottom: viewport.height }])
  const frame = frameBackdrops.length ? minimumKeep(colors.ink, colors.text2, frameBackdrops) : 0

  // Tanpa efek: every panel is solid; only the frame ground stays translucent.
  if (style === 'tanpa') {
    return { ...Object.fromEntries(FLOOR_VARS.map(v => [v, 100])), '--nv-floor-frame': Math.round(frame * 100) }
  }
  // Panels sit on the frame ground at (at least) that opacity.
  const onFrame = (list: RectLike[]) => backdropsUnder(list).map(b => over(colors.ink, frame, b))

  const floorFor = (list: RectLike[], surface: Rgb) => {
    const backdrops = onFrame(list)

    return backdrops.length ? minimumKeep(fill(surface), colors.text2, backdrops) : 0
  }

  const stage = floorFor(rects.stage, colors.ink)
  // Bubbles sit inside the stage, on the stage fill at (at least) its floor.
  const stageBackdrops = onFrame(rects.stage).map(b => over(fill(colors.ink), stage, b))
  // (The user's bubble carries 10% more accent, +6% on hover: check the strongest.)
  const bubbleFill = mix(smoke(colors.ink2), colors.accent, tint + 0.16)
  const bubble = stageBackdrops.length ? minimumKeep(bubbleFill, colors.text2, stageBackdrops) : 0

  const pct = (k: number) => Math.round(k * 100)

  return {
    '--nv-floor-frame': pct(frame),
    '--nv-floor-stage': pct(stage),
    '--nv-floor-sessions': pct(floorFor(rects.sessions, colors.ink2)),
    '--nv-floor-context': pct(floorFor(rects.context, colors.ink2)),
    '--nv-floor-bubble': pct(bubble)
  }
}

const rectsOf = (selector: string) =>
  Array.from(document.querySelectorAll(selector))
    .map(el => el.getBoundingClientRect())
    .filter(r => r.width > 0 && r.height > 0)

function readColors(): FloorInput['colors'] {
  const cs = getComputedStyle(document.documentElement)
  const get = (name: string, fallback: string) => parseColor(cs.getPropertyValue(name)) ?? parseColor(fallback)!
  const ink = get('--nv-ink', '#0d0606')

  return {
    ink,
    ink2: get('--nv-ink-2', '#120909'),
    text: get('--nv-text', '#f4f2ed'),
    text2: get('--nv-text-2', '#b9b2ac'),
    accent: get('--nv-red', '#ee1c1c'),
    chrome: parseColor(cs.getPropertyValue('--ui-bg-chrome')) ?? ink
  }
}

let run = 0

export async function updateContrastFloors(): Promise<null | Record<string, number>> {
  const mine = ++run
  const root = document.documentElement
  const w = $wallpaper.get()
  const url = $wallpaperUrl.get()

  if (!w.source || !url) {
    ;[...FLOOR_VARS, ...SHADOW_VARS].forEach(v => root.style.removeProperty(v))

    return null
  }

  const sample = await sampleWallpaper(url)

  if (!sample || mine !== run) {
    return null
  }

  const input: FloorInput = {
    sample,
    rects: {
      frame: rectsOf('.nv-command-bar, .nv-rail'),
      stage: rectsOf('.nv-stage'),
      sessions: rectsOf('.nv-sessions'),
      context: rectsOf('.nv-context-card')
    },
    viewport: { width: window.innerWidth, height: window.innerHeight },
    settings: w,
    style: $glassStyle.get(),
    scheme: $appearance.get(),
    colors: readColors()
  }
  const floors = computeFloors(input)

  for (const [k, v] of Object.entries(floors)) {
    root.style.setProperty(k, `${v}%`)
  }

  for (const [k, v] of Object.entries(computeShadows(input))) {
    root.style.setProperty(k, v)
  }

  root.setAttribute('data-nv-contrast-ready', '')

  return floors
}

if (typeof window !== 'undefined') {
  let timer: ReturnType<typeof setTimeout> | undefined
  let observer: ResizeObserver | undefined

  const observe = () => {
    observer?.disconnect()

    if (!$wallpaper.get().source || typeof ResizeObserver === 'undefined') {
      return
    }

    observer ??= new ResizeObserver(() => schedule())

    for (const el of document.querySelectorAll('.nv-frame-body, .nv-stage, .nv-sessions, .nv-context')) {
      observer.observe(el)
    }
  }

  // Debounced, so a sidebar animation or a window drag costs one measure.
  const schedule = () => {
    clearTimeout(timer)
    timer = setTimeout(() => {
      void updateContrastFloors()
      observe()
    }, 150)
  }

  $wallpaper.listen(schedule)
  $wallpaperUrl.subscribe(schedule)
  $glassStyle.listen(schedule)
  $appearance.listen(schedule)
  $nvAppearance.listen(schedule)
  window.addEventListener('resize', schedule)
}

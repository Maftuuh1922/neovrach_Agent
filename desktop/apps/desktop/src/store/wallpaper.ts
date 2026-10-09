/**
 * Neovarch wallpaper ("Latar belakang", Settings ▸ Tampilan), matching the
 * phone remote's v1.4.2 background: an image behind the whole app shell with
 * Blur / Kegelapan / Tint aksen / Saturasi, plus "Kekuatan kaca" for the
 * translucent glass panels laid over it.
 *
 * Presentation-only, so the renderer owns and persists it (localStorage via
 * lib/storage, like the other appearance prefs). `source` is '' (flat, the
 * default), `preset:<id>` (art bundled with the app) or `file:<name>` (an image
 * the main process copied into userData/wallpapers; see
 * electron/neovarch-wallpaper.ts).
 *
 * Painting is pure CSS: this module only writes root variables and the
 * `data-nv-wallpaper` attribute. One fixed layer (components/neovarch/
 * wallpaper.tsx) wears the filters; no per-frame JS anywhere.
 */

import { atom } from 'nanostores'

import featAutomation from '@/assets/neovarch/wallpapers/feat-automation.webp'
import featRemote from '@/assets/neovarch/wallpapers/feat-remote.webp'
import portalBanner from '@/assets/neovarch/wallpapers/portal-banner.webp'
import { readJson, writeJson } from '@/lib/storage'

import { $appearance } from './translucency'

export interface WallpaperSettings {
  source: string
  /** Image blur radius, px (0–30). */
  blur: number
  /** Theme-background overlay over the image (0–0.8). */
  dim: number
  /** Accent overlay over the image (0–0.6). */
  tint: number
  /** Image saturation (0–2, 1 = unchanged). */
  saturation: number
  /** Glass panels' backdrop blur, px (0–40); also thins the panels' fill. */
  glass: number
  /** "Warna dari wallpaper": derive the app accent from the image (on by default). */
  autoAccent: boolean
  /** The accent in use before the wallpaper took it over ('' = none), restored when it lets go. */
  restoreAccent: string
}

export const WALLPAPER_RANGES = {
  blur: { min: 0, max: 30, step: 1 },
  dim: { min: 0, max: 0.8, step: 0.01 },
  tint: { min: 0, max: 0.6, step: 0.01 },
  saturation: { min: 0, max: 2, step: 0.01 },
  glass: { min: 0, max: 40, step: 1 }
} as const

export type WallpaperAdjustment = keyof typeof WALLPAPER_RANGES

export const DEFAULT_WALLPAPER: WallpaperSettings = {
  source: '',
  blur: 6,
  dim: 0.4,
  tint: 0.15,
  saturation: 1,
  glass: 22,
  autoAccent: true,
  restoreAccent: ''
}

export const WALLPAPER_PRESETS = [
  { id: 'remote', label: 'Remote', url: featRemote },
  { id: 'automation', label: 'Otomasi', url: featAutomation },
  { id: 'portal', label: 'Portal', url: portalBanner }
] as const

export const WALLPAPER_KEY = 'neovarch.desktop.wallpaper.v1'

const SOURCE_RE = /^(preset:(remote|automation|portal)|file:wallpaper-[0-9a-f]{16}\.(png|jpg|webp|gif))$/

const clamp = (value: unknown, key: WallpaperAdjustment): number => {
  const { min, max } = WALLPAPER_RANGES[key]
  const n = typeof value === 'number' ? value : Number(value)

  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : DEFAULT_WALLPAPER[key]
}

export function normalizeWallpaper(raw: unknown): WallpaperSettings {
  const r = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {}
  const source = typeof r.source === 'string' && SOURCE_RE.test(r.source) ? r.source : ''

  return {
    source,
    blur: clamp(r.blur ?? DEFAULT_WALLPAPER.blur, 'blur'),
    dim: clamp(r.dim ?? DEFAULT_WALLPAPER.dim, 'dim'),
    tint: clamp(r.tint ?? DEFAULT_WALLPAPER.tint, 'tint'),
    saturation: clamp(r.saturation ?? DEFAULT_WALLPAPER.saturation, 'saturation'),
    glass: clamp(r.glass ?? DEFAULT_WALLPAPER.glass, 'glass'),
    autoAccent: typeof r.autoAccent === 'boolean' ? r.autoAccent : DEFAULT_WALLPAPER.autoAccent,
    restoreAccent:
      typeof r.restoreAccent === 'string' && /^#[0-9A-F]{6}$/i.test(r.restoreAccent) ? r.restoreAccent.toUpperCase() : ''
  }
}

const sameWallpaper = (a: WallpaperSettings, b: WallpaperSettings) =>
  a.source === b.source &&
  a.blur === b.blur &&
  a.dim === b.dim &&
  a.tint === b.tint &&
  a.saturation === b.saturation &&
  a.glass === b.glass &&
  a.autoAccent === b.autoAccent &&
  a.restoreAccent === b.restoreAccent

export const isDefaultWallpaper = (w: WallpaperSettings) => sameWallpaper(w, DEFAULT_WALLPAPER)

export const $wallpaper = atom<WallpaperSettings>(
  typeof window === 'undefined' ? DEFAULT_WALLPAPER : normalizeWallpaper(readJson<unknown>(WALLPAPER_KEY))
)

/** The resolved image URL for `source` (a file source loads asynchronously). */
export const $wallpaperUrl = atom<null | string>(null)

/** Last import/load problem, Indonesian, shown under the picker. */
export const $wallpaperError = atom<null | string>(null)

export function setWallpaper(patch: Partial<WallpaperSettings>): void {
  const next = normalizeWallpaper({ ...$wallpaper.get(), ...patch })

  if (!sameWallpaper(next, $wallpaper.get())) {
    $wallpaper.set(next)
  }
}

/** "Reset": back to the defaults (no wallpaper, default sliders), like the phone. */
export function resetWallpaper(): void {
  const bridge = typeof window === 'undefined' ? undefined : window.neovarchWallpaper
  $wallpaperError.set(null)
  $wallpaper.set({ ...DEFAULT_WALLPAPER })
  void bridge?.clear().catch(() => undefined)
}

/**
 * Called by every manual accent choice. With a wallpaper shown this turns
 * "Warna dari wallpaper" off and forgets the accent to restore (the new
 * choice is kept; see store/wallpaper-accent.ts).
 */
export function noteManualAccent(): void {
  const w = $wallpaper.get()

  if (w.source && (w.autoAccent || w.restoreAccent)) {
    setWallpaper({ autoAccent: false, restoreAccent: '' })
  }
}

export function setWallpaperSource(source: string): void {
  $wallpaperError.set(null)
  setWallpaper({ source })
}

/**
 * Glass fill share for the panels, in percent, from "Kekuatan kaca": stronger
 * glass = thinner fill. Readability is not decided here: the per-panel
 * contrast floors (store/wallpaper-contrast.ts) raise the fill wherever the
 * wallpaper underneath would push text below 4.5:1.
 */
export function wallpaperPanelKeep(w: Pick<WallpaperSettings, 'glass'>): number {
  return Math.round(Math.max(46, 94 - w.glass * 1.2) * 10) / 10
}

/** The root CSS variables the wallpaper paints with. */
export function wallpaperCssVars(w: WallpaperSettings): Record<string, string> {
  return {
    '--nv-wall-blur': `${w.blur}px`,
    '--nv-wall-saturation': String(w.saturation),
    '--nv-wall-dim': String(w.dim),
    '--nv-wall-tint': String(w.tint),
    '--nv-wall-glass': `${w.glass}px`,
    '--nv-wall-keep': `${wallpaperPanelKeep(w)}%`,
    // With the accent taken from the image, the glass picks up a whisper of it.
    '--nv-wall-accent-tint': w.autoAccent ? '5%' : '0%'
  }
}

const VAR_NAMES = Object.keys(wallpaperCssVars(DEFAULT_WALLPAPER))

/** A GIF wallpaper is shown still: its first frame, drawn once to a canvas. */
async function freezeGif(dataUrl: string): Promise<string> {
  try {
    const img = new Image()
    img.src = dataUrl
    await img.decode()
    const canvas = document.createElement('canvas')
    canvas.width = img.naturalWidth
    canvas.height = img.naturalHeight
    const ctx = canvas.getContext('2d')

    if (!ctx || !canvas.width) {
      return dataUrl
    }

    ctx.drawImage(img, 0, 0)

    return canvas.toDataURL('image/png')
  } catch {
    return dataUrl
  }
}

let loadToken = 0

async function resolveSource(source: string): Promise<void> {
  const token = ++loadToken

  if (!source) {
    $wallpaperUrl.set(null)

    return
  }

  if (source.startsWith('preset:')) {
    const preset = WALLPAPER_PRESETS.find(p => `preset:${p.id}` === source)
    $wallpaperUrl.set(preset?.url ?? null)

    return
  }

  const bridge = window.neovarchWallpaper
  const name = source.slice('file:'.length)
  const result = bridge ? await bridge.read(name).catch(() => null) : null

  if (token !== loadToken) {
    return
  }

  if (!result) {
    $wallpaperUrl.set(null)
    $wallpaperError.set('Gambar latar belakang tidak ditemukan lagi. Pilih gambar lain.')

    return
  }

  const url = result.mime === 'image/gif' ? await freezeGif(result.dataUrl) : result.dataUrl

  if (token === loadToken) {
    $wallpaperUrl.set(url)
  }
}

function paint(w: WallpaperSettings, url: null | string): void {
  const root = document.documentElement
  const on = Boolean(w.source && url)
  root.toggleAttribute('data-nv-wallpaper', on)

  if (on) {
    for (const [k, v] of Object.entries(wallpaperCssVars(w))) {
      root.style.setProperty(k, v)
    }
  } else {
    for (const k of VAR_NAMES) {
      root.style.removeProperty(k)
    }
  }
}

if (typeof window !== 'undefined') {
  let lastSource: null | string = null

  $wallpaper.subscribe(w => {
    writeJson(WALLPAPER_KEY, isDefaultWallpaper(w) ? null : w)

    if (w.source !== lastSource) {
      lastSource = w.source
      void resolveSource(w.source)
    }

    paint(w, $wallpaperUrl.get())
  })

  $wallpaperUrl.subscribe(url => paint($wallpaper.get(), url))

  // The rendered light/dark scheme, for the few glass rules that differ by it.
  $appearance.subscribe(mode => document.documentElement.setAttribute('data-nv-scheme', mode))
}

const IMAGE_TYPES = /^image\/(png|jpeg|webp|gif)$/

/** Import a picked/dropped image through the main process and select it. */
async function adopt(result: NeovarchWallpaperImport | undefined): Promise<boolean> {
  if (!result || result.canceled) {
    return false
  }

  if (!result.ok || !result.name) {
    $wallpaperError.set(result.error ?? 'Gagal memuat gambar.')

    return false
  }

  setWallpaperSource(`file:${result.name}`)

  return true
}

export async function pickWallpaperFile(): Promise<boolean> {
  const bridge = window.neovarchWallpaper

  if (!bridge) {
    $wallpaperError.set('Memilih file hanya tersedia di aplikasi desktop.')

    return false
  }

  return adopt(await bridge.pick().catch(() => ({ ok: false, error: 'Gagal membuka pemilih file.' })))
}

export async function importWallpaperFile(file: File): Promise<boolean> {
  const bridge = window.neovarchWallpaper

  if (!IMAGE_TYPES.test(file.type) && !/\.(png|jpe?g|webp|gif)$/i.test(file.name)) {
    $wallpaperError.set('Format tidak didukung. Pakai PNG, JPG, WebP, atau GIF.')

    return false
  }

  if (!bridge) {
    $wallpaperError.set('Menyimpan gambar hanya tersedia di aplikasi desktop.')

    return false
  }

  const filePath = bridge.pathForFile(file)
  const result = filePath
    ? await bridge.importFile(filePath).catch(() => undefined)
    : await bridge.importBytes(new Uint8Array(await file.arrayBuffer())).catch(() => undefined)

  return adopt(result ?? { ok: false, error: 'Gagal memuat gambar.' })
}

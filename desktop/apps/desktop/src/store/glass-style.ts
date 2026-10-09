/**
 * "Gaya kaca" (Settings ▸ Tampilan): how the glass panels over a wallpaper are
 * painted. Ids are shared with the Android remote so theme sync can carry them:
 *   reguler  moderate blur + subtle specular (default)
 *   bening   clear: very transparent, low blur, strong rim, floating
 *   gelap    dark smoked glass that keeps its highlights
 *   warna    tinted by the accent / wallpaper palette
 *   tanpa    no effect: opaque solid surfaces, no backdrop-filter
 *            (Aksesibilitas; the default when the OS asks for reduced
 *            transparency or more contrast)
 *
 * The renderer only sets `data-nv-glass-style` on <html>; every value lives in
 * CSS variables (styles/neovarch.css). The OS preference is read through
 * matchMedia change events, never polled.
 */

import { atom, computed } from 'nanostores'

import { readKey, writeKey } from '@/lib/storage'

export const GLASS_STYLES = ['reguler', 'bening', 'gelap', 'warna', 'tanpa'] as const

export type GlassStyle = (typeof GLASS_STYLES)[number]

export const GLASS_STYLE_LABELS: Record<GlassStyle, string> = {
  reguler: 'Reguler',
  bening: 'Bening',
  gelap: 'Gelap',
  warna: 'Warna',
  tanpa: 'Tanpa efek'
}

export const GLASS_STYLE_KEY = 'neovarch.desktop.glass-style.v1'

export const REDUCED_TRANSPARENCY_QUERY = '(prefers-reduced-transparency: reduce), (prefers-contrast: more)'

export const isGlassStyle = (v: unknown): v is GlassStyle =>
  typeof v === 'string' && (GLASS_STYLES as readonly string[]).includes(v)

/** The user's explicit choice; null = automatic (follows the OS preference). */
export const $glassStyleChoice = atom<GlassStyle | null>(
  typeof window === 'undefined' ? null : ((s => (isGlassStyle(s) ? s : null))(readKey(GLASS_STYLE_KEY)))
)

const mediaQuery = (): MediaQueryList | null =>
  typeof window !== 'undefined' && typeof window.matchMedia === 'function' ? window.matchMedia(REDUCED_TRANSPARENCY_QUERY) : null

/** The OS asks for reduced transparency or more contrast. */
export const $prefersReducedTransparency = atom<boolean>(mediaQuery()?.matches ?? false)

export const defaultGlassStyle = (reduced: boolean): GlassStyle => (reduced ? 'tanpa' : 'reguler')

/** The style in effect. */
export const $glassStyle = computed(
  [$glassStyleChoice, $prefersReducedTransparency],
  (choice, reduced): GlassStyle => choice ?? defaultGlassStyle(reduced)
)

export function setGlassStyle(style: GlassStyle): void {
  $glassStyleChoice.set(style)
}

if (typeof window !== 'undefined') {
  const mq = mediaQuery()
  mq?.addEventListener?.('change', event => $prefersReducedTransparency.set(event.matches))

  $glassStyleChoice.subscribe(choice => writeKey(GLASS_STYLE_KEY, choice))
  $glassStyle.subscribe(style => document.documentElement.setAttribute('data-nv-glass-style', style))
}

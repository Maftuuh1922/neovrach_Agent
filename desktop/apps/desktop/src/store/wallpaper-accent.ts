/**
 * "Warna dari wallpaper": while a wallpaper is shown and the toggle is on, the
 * app accent follows the image's palette (lib/wallpaper-palette.ts). The accent
 * goes through the normal appearance save, so a paired phone follows it too.
 *
 * The accent in use before the wallpaper took over is remembered and put back
 * when the wallpaper is removed, reset, or the toggle is switched off. Picking
 * an accent by hand (a preset, a hex, or one of the wallpaper's swatches)
 * switches the toggle off and keeps that choice.
 */

import { atom } from 'nanostores'

import { $nvAppearance, applyAccent, DEFAULT_ACCENT, saveAppearance } from '@/components/neovarch/appearance'
import { wallpaperPalette, type WallpaperPalette } from '@/lib/wallpaper-palette'

import { $wallpaper, $wallpaperUrl, noteManualAccent, setWallpaper, type WallpaperSettings } from './wallpaper'

/** Palette of the wallpaper on screen (null while none / not yet computed). */
export const $wallpaperPalette = atom<null | WallpaperPalette>(null)

/** Seam for tests. */
export const paletteSource = { compute: wallpaperPalette }

const currentBase = (): 'dark' | 'light' => $nvAppearance.get()?.base ?? 'dark'
const currentAccent = (): string => ($nvAppearance.get()?.accent ?? DEFAULT_ACCENT).toUpperCase()

async function applyWallpaperAccent(accent: string): Promise<void> {
  if (currentAccent() === accent.toUpperCase()) {
    return
  }

  try {
    await saveAppearance({ accent, base: currentBase() })
  } catch {
    // Core unreachable: paint locally; the next save syncs it.
    applyAccent(accent, currentBase())
  }
}

const following = (w: WallpaperSettings) => Boolean(w.source) && w.autoAccent

function maybeApply(): void {
  const w = $wallpaper.get()
  const palette = $wallpaperPalette.get()

  if (!following(w) || !palette) {
    return
  }

  if (!w.restoreAccent) {
    setWallpaper({ restoreAccent: currentAccent() })
  }

  void applyWallpaperAccent(palette.seed)
}

/** A suggested swatch from the wallpaper, picked by hand. */
export async function pickWallpaperSwatch(accent: string): Promise<void> {
  noteManualAccent()
  await applyWallpaperAccent(accent)
}

export function setWallpaperAutoAccent(on: boolean): void {
  setWallpaper({ autoAccent: on })
}

let token = 0

if (typeof window !== 'undefined') {
  $wallpaperUrl.subscribe(url => {
    const mine = ++token

    if (!url || !$wallpaper.get().source) {
      $wallpaperPalette.set(null)

      return
    }

    void paletteSource.compute(url).then(palette => {
      if (mine === token) {
        $wallpaperPalette.set(palette)
        maybeApply()
      }
    })
  })

  let prev = $wallpaper.get()

  $wallpaper.listen(next => {
    const before = prev
    prev = next

    // Let go of the accent: wallpaper removed/reset, or the toggle switched off.
    // (A manual pick also stops following, but clears restoreAccent while the
    // wallpaper stays: that choice is kept.)
    if (following(before) && !following(next) && before.restoreAccent && (!next.source || next.restoreAccent)) {
      const restore = before.restoreAccent

      if (next.restoreAccent) {
        setWallpaper({ restoreAccent: '' })
      }

      void applyWallpaperAccent(restore)

      return
    }

    if (!following(before) && following(next)) {
      maybeApply()
    }
  })
}

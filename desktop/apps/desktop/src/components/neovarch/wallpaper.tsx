// Side effect: "Warna dari wallpaper" (accent follows the image's palette).
import '@/store/wallpaper-accent'
// Side effect: "Gaya kaca" (data-nv-glass-style on <html>).
import '@/store/glass-style'
// Side effect: per-panel fill floors that keep text >= 4.5:1 over the image.
import '@/store/wallpaper-contrast'

import { useStore } from '@nanostores/react'
import type { CSSProperties } from 'react'

import { $wallpaper, $wallpaperUrl } from '@/store/wallpaper'

/**
 * The one fixed background layer behind the whole app shell. The image wears
 * CSS filters (blur + saturate) read from root variables; the accent tint and
 * the theme-coloured dim are two flat overlays (no gradients). Renders nothing
 * without a wallpaper, so the default look is untouched.
 */
export function NeovarchWallpaper() {
  const wallpaper = useStore($wallpaper)
  const url = useStore($wallpaperUrl)

  if (!wallpaper.source || !url) {
    return null
  }

  return (
    <div aria-hidden="true" className="nv-wallpaper" data-slot="nv-wallpaper">
      <div
        className="nv-wallpaper-image"
        data-slot="nv-wallpaper-image"
        style={
          {
            backgroundImage: `url("${url}")`,
            filter: `blur(${wallpaper.blur}px) saturate(${wallpaper.saturation})`
          } as CSSProperties
        }
      />
      {wallpaper.tint > 0 && (
        <div className="nv-wallpaper-tint" data-slot="nv-wallpaper-tint" style={{ opacity: wallpaper.tint }} />
      )}
      {wallpaper.dim > 0 && (
        <div className="nv-wallpaper-dim" data-slot="nv-wallpaper-dim" style={{ opacity: wallpaper.dim }} />
      )}
    </div>
  )
}

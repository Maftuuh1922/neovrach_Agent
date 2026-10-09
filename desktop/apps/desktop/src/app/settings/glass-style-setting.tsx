import { useStore } from '@nanostores/react'

import {
  $glassStyle,
  $glassStyleChoice,
  $prefersReducedTransparency,
  GLASS_STYLE_LABELS,
  type GlassStyle,
  setGlassStyle
} from '@/store/glass-style'
import { $wallpaper, $wallpaperUrl, WALLPAPER_PRESETS } from '@/store/wallpaper'

const HINTS: Record<GlassStyle, string> = {
  reguler: 'Blur sedang, kilau halus',
  bening: 'Sangat bening, tepi terang',
  gelap: 'Kaca asap gelap',
  warna: 'Diwarnai aksen',
  tanpa: 'Permukaan padat, tanpa blur'
}

function Tile({ style, selected, image }: { style: GlassStyle; selected: boolean; image: string }) {
  return (
    <button
      aria-label={GLASS_STYLE_LABELS[style]}
      aria-pressed={selected}
      className="nv-glass-tile"
      data-nv-glass-tile={style}
      onClick={() => setGlassStyle(style)}
      title={HINTS[style]}
      type="button"
    >
      {/* Live preview: the same CSS variables as the real panels, scoped to
          this tile by its own data-nv-glass-style. */}
      <span className="nv-glass-tile-stage" data-nv-glass-style={style} style={{ backgroundImage: `url("${image}")` }}>
        <span className="nv-glass-tile-panel">
          Aa
          <i />
        </span>
      </span>
      <span>{GLASS_STYLE_LABELS[style]}</span>
    </button>
  )
}

/** Settings ▸ Tampilan ▸ Gaya kaca (ids shared with the phone: reguler/bening/gelap/warna/tanpa). */
export function GlassStyleSetting() {
  const style = useStore($glassStyle)
  const choice = useStore($glassStyleChoice)
  const reduced = useStore($prefersReducedTransparency)
  const wallpaper = useStore($wallpaper)
  const url = useStore($wallpaperUrl)
  // Preview over the wallpaper in use, or the Portal preset when none is set.
  const image = (wallpaper.source && url) || WALLPAPER_PRESETS[2].url

  return (
    <section aria-label="Gaya kaca" data-nv-glass-style-setting="">
      <p className="mb-1 text-sm font-medium">Gaya kaca</p>
      <p className="mb-3 text-xs text-(--ui-text-tertiary)">
        Cara panel kaca dilukis di atas latar belakang.{wallpaper.source ? '' : ' Terlihat setelah memilih latar belakang.'}
      </p>
      <div aria-label="Gaya kaca" className="nv-glass-tiles" role="group">
        {(['reguler', 'bening', 'gelap', 'warna'] as const).map(s => (
          <Tile image={image} key={s} selected={style === s} style={s} />
        ))}
      </div>
      <p className="mt-4 mb-1 text-xs font-medium tracking-wide text-(--ui-text-secondary) uppercase">Aksesibilitas</p>
      <div className="nv-glass-tiles">
        <Tile image={image} selected={style === 'tanpa'} style="tanpa" />
      </div>
      <p className="mt-2 text-xs text-(--ui-text-tertiary)">
        {reduced && choice === null
          ? 'Aktif otomatis: sistem meminta kurangi transparansi / kontras lebih tinggi.'
          : 'Otomatis dipakai bila sistem meminta kurangi transparansi atau kontras lebih tinggi.'}
      </p>
    </section>
  )
}

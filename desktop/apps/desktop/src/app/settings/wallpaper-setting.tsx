import { useStore } from '@nanostores/react'
import { type DragEvent, type ReactNode, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Slider } from '@/components/ui/slider'
import { Switch } from '@/components/ui/switch'
import { $nvAppearance, DEFAULT_ACCENT } from '@/components/neovarch/appearance'
import { ImageIcon, RefreshCw, Upload, X } from '@/lib/icons'
import {
  $wallpaper,
  $wallpaperError,
  $wallpaperUrl,
  importWallpaperFile,
  isDefaultWallpaper,
  pickWallpaperFile,
  resetWallpaper,
  setWallpaper,
  setWallpaperSource,
  WALLPAPER_PRESETS,
  WALLPAPER_RANGES,
  type WallpaperAdjustment
} from '@/store/wallpaper'
import { $wallpaperPalette, pickWallpaperSwatch, setWallpaperAutoAccent } from '@/store/wallpaper-accent'

const pct = (v: number) => `${Math.round(v * 100)}%`
const px = (v: number) => String(Math.round(v))

const SLIDERS: { key: WallpaperAdjustment; label: string; format: (v: number) => string; needsImage: boolean }[] = [
  { key: 'blur', label: 'Blur', format: px, needsImage: true },
  { key: 'dim', label: 'Kegelapan', format: pct, needsImage: true },
  { key: 'tint', label: 'Tint aksen', format: pct, needsImage: true },
  { key: 'saturation', label: 'Saturasi', format: pct, needsImage: true },
  { key: 'glass', label: 'Kekuatan kaca', format: px, needsImage: false }
]

function Choice({
  id,
  label,
  selected,
  onClick,
  image,
  children
}: {
  id: string
  label: string
  selected: boolean
  onClick: () => void
  image?: null | string
  children?: ReactNode
}) {
  return (
    <button
      aria-label={label}
      aria-pressed={selected}
      className="nv-wall-choice"
      data-nv-wall-choice={id}
      onClick={onClick}
      type="button"
    >
      <span className="nv-wall-thumb" style={image ? { backgroundImage: `url("${image}")` } : undefined}>
        {image ? null : children}
      </span>
      <span>{label}</span>
    </button>
  )
}

/** Settings ▸ Tampilan ▸ Latar belakang (same controls as the phone's v1.4.2). */
export function WallpaperSetting() {
  const wallpaper = useStore($wallpaper)
  const url = useStore($wallpaperUrl)
  const error = useStore($wallpaperError)
  const [busy, setBusy] = useState(false)
  const [dragging, setDragging] = useState(false)
  const active = wallpaper.source !== ''
  const isFile = wallpaper.source.startsWith('file:')
  const palette = useStore($wallpaperPalette)
  const accent = (useStore($nvAppearance)?.accent ?? DEFAULT_ACCENT).toUpperCase()

  const run = async (task: () => Promise<boolean>) => {
    setBusy(true)

    try {
      await task()
    } finally {
      setBusy(false)
    }
  }

  const hasFiles = (event: DragEvent) => Array.from(event.dataTransfer?.types ?? []).includes('Files')

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    if (!hasFiles(event)) {
      return
    }

    event.preventDefault()
    setDragging(false)
    const file = event.dataTransfer.files?.[0]

    if (file) {
      void run(() => importWallpaperFile(file))
    }
  }

  return (
    <section
      aria-label="Latar belakang"
      className="nv-wall-drop"
      data-dragging={dragging ? '' : undefined}
      data-nv-wallpaper-setting=""
      onDragLeave={event => {
        if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
          setDragging(false)
        }
      }}
      onDragOver={event => {
        if (hasFiles(event)) {
          event.preventDefault()
          event.dataTransfer.dropEffect = 'copy'
          setDragging(true)
        }
      }}
      onDrop={onDrop}
    >
      <div className="mb-1 flex items-center justify-between gap-3">
        <p className="text-sm font-medium">Latar belakang</p>
        <Button
          data-nv-wall-reset=""
          disabled={isDefaultWallpaper(wallpaper)}
          onClick={resetWallpaper}
          size="sm"
          variant="ghost"
        >
          <RefreshCw className="size-3.5" />
          Reset
        </Button>
      </div>
      <p className="mb-3 text-xs text-(--ui-text-tertiary)">
        Gambar di belakang seluruh aplikasi; panel jadi kaca tembus pandang. Seret gambar (PNG, JPG, WebP, GIF) ke sini
        atau pilih dari disk.
      </p>

      <div className="nv-wall-choices">
        <Choice id="none" label="Polos" onClick={() => setWallpaperSource('')} selected={!active}>
          <X className="size-5" />
        </Choice>
        <Choice
          id="file"
          image={isFile ? url : null}
          label={busy ? 'Memuat…' : 'Pilih file'}
          onClick={() => {
            if (!busy) {
              void run(pickWallpaperFile)
            }
          }}
          selected={isFile}
        >
          {dragging ? <Upload className="size-5" /> : <ImageIcon className="size-5" />}
        </Choice>
        {WALLPAPER_PRESETS.map(preset => (
          <Choice
            id={`preset-${preset.id}`}
            image={preset.url}
            key={preset.id}
            label={preset.label}
            onClick={() => setWallpaperSource(`preset:${preset.id}`)}
            selected={wallpaper.source === `preset:${preset.id}`}
          />
        ))}
      </div>

      {error && (
        <p className="mt-2 text-xs text-(--nv-red-text)" role="alert">
          {error}
        </p>
      )}

      {active && (
        <div className="mt-3 grid gap-2" data-nv-wall-accent="">
          <label className="flex items-center justify-between gap-3 text-sm">
            <span>
              Warna dari wallpaper
              <span className="block text-xs text-(--ui-text-tertiary)">
                Aksen aplikasi (dan HP) mengikuti palet gambar. Memilih warna sendiri mematikan ini.
              </span>
            </span>
            <Switch
              aria-label="Warna dari wallpaper"
              checked={wallpaper.autoAccent}
              data-nv-wall-auto-accent=""
              onCheckedChange={on => setWallpaperAutoAccent(on === true)}
            />
          </label>
          {palette && (
            <div className="flex items-center gap-3">
              <span className="text-xs text-(--ui-text-tertiary)">
                {palette.monochrome ? 'Gambar netral, pakai monokrom:' : 'Saran dari gambar:'}
              </span>
              <div className="nv-wall-swatches" role="group" aria-label="Saran warna dari wallpaper">
                {palette.swatches.map(hex => (
                  <button
                    aria-label={`Pakai ${hex}`}
                    aria-pressed={accent === hex}
                    className="nv-wall-swatch"
                    data-nv-wall-swatch={hex}
                    key={hex}
                    onClick={() => void pickWallpaperSwatch(hex)}
                    style={{ background: hex }}
                    title={hex}
                    type="button"
                  />
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      <div className="mt-3 grid gap-0.5">
        {SLIDERS.map(({ key, label, format, needsImage }) => {
          const range = WALLPAPER_RANGES[key]
          const disabled = needsImage && !active

          return (
            <label className="nv-wall-slider" data-disabled={disabled ? '' : undefined} key={key}>
              <span>{label}</span>
              <Slider
                aria-label={label}
                className="w-full"
                data-nv-wall-slider={key}
                disabled={disabled}
                max={range.max}
                min={range.min}
                onChange={event => setWallpaper({ [key]: Number(event.target.value) })}
                step={range.step}
                value={wallpaper[key]}
              />
              <span className="nv-wall-value">{format(wallpaper[key])}</span>
            </label>
          )
        })}
      </div>
    </section>
  )
}

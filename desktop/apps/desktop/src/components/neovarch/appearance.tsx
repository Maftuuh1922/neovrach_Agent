import { useStore } from '@nanostores/react'
import { atom, onMount } from 'nanostores'
import { useEffect, useState } from 'react'

import { hermesApi } from '@/api/client'
import { onGatewayEvent } from '@/contrib/events'
import { cn } from '@/lib/utils'
import { $gateway } from '@/store/gateway'
import { setAccentOverride } from '@/themes/accent-override'
import { useTheme } from '@/themes/context'

/** The PC's appearance, owned by the core (`/api/appearance`) so the phone can
 *  follow it: an accent hex and a dark/light base. */
export interface NeovarchAppearance {
  accent: string
  base: 'dark' | 'light'
  on_accent?: string
}

export const DEFAULT_ACCENT = '#EE1C1C'

export const ACCENT_PRESETS: { hex: string; name: string }[] = [
  { hex: '#EE1C1C', name: 'Merah' },
  { hex: '#2563EB', name: 'Biru' },
  { hex: '#16A34A', name: 'Hijau' },
  { hex: '#7C3AED', name: 'Ungu' },
  { hex: '#EA580C', name: 'Oranye' },
  { hex: '#A3A3A3', name: 'Monokrom' }
]

const CHOSEN_KEY = 'neovarch:theme-chosen'

export const $nvAppearance = atom<NeovarchAppearance | null>(null)

const HEX = /^#?[0-9a-f]{6}$/i

export function normalizeAccent(v: string): null | string {
  const s = v.trim()

  return HEX.test(s) ? `#${s.replace('#', '').toUpperCase()}` : null
}

function mix(hex: string, other: string, t: number): string {
  const a = parseInt(hex.slice(1), 16)
  const b = parseInt(other.slice(1), 16)
  const ch = (shift: number) => Math.round(((a >> shift) & 255) * (1 - t) + ((b >> shift) & 255) * t)

  return `#${[16, 8, 0].map(s => ch(s).toString(16).padStart(2, '0')).join('')}`
}

/** Paint the accent: retint the active skin and the Neovarch brand tokens. */
export function applyAccent(accent: string, base: 'dark' | 'light'): void {
  const root = document.documentElement
  const isDefault = accent.toUpperCase() === DEFAULT_ACCENT
  setAccentOverride(isDefault ? null : accent)

  if (isDefault) {
    for (const k of ['--nv-red', '--nv-red-deep', '--nv-red-text', '--nv-red-wash']) {
      root.style.removeProperty(k)
    }

    return
  }

  root.style.setProperty('--nv-red', accent)
  root.style.setProperty('--nv-red-deep', mix(accent, '#000000', 0.45))
  root.style.setProperty('--nv-red-text', base === 'dark' ? mix(accent, '#ffffff', 0.2) : mix(accent, '#000000', 0.35))
  root.style.setProperty('--nv-red-wash', base === 'dark' ? mix(accent, '#0d0606', 0.82) : mix(accent, '#ffffff', 0.82))
}

async function refresh(): Promise<void> {
  try {
    $nvAppearance.set(await hermesApi<NeovarchAppearance>({ path: '/api/appearance' }))
  } catch {
    // core not up yet; the gateway listener retries
  }
}

onMount($nvAppearance, () => {
  void refresh()
  const off = onGatewayEvent('appearance.changed', event => {
    const p = event.payload as NeovarchAppearance | undefined

    if (p?.accent) {
      $nvAppearance.set(p)
    }
  })
  const offGw = $gateway.listen(() => void refresh())

  return () => {
    off()
    offGw()
  }
})

export async function saveAppearance(next: NeovarchAppearance): Promise<NeovarchAppearance> {
  const saved = await hermesApi<NeovarchAppearance>({
    path: '/api/appearance',
    method: 'PUT',
    body: { accent: next.accent, base: next.base }
  })
  $nvAppearance.set(saved)

  return saved
}

/** Keeps the window painted with the core's appearance (mounted once). */
export function NeovarchAppearanceSync() {
  const appearance = useStore($nvAppearance)
  const { renderedMode, setMode } = useTheme()

  useEffect(() => {
    if (!appearance) {
      return
    }

    applyAccent(appearance.accent, appearance.base)

    if (renderedMode !== appearance.base) {
      setMode(appearance.base)
    }
    // renderedMode is deliberately not a dependency: the rail's sun/moon
    // toggle may flip the mode locally without the core overriding it back.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [appearance, setMode])

  return null
}

/** Accent presets + custom hex + dark/light. Saves to the core on every pick. */
export function NeovarchThemePicker({ compact = false }: { compact?: boolean }) {
  const appearance = useStore($nvAppearance) ?? { accent: DEFAULT_ACCENT, base: 'dark' as const }
  const [custom, setCustom] = useState('')
  const [error, setError] = useState<null | string>(null)

  const pick = async (accent: string, base = appearance.base) => {
    setError(null)

    try {
      await saveAppearance({ accent, base })
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className={cn('nv-theme-picker', compact && 'nv-theme-picker-compact')} data-nv-theme-picker="">
      <div className="nv-theme-swatches">
        {ACCENT_PRESETS.map(p => (
          <button
            aria-pressed={appearance.accent.toUpperCase() === p.hex}
            className="nv-theme-swatch"
            data-nv-accent={p.name}
            key={p.hex}
            onClick={() => void pick(p.hex)}
            type="button"
          >
            <span style={{ background: p.hex }} />
            {p.name}
          </button>
        ))}
      </div>
      <div className="nv-theme-row">
        <input
          className="nv-theme-hex"
          data-nv-field="accent-hex"
          onChange={e => setCustom(e.target.value)}
          placeholder="Hex kustom, mis. #FF0066"
          value={custom}
        />
        <button
          className="nv-theme-apply"
          disabled={!normalizeAccent(custom)}
          onClick={() => void pick(normalizeAccent(custom)!)}
          type="button"
        >
          Pakai
        </button>
        <div className="nv-theme-mode" role="group">
          {(['dark', 'light'] as const).map(b => (
            <button
              aria-pressed={appearance.base === b}
              data-nv-base={b}
              key={b}
              onClick={() => void pick(appearance.accent, b)}
              type="button"
            >
              {b === 'dark' ? 'Gelap' : 'Terang'}
            </button>
          ))}
        </div>
      </div>
      {error && <p className="nv-theme-error">{error}</p>}
    </div>
  )
}

/** First launch: pick a colour once (changeable later in Settings ▸ Tampilan). */
export function NeovarchFirstRunTheme() {
  const [open, setOpen] = useState(() => typeof localStorage !== 'undefined' && !localStorage.getItem(CHOSEN_KEY))

  if (!open) {
    return null
  }

  const done = () => {
    localStorage.setItem(CHOSEN_KEY, '1')
    setOpen(false)
  }

  return (
    <div className="nv-theme-firstrun" data-nv-first-run-theme="" role="dialog">
      <div className="nv-theme-card">
        <p className="nv-theme-kicker">Selamat datang</p>
        <h2>Pilih warna Neovarch</h2>
        <p className="nv-theme-sub">HP yang dipasangkan ikut warna ini. Bisa diganti kapan saja di Pengaturan ▸ Tampilan.</p>
        <NeovarchThemePicker />
        <button className="nv-theme-done" data-nv-theme-done="" onClick={done} type="button">
          Mulai
        </button>
      </div>
    </div>
  )
}

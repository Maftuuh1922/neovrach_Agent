import { useStore } from '@nanostores/react'
import { atom, onMount } from 'nanostores'

import { hermesApi } from '@/api/client'
import { X } from '@/lib/icons'
import { $gateway } from '@/store/gateway'

/** What the core's `GET /api/update` answers (GitHub Releases, cached 6 h). */
export interface NeovarchUpdateInfo {
  available: boolean
  current: string
  download_url: string
  error?: string
  latest: null | string
  url: string
}

const DISMISS_KEY = 'neovarch:update-dismissed'
const RECHECK_MS = 6 * 60 * 60 * 1000

export const $nvUpdate = atom<NeovarchUpdateInfo | null>(null)
const $dismissed = atom<string>(typeof localStorage === 'undefined' ? '' : (localStorage.getItem(DISMISS_KEY) ?? ''))

function platformKey(): string {
  const p = (navigator.userAgent || '').toLowerCase()

  return p.includes('windows') ? 'windows' : p.includes('linux') ? 'linux' : ''
}

async function check(): Promise<void> {
  try {
    $nvUpdate.set(await hermesApi<NeovarchUpdateInfo>({ path: `/api/update?platform=${platformKey()}` }))
  } catch {
    // offline or core still starting: try again on the next tick
  }
}

onMount($nvUpdate, () => {
  void check()
  const timer = window.setInterval(() => void check(), RECHECK_MS)
  const off = $gateway.listen(() => void check())

  return () => {
    window.clearInterval(timer)
    off()
  }
})

/** "Update tersedia vX" — a slim banner above the workspace, linking to the release. */
export function NeovarchUpdateBanner() {
  const info = useStore($nvUpdate)
  const dismissed = useStore($dismissed)

  if (!info?.available || !info.latest || dismissed === info.latest) {
    return null
  }

  const open = () => void window.hermesDesktop?.openExternal?.(info.download_url || info.url)

  return (
    <div className="nv-update-banner" data-nv-update-banner={info.latest} role="status">
      <span className="nv-update-dot" />
      <span>
        Update tersedia <strong>v{info.latest}</strong> <span className="nv-update-muted">(sekarang v{info.current})</span>
      </span>
      <button className="nv-update-link" onClick={open} type="button">
        Unduh
      </button>
      <button
        aria-label="Tutup"
        className="nv-update-close"
        onClick={() => {
          localStorage.setItem(DISMISS_KEY, info.latest ?? '')
          $dismissed.set(info.latest ?? '')
        }}
        type="button"
      >
        <X className="size-3.5" />
      </button>
    </div>
  )
}

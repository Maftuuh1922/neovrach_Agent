import { useStore } from '@nanostores/react'

import { ChevronDown, Search } from '@/lib/icons'
import { openCommandPalette } from '@/store/command-palette'
import { $currentModel, setModelPickerOpen } from '@/store/session'

import { NeovarchWordmark } from './halo-mark'

export const NV_COMMAND_BAR_HEIGHT = 44

/** Last path segment of a model id, e.g. `openrouter/anthropic/x` → `x`. */
export function shortModelName(model: string): string {
  const trimmed = model.trim()

  if (!trimmed) {
    return 'Pilih model'
  }

  const parts = trimmed.split('/')

  return parts[parts.length - 1] || trimmed
}

/**
 * The top command bar: serif wordmark, one wide search / goal field (opens the
 * command palette) and the model picker. It is also the window drag strip, so
 * every control opts out of the drag region.
 */
export function NeovarchCommandBar() {
  const model = useStore($currentModel)

  return (
    <header className="nv-command-bar" data-slot="nv-command-bar" style={{ height: NV_COMMAND_BAR_HEIGHT }}>
      <div className="nv-command-brand">
        <NeovarchWordmark />
      </div>

      <button
        aria-label="Cari sesi, perintah, atau tulis tujuan"
        className="nv-command-search"
        data-slot="nv-command-search"
        onClick={() => openCommandPalette()}
        type="button"
      >
        <Search className="size-3.5 shrink-0" />
        <span className="nv-command-search-text">Cari, perintah, atau tulis tujuan…</span>
        <kbd className="nv-command-kbd">Ctrl K</kbd>
      </button>

      <button
        aria-label="Ganti model"
        className="nv-command-model"
        data-slot="nv-command-model"
        onClick={() => setModelPickerOpen(true)}
        title={model || undefined}
        type="button"
      >
        <span className="nv-command-model-label">MODEL</span>
        <span className="nv-command-model-name">{shortModelName(model)}</span>
        <ChevronDown className="size-3 shrink-0 opacity-70" />
      </button>
    </header>
  )
}

import { Search } from '@/lib/icons'
import { openCommandPalette } from '@/store/command-palette'

import { NeovarchWordmark } from './halo-mark'

export const NV_COMMAND_BAR_HEIGHT = 44

/**
 * The top command bar: serif wordmark and one wide search / goal field (opens
 * the command palette). The model is chosen in one place only, the composer's
 * model picker, so the bar carries no model chip. It is also the window drag
 * strip, so every control opts out of the drag region.
 */
export function NeovarchCommandBar() {
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
    </header>
  )
}

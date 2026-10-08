import { atom } from 'nanostores'

/**
 * Neovarch frame state. The session list is a panel opened from the rail (not
 * Hermes' always-on left sidebar), so its open state lives here.
 */
export const $nvSessionsOpen = atom(false)

export function toggleNvSessions(): void {
  $nvSessionsOpen.set(!$nvSessionsOpen.get())
}

export function closeNvSessions(): void {
  $nvSessionsOpen.set(false)
}

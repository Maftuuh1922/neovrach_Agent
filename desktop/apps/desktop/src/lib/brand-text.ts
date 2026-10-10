/**
 * Display-time branding for text that comes from the core, the Electron main
 * process or upstream error strings ("Hermes backend did not become ready…").
 *
 * The raw text is left untouched where it is produced, because recovery logic
 * classifies errors by matching it (boot-failure-cause, reauth detection,
 * missing-RPC checks). Only what the user reads is rebranded: toasts, the boot
 * failure overlay and boot progress lines. Third-party names that are really
 * someone else's service (Hermes Cloud) and lowercase commands/paths
 * (`hermes update`, ~/.hermes) are kept.
 */
const HERMES_AGENT = /\bHermes Agent\b/g
const HERMES_WORD = /\bHermes\b(?![- ]Cloud\b)/g

export function brandText(text: string): string
export function brandText(text: string | undefined): string | undefined
export function brandText(text: string | null): string | null
export function brandText(text: string | null | undefined): string | null | undefined
export function brandText(text: string | null | undefined): string | null | undefined {
  if (typeof text !== 'string' || !text.includes('Hermes')) {
    return text
  }

  return text.replace(HERMES_AGENT, 'Neovarch').replace(HERMES_WORD, 'Neovarch')
}

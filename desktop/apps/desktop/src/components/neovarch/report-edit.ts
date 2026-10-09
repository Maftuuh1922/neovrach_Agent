/**
 * Live report editing: which document the agent is writing right now, what it
 * reads like after each edit, and which paragraphs the latest edit touched.
 * Derived only from the conversation's tool calls (write_file / patch and
 * their aliases), so it works for any session without a new core event.
 */
import { atom } from 'nanostores'

import type { ChatMessage } from '@/lib/chat-messages/types'

const DOC_PATH = /\.(md|markdown|mdx|txt|rst|adoc|org|html?)$/i

const WRITE_TOOLS = new Set(['create_file', 'write', 'write_file', 'write_to_file'])
const PATCH_TOOLS = new Set(['edit', 'edit_file', 'patch', 'replace_in_file', 'str_replace', 'str_replace_editor'])

export function isReportPath(path: string): boolean {
  return DOC_PATH.test(path.split('?')[0] ?? '')
}

export interface ReportEdit {
  /** Paragraph indexes (in `paragraphs`) the latest edit changed. */
  changed: number[]
  /** Text the latest edit inserted (for the typing reveal). */
  inserted: string
  /** True while the latest edit's tool call has no result yet. */
  live: boolean
  /** The document text is only the edited fragment (base never seen). */
  partial: boolean
  path: string
  paragraphs: string[]
  /** Edits to this document in the conversation, newest last. */
  revision: number
  toolCallId: string
}

/** Split into paragraphs on blank lines; headings and list blocks stay whole. */
export function splitParagraphs(text: string): string[] {
  return text
    .replace(/\r\n/g, '\n')
    .split(/\n{2,}/)
    .map(block => block.replace(/^\n+|\n+$/g, ''))
    .filter(block => block.trim().length > 0)
}

/** Indexes of `next` paragraphs that differ from `prev` (common prefix/suffix trimmed). */
export function changedParagraphs(prev: readonly string[], next: readonly string[]): number[] {
  let start = 0

  while (start < prev.length && start < next.length && prev[start] === next[start]) {
    start++
  }

  let endPrev = prev.length - 1
  let endNext = next.length - 1

  while (endPrev >= start && endNext >= start && prev[endPrev] === next[endNext]) {
    endPrev--
    endNext--
  }

  const out: number[] = []

  for (let i = start; i <= endNext; i++) {
    out.push(i)
  }

  return out
}

function str(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined
}

function pathOf(args: Record<string, unknown>): string | undefined {
  return str(args.path) ?? str(args.file_path) ?? str(args.filepath) ?? str(args.target_file) ?? str(args.filename)
}

interface ToolPart {
  args?: unknown
  result?: unknown
  toolCallId?: string
  toolName?: string
  type?: string
}

/** The latest document edit in the conversation, replaying every earlier edit
 *  to the same file so the preview reads like the document, not a diff. */
export function latestReportEdit(messages: readonly ChatMessage[]): null | ReportEdit {
  const docs = new Map<string, { partial: boolean; revision: number; text: string }>()
  let latest: null | ReportEdit = null

  for (const message of messages) {
    for (const raw of message.parts) {
      const part = raw as ToolPart

      if (part.type !== 'tool-call' || !part.toolName || !part.args || typeof part.args !== 'object') {
        continue
      }

      const name = part.toolName.toLowerCase()
      const isWrite = WRITE_TOOLS.has(name)
      const isPatch = PATCH_TOOLS.has(name)

      if (!isWrite && !isPatch) {
        continue
      }

      const args = part.args as Record<string, unknown>
      const path = pathOf(args)

      if (!path || !isReportPath(path)) {
        continue
      }

      const before = docs.get(path)
      const prevParagraphs = before ? splitParagraphs(before.text) : []
      let text: string
      let inserted: string
      let partial: boolean

      if (isWrite) {
        text = str(args.content) ?? str(args.file_text) ?? str(args.text) ?? ''
        inserted = text
        partial = false
      } else {
        const oldText = str(args.old_string) ?? str(args.old_str) ?? str(args.old_text) ?? ''
        const newText = str(args.new_string) ?? str(args.new_str) ?? str(args.new_text) ?? ''

        inserted = newText

        if (before && oldText && before.text.includes(oldText)) {
          text = before.text.replace(oldText, newText)
          partial = before.partial
        } else if (before && !oldText) {
          text = `${before.text}\n\n${newText}`
          partial = before.partial
        } else {
          text = newText
          partial = true
        }
      }

      const paragraphs = splitParagraphs(text)
      let changed = before && !partial ? changedParagraphs(prevParagraphs, paragraphs) : paragraphs.map((_, i) => i)

      if (isPatch && inserted.trim()) {
        const hit = paragraphs.flatMap((p, i) => (p.includes(inserted.trim().split('\n')[0]!) ? [i] : []))

        if (hit.length) {
          changed = [...new Set([...changed, ...hit])].sort((a, b) => a - b)
        }
      }

      const revision = (before?.revision ?? 0) + 1
      docs.set(path, { partial, revision, text })
      latest = {
        changed,
        inserted,
        live: part.result === undefined,
        partial,
        path,
        paragraphs,
        revision,
        toolCallId: part.toolCallId ?? `${path}#${revision}`
      }
    }
  }

  return latest
}

/* ── Panel state: open/closed is the user's and is remembered ───────────── */

export const REPORT_PANEL_KEY = 'neovarch.desktop.report-panel.v1'

function readOpen(): boolean {
  try {
    return window.localStorage.getItem(REPORT_PANEL_KEY) !== 'closed'
  } catch {
    return true
  }
}

export const $reportPanelOpen = atom<boolean>(typeof window === 'undefined' ? true : readOpen())

export function setReportPanelOpen(open: boolean): void {
  $reportPanelOpen.set(open)

  try {
    window.localStorage.setItem(REPORT_PANEL_KEY, open ? 'open' : 'closed')
  } catch {
    // Storage unavailable: the choice still holds for this run.
  }
}

export function toggleReportPanel(): void {
  setReportPanelOpen(!$reportPanelOpen.get())
}

/** Ctrl+Alt+L (⌘⌥L on macOS): show / hide the report panel. */
export function isReportPanelShortcut(event: Pick<KeyboardEvent, 'altKey' | 'code' | 'ctrlKey' | 'key' | 'metaKey' | 'shiftKey'>): boolean {
  const mod = event.ctrlKey || event.metaKey

  return mod && event.altKey && !event.shiftKey && (event.code === 'KeyL' || event.key.toLowerCase() === 'l')
}

export const REPORT_PANEL_SHORTCUT_LABEL = 'Ctrl+Alt+L'

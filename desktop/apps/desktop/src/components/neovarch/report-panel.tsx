/**
 * Live report preview in the right panel: while an agent writes or patches a
 * document, the document is shown here (not in a modal), the paragraphs the
 * edit touched are highlighted and the new text types itself in. The user can
 * hide / show it (button or Ctrl+Alt+L); that choice is remembered.
 */
import { useStore } from '@nanostores/react'
import { useEffect, useRef, useState } from 'react'

import { FileText, X } from '@/lib/icons'
import { cn } from '@/lib/utils'

import {
  $reportPanelOpen,
  isReportPanelShortcut,
  REPORT_PANEL_SHORTCUT_LABEL,
  type ReportEdit,
  setReportPanelOpen,
  toggleReportPanel
} from './report-edit'

function baseName(path: string): string {
  const parts = path.split(/[\\/]/)

  return parts[parts.length - 1] || path
}

function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && Boolean(window.matchMedia?.('(prefers-reduced-motion: reduce)').matches)
}

/** Characters of `text` revealed so far; restarts when `key` changes. */
export function useTypedReveal(text: string, key: string, animate: boolean): number {
  const [shown, setShown] = useState(animate ? 0 : text.length)

  useEffect(() => {
    if (!animate || prefersReducedMotion() || typeof requestAnimationFrame === 'undefined') {
      setShown(text.length)

      return
    }

    const duration = Math.min(1600, Math.max(350, text.length * 9))
    const start = performance.now()
    let frame = 0

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration)

      setShown(Math.round(text.length * t))

      if (t < 1) {
        frame = requestAnimationFrame(tick)
      }
    }

    setShown(0)
    frame = requestAnimationFrame(tick)

    return () => cancelAnimationFrame(frame)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, animate])

  return Math.min(shown, text.length)
}

/** True for `ms` after `key` changes away from the value it had on mount. */
export function useRecentlyChanged(key: null | string, ms: number): boolean {
  const [mountKey] = useState(key)
  const [recentKey, setRecentKey] = useState<null | string>(null)

  useEffect(() => {
    if (!key || key === mountKey) {
      return
    }

    setRecentKey(key)
    const timer = window.setTimeout(() => setRecentKey(null), ms)

    return () => window.clearTimeout(timer)
  }, [key, mountKey, ms])

  return recentKey !== null && recentKey === key
}

function Paragraph({ animate, revealKey, text }: { animate: boolean; revealKey: string; text: string }) {
  const shown = useTypedReveal(text, revealKey, animate)
  const visible = text.slice(0, shown)
  const heading = /^(#{1,6})\s+/.exec(visible)

  if (heading) {
    const level = Math.min(heading[1]!.length, 3)

    return (
      <span className={cn('nv-report-heading', `nv-report-h${level}`)}>
        {visible.slice(heading[0].length)}
        {shown < text.length && <i aria-hidden="true" className="nv-report-caret" />}
      </span>
    )
  }

  return (
    <>
      {visible}
      {shown < text.length && <i aria-hidden="true" className="nv-report-caret" />}
    </>
  )
}

export function ReportPanel({ edit, editing }: { edit: ReportEdit; editing: boolean }) {
  const open = useStore($reportPanelOpen)
  const bodyRef = useRef<HTMLDivElement>(null)
  const revealKey = `${edit.toolCallId}:${edit.revision}`
  const firstChanged = edit.changed[0]
  const lastChanged = edit.changed[edit.changed.length - 1]

  useEffect(() => {
    if (!open || firstChanged === undefined) {
      return
    }

    const target = bodyRef.current?.querySelector<HTMLElement>(`[data-report-paragraph="${firstChanged}"]`)

    target?.scrollIntoView?.({ behavior: prefersReducedMotion() ? 'auto' : 'smooth', block: 'center' })
  }, [open, revealKey, firstChanged])

  if (!open) {
    return (
      <button
        className="nv-report-reopen"
        data-live={editing || undefined}
        data-slot="nv-report-reopen"
        onClick={() => setReportPanelOpen(true)}
        title={`Tampilkan laporan (${REPORT_PANEL_SHORTCUT_LABEL})`}
        type="button"
      >
        <FileText className="size-3.5 shrink-0" />
        <span className="nv-report-reopen-name">{baseName(edit.path)}</span>
        {editing && <i aria-hidden="true" className="nv-sender-live" />}
        <span className="nv-report-reopen-cta">Buka</span>
      </button>
    )
  }

  return (
    <section
      aria-label={`Laporan ${baseName(edit.path)}`}
      className="nv-context-card nv-report-card"
      data-editing={editing || undefined}
      data-slot="nv-report-panel"
    >
      <header className="nv-report-head">
        <FileText className="size-3.5 shrink-0" />
        <span className="nv-report-name" title={edit.path}>
          {baseName(edit.path)}
        </span>
        <span className="nv-report-state" data-live={editing || undefined}>
          {editing ? 'menyunting…' : `rev ${edit.revision}`}
        </span>
        <button
          aria-label={`Sembunyikan laporan (${REPORT_PANEL_SHORTCUT_LABEL})`}
          className="nv-icon-button nv-report-close"
          onClick={() => setReportPanelOpen(false)}
          title={`Sembunyikan (${REPORT_PANEL_SHORTCUT_LABEL})`}
          type="button"
        >
          <X className="size-3.5" />
        </button>
      </header>
      {edit.partial && <p className="nv-report-note">Cuplikan bagian yang diubah.</p>}
      <div className="nv-report-body" ref={bodyRef}>
        {edit.paragraphs.map((text, index) => {
          const changed = edit.changed.includes(index)

          return (
            <p
              className={cn('nv-report-p', changed && 'nv-report-hl')}
              data-changed={changed || undefined}
              data-report-paragraph={index}
              key={changed ? `${revealKey}:${index}` : `p:${index}:${text.length}`}
            >
              <Paragraph animate={changed && editing && index === lastChanged} revealKey={revealKey} text={text} />
            </p>
          )
        })}
      </div>
    </section>
  )
}

/** Window-level Ctrl+Alt+L while the panel's host is mounted. */
export function useReportPanelShortcut(enabled: boolean): void {
  useEffect(() => {
    if (!enabled) {
      return
    }

    const onKey = (event: KeyboardEvent) => {
      if (isReportPanelShortcut(event)) {
        event.preventDefault()
        toggleReportPanel()
      }
    }

    window.addEventListener('keydown', onKey)

    return () => window.removeEventListener('keydown', onKey)
  }, [enabled])
}

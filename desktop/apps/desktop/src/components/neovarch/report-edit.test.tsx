// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, describe, expect, it } from 'vitest'

import type { ChatMessage } from '@/lib/chat-messages/types'
import { $messages } from '@/store/session'

import { NeovarchContextRail } from './context-rail'
import {
  $reportPanelOpen,
  changedParagraphs,
  isReportPanelShortcut,
  isReportPath,
  latestReportEdit,
  REPORT_PANEL_KEY,
  setReportPanelOpen,
  splitParagraphs
} from './report-edit'

function tool(id: string, toolName: string, args: Record<string, unknown>, done = true): ChatMessage {
  return {
    id: `m-${id}`,
    parts: [
      {
        args,
        argsText: JSON.stringify(args),
        toolCallId: id,
        toolName,
        type: 'tool-call',
        ...(done ? { result: 'ok' } : {})
      }
    ],
    role: 'assistant'
  } as unknown as ChatMessage
}

const DOC = '# Laporan Q3\n\nPenjualan naik.\n\nBiaya stabil.'

afterEach(() => {
  cleanup()
  $messages.set([])
  setReportPanelOpen(true)
  window.localStorage.clear()
})

describe('report edit model', () => {
  it('recognises document paths only', () => {
    expect(isReportPath('/tmp/laporan.md')).toBe(true)
    expect(isReportPath('notes.TXT')).toBe(true)
    expect(isReportPath('src/app.ts')).toBe(false)
  })

  it('splits paragraphs and finds the changed ones', () => {
    expect(splitParagraphs(DOC)).toEqual(['# Laporan Q3', 'Penjualan naik.', 'Biaya stabil.'])
    expect(changedParagraphs(['a', 'b', 'c'], ['a', 'B', 'c'])).toEqual([1])
    expect(changedParagraphs(['a', 'b'], ['a', 'b', 'c'])).toEqual([2])
  })

  it('replays write + patch so the preview is the document with the edited paragraph marked', () => {
    const messages = [
      tool('t1', 'write_file', { content: DOC, path: '/w/laporan.md' }),
      tool('t2', 'patch', { new_string: 'Penjualan naik 12%.', old_string: 'Penjualan naik.', path: '/w/laporan.md' }, false)
    ]

    const edit = latestReportEdit(messages)!

    expect(edit.path).toBe('/w/laporan.md')
    expect(edit.paragraphs).toEqual(['# Laporan Q3', 'Penjualan naik 12%.', 'Biaya stabil.'])
    expect(edit.changed).toEqual([1])
    expect(edit.live).toBe(true)
    expect(edit.partial).toBe(false)
    expect(edit.revision).toBe(2)
  })

  it('a patch with no known base is a partial fragment; code files are ignored', () => {
    expect(latestReportEdit([tool('t1', 'write_file', { content: 'x', path: 'a.ts' })])).toBeNull()
    const edit = latestReportEdit([tool('t1', 'edit_file', { new_string: 'Baru.', old_string: 'Lama.', path: 'r.md' })])!

    expect(edit.partial).toBe(true)
    expect(edit.paragraphs).toEqual(['Baru.'])
  })

  it('shortcut is Ctrl/Cmd+Alt+L', () => {
    const base = { altKey: true, code: 'KeyL', ctrlKey: true, key: 'l', metaKey: false, shiftKey: false }

    expect(isReportPanelShortcut(base)).toBe(true)
    expect(isReportPanelShortcut({ ...base, altKey: false })).toBe(false)
    expect(isReportPanelShortcut({ ...base, ctrlKey: false, metaKey: true })).toBe(true)
  })
})

describe('report panel in the right rail', () => {
  function renderRail() {
    return render(
      <MemoryRouter initialEntries={['/']}>
        <NeovarchContextRail />
      </MemoryRouter>
    )
  }

  it('opens in the right panel while the agent edits, highlights the change and folds the other cards', () => {
    $messages.set([
      tool('t1', 'write_file', { content: DOC, path: '/w/laporan.md' }),
      tool('t2', 'patch', { new_string: 'Biaya turun 3%.', old_string: 'Biaya stabil.', path: '/w/laporan.md' }, false)
    ])
    const { container } = renderRail()
    const panel = container.querySelector('[data-slot="nv-report-panel"]') as HTMLElement

    expect(panel).not.toBeNull()
    expect(panel.closest('[data-slot="nv-context-rail"]')).not.toBeNull()
    expect(document.querySelector('[role="dialog"]')).toBeNull()
    expect(screen.getByText('menyunting…')).toBeTruthy()
    expect(container.querySelector('[data-report-paragraph="2"]')?.getAttribute('data-changed')).toBe('true')
    expect(container.querySelector('[data-report-paragraph="1"]')?.hasAttribute('data-changed')).toBe(false)
    expect(container.querySelector('[data-slot="nv-context-rail"]')?.hasAttribute('data-cards-collapsed')).toBe(true)
  })

  it('can be hidden with the button or the shortcut, and the choice is remembered', () => {
    $messages.set([tool('t1', 'write_file', { content: DOC, path: '/w/laporan.md' })])
    const { container } = renderRail()

    fireEvent.click(screen.getByLabelText('Sembunyikan laporan (Ctrl+Alt+L)'))
    expect($reportPanelOpen.get()).toBe(false)
    expect(window.localStorage.getItem(REPORT_PANEL_KEY)).toBe('closed')
    expect(container.querySelector('[data-slot="nv-report-panel"]')).toBeNull()
    expect(container.querySelector('[data-slot="nv-report-reopen"]')).not.toBeNull()

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { altKey: true, code: 'KeyL', ctrlKey: true, key: 'l' }))
    })
    expect($reportPanelOpen.get()).toBe(true)
    expect(window.localStorage.getItem(REPORT_PANEL_KEY)).toBe('open')
    expect(container.querySelector('[data-slot="nv-report-panel"]')).not.toBeNull()
  })
})

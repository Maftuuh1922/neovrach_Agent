// @vitest-environment jsdom
import { cleanup, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, describe, expect, it } from 'vitest'

import { $currentModel, $currentProvider } from '@/store/session'

import { NeovarchCommandBar } from './command-bar'
import { NeovarchContextRail } from './context-rail'
import { $modelSheetAccessory, ModelSheetHead, modelSheetKicker, registerModelSheetAccessory } from './model-sheet'
import { $office, type OfficeSnapshot } from './office-store'

afterEach(() => {
  cleanup()
  $office.set(null)
  registerModelSheetAccessory(null)
  $currentModel.set('')
  $currentProvider.set('')
})

const OFFICE: OfficeSnapshot = {
  agents: [
    {
      current_task: null,
      current_tool: null,
      id: 'session:s1',
      kind: 'session',
      last_activity: 0,
      last_activity_text: null,
      message_count: 0,
      model: 'oc/big-pickle',
      name: 'Raka',
      pending_approval: null,
      role: 'Agen utama',
      session_id: 's1',
      source: 'desktop',
      status: 'idle',
      title: null
    }
  ],
  counts: { idle: 1, total: 1, 'waiting-approval': 0, working: 0 },
  feed: [],
  generated_at: 0,
  host: 'pc',
  kanban: {},
  seq: 1,
  vault: { configured: false, connected: false, note_count: 0, path: '' }
}

describe('single model selector', () => {
  it('the top command bar has no model chip', () => {
    const { container } = render(<NeovarchCommandBar />)

    expect(container.querySelector('[data-slot="nv-command-model"]')).toBeNull()
    expect(screen.queryByText('MODEL')).toBeNull()
    expect(screen.getByLabelText('Cari sesi, perintah, atau tulis tujuan')).toBeTruthy()
  })

  it('the right panel Model card is read-only info with the friendly name and raw id', () => {
    $currentModel.set('anthropic/claude-sonnet-4.5')
    $currentProvider.set('openrouter')

    const { container } = render(
      <MemoryRouter initialEntries={['/']}>
        <NeovarchContextRail />
      </MemoryRouter>
    )

    const card = container.querySelector('[data-slot="nv-context-model"]') as HTMLElement

    expect(card).not.toBeNull()
    expect(card.tagName).toBe('P')
    expect(card.querySelector('button')).toBeNull()
    expect(card.textContent).toContain('anthropic/claude-sonnet-4.5')
    expect(container.querySelector('.nv-context-model-name')?.textContent).not.toBe('anthropic/claude-sonnet-4.5')
    expect(screen.getByText('Ganti model lewat pemilih model di kolom chat.')).toBeTruthy()
  })

  it('sheet kicker names the default PC or the session agent', () => {
    expect(modelSheetKicker(null)).toBe('model · default PC')
    expect(modelSheetKicker('Raka')).toBe('model · Raka')

    $office.set(OFFICE)
    render(<ModelSheetHead sessionIds={['s1']} />)
    expect(screen.getByText('model · Raka')).toBeTruthy()
    expect(screen.getByText('Pilih model')).toBeTruthy()
  })

  it('9Router hook: a registered accessory renders under the sheet title', () => {
    registerModelSheetAccessory(() => <span>9Router aktif</span>)
    expect($modelSheetAccessory.get()).not.toBeNull()
    render(<ModelSheetHead sessionIds={[null]} />)
    expect(screen.getByText('model · default PC')).toBeTruthy()
    expect(screen.getByText('9Router aktif')).toBeTruthy()
  })
})

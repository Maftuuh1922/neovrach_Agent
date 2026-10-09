// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import type { OfficeSnapshot } from './office-store'

const scene = vi.hoisted(() => ({
  created: [] as { options: { framing?: string; onSelect?: (id: null | string) => void; reducedMotion?: boolean } }[],
  dispose: vi.fn(),
  fail: false,
  resetCamera: vi.fn(),
  setAgents: vi.fn(),
  setPaused: vi.fn(),
  setSelected: vi.fn()
}))

vi.mock('./office3d-scene', () => ({
  createOfficeScene: (options: { framing?: string; onSelect?: (id: null | string) => void; reducedMotion?: boolean }) => {
    if (scene.fail) {
      throw new Error('WebGL context lost')
    }

    scene.created.push({ options })

    return {
      dispose: scene.dispose,
      resetCamera: scene.resetCamera,
      setAgents: scene.setAgents,
      setPaused: scene.setPaused,
      setSelected: scene.setSelected
    }
  }
}))

const rest = vi.hoisted(() => vi.fn())

vi.mock('@/api/plugins', () => ({ pluginRest: rest }))

// The store subscribes to the gateway on mount; keep it inert here.
vi.mock('@/store/gateway', async () => {
  const { atom } = await import('nanostores')

  return { $gateway: atom(null) }
})

const { $office, $officeView, OFFICE_VIEW_KEY, setOfficeView } = await import('./office-store')
const { NeovarchOfficePage } = await import('./office')

const SNAP: OfficeSnapshot = {
  agents: [
    {
      current_task: 'Tulis laporan',
      current_tool: null,
      id: 'session:a',
      kind: 'session',
      last_activity: 0,
      last_activity_text: null,
      message_count: 2,
      model: 'm',
      name: 'Sari',
      pending_approval: null,
      role: 'Agen utama',
      session_id: 'a',
      source: 'desktop',
      status: 'working',
      title: null
    }
  ],
  counts: { idle: 0, total: 1, 'waiting-approval': 0, working: 1 },
  feed: [],
  generated_at: 0,
  host: 'pc',
  kanban: {},
  seq: 1,
  vault: { configured: false, connected: false, note_count: 0, path: '' }
}

let webgl = false

function renderPage() {
  return render(
    <MemoryRouter>
      <NeovarchOfficePage />
    </MemoryRouter>
  )
}

beforeEach(() => {
  window.localStorage.clear()
  $officeView.set('3d')
  webgl = false
  scene.created.length = 0
  vi.clearAllMocks()
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(((kind: string) =>
    webgl && kind.startsWith('webgl') ? ({} as WebGLRenderingContext) : null) as never)
})

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})

describe('Kantor view toggle', () => {
  it('defaults to 3D', () => {
    webgl = true
    renderPage()
    act(() => $office.set(SNAP))

    expect(screen.getByRole('button', { name: '3D' }).getAttribute('aria-pressed')).toBe('true')
    expect(document.querySelector('[data-slot="nv-office3d"]')).not.toBeNull()
  })

  it('switches to the list and remembers the choice', () => {
    webgl = true
    renderPage()
    act(() => $office.set(SNAP))
    fireEvent.click(screen.getByRole('button', { name: 'Daftar' }))

    expect(document.querySelector('[data-slot="nv-office3d"]')).toBeNull()
    expect(document.querySelector('[data-nv-desk="session:a"]')).not.toBeNull()
    expect(window.localStorage.getItem(OFFICE_VIEW_KEY)).toBe('list')
    expect(screen.getByRole('button', { name: 'Daftar' }).getAttribute('aria-pressed')).toBe('true')
  })

  it('falls back to the list when WebGL is unavailable', () => {
    webgl = false
    renderPage()
    act(() => $office.set(SNAP))

    expect(document.querySelector('[data-slot="nv-office3d-fallback"]')).not.toBeNull()
    expect(screen.getByRole('status').textContent).toContain('WebGL')
    expect(document.querySelector('[data-nv-desk="session:a"]')).not.toBeNull()
    expect(scene.created).toHaveLength(0)
  })
})

describe('Kantor 3D scene wiring', () => {
  it('lazy-loads the scene, feeds it every live update, and disposes it', async () => {
    webgl = true
    act(() => $office.set(SNAP))
    const view = renderPage()

    await waitFor(() => expect(scene.created).toHaveLength(1))
    await waitFor(() => expect(scene.setAgents).toHaveBeenCalled())
    expect(scene.setAgents.mock.lastCall![0]).toMatchObject([{ id: 'session:a', status: 'working' }])

    act(() => $office.set({ ...SNAP, agents: [{ ...SNAP.agents[0]!, status: 'waiting-approval' }], seq: 2 }))
    await waitFor(() => expect(scene.setAgents.mock.lastCall![0]).toMatchObject([{ status: 'waiting' }]))
    expect(document.querySelector('[data-agent-label="session:a"]')?.getAttribute('data-status')).toBe('waiting')

    view.unmount()
    expect(scene.dispose).toHaveBeenCalled()
  })

  it('frames room + garden, re-frames on "Atur ulang kamera", and passes reduced motion (no strolls)', async () => {
    webgl = true
    vi.stubGlobal('matchMedia', (query: string) => ({ matches: query.includes('reduce'), media: query }))
    act(() => $office.set(SNAP))
    renderPage()

    await waitFor(() => expect(scene.created).toHaveLength(1))
    expect(scene.created[0]!.options.framing).toBe('all')
    expect(scene.created[0]!.options.reducedMotion).toBe(true)

    fireEvent.click(await screen.findByRole('button', { name: 'Atur ulang kamera' }))
    expect(scene.resetCamera).toHaveBeenCalledTimes(1)
    vi.unstubAllGlobals()
  })

  it('opens the agent popover on pick and creates an assigned Kanban task', async () => {
    webgl = true
    act(() => $office.set(SNAP))
    renderPage()
    await waitFor(() => expect(scene.created).toHaveLength(1))

    act(() => scene.created[0]!.options.onSelect?.('session:a'))
    const dialog = await screen.findByRole('dialog', { name: 'Agen Sari' })
    expect(dialog.textContent).toContain('Buka sesi')

    rest.mockResolvedValueOnce({ task: { id: 't1' } })
    fireEvent.change(screen.getByLabelText('Kasih tugas'), { target: { value: '  Rapikan README  ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Kasih tugas' }))

    await waitFor(() =>
      expect(rest).toHaveBeenCalledWith('kanban', '/tasks', {
        body: { assignee: 'Sari', title: 'Rapikan README' },
        method: 'POST'
      })
    )
    expect(await screen.findByText('Tugas dikirim ke Sari.')).toBeTruthy()
  })

  it('shows the list instead when the scene fails to start', async () => {
    webgl = true
    scene.fail = true
    act(() => $office.set(SNAP))
    renderPage()

    expect(await screen.findByRole('status')).toBeTruthy()
    expect(document.querySelector('[data-slot="nv-office3d-fallback"]')).not.toBeNull()
    expect(document.querySelector('[data-nv-desk="session:a"]')).not.toBeNull()
    scene.fail = false
  })
})

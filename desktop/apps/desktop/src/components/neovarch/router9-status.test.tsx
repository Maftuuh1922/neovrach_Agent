// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { emitGatewayEvent } from '@/contrib/events'
import { $gateway } from '@/store/gateway'
import {
  $routerBusy,
  $routerError,
  $routerStatus,
  createGatewayOfficeModelAdapter,
  freeModelSet,
  refreshRouterStatus,
  routerPrimaryAction,
  routerStateLabel,
  type RouterStatus
} from '@/store/router9'

import { isFreeRouterModel, router9RowBadge } from './router9-row-badge'
import { Router9Card, Router9MenuRow } from './router9-status'

const openExternal = vi.fn()

vi.mock('@/lib/external-link', async importOriginal => ({
  ...(await importOriginal<Record<string, unknown>>()),
  openExternalLink: (href: string) => openExternal(href)
}))

function status(patch: Partial<RouterStatus> = {}, setup: Partial<RouterStatus['setup']> = {}): RouterStatus {
  return {
    state: 'running',
    installed: true,
    running: true,
    managed: false,
    pid: null,
    base_url: 'http://localhost:20128/v1',
    dashboard_url: 'http://localhost:20128/dashboard',
    version: '0.5.99',
    binary: '/usr/bin/9router',
    has_api_key: true,
    autostart: true,
    error: null,
    ...patch,
    setup: {
      ready: true,
      action: null,
      message: null,
      action_url: null,
      install_command: 'npm install -g 9router',
      ...setup
    }
  }
}

const READY = status()

const STOPPED = status(
  { state: 'stopped', running: false, version: null },
  { ready: false, action: 'start', message: '9Router berhenti. Tekan Jalankan untuk menyalakannya.' }
)

const NOT_INSTALLED = status(
  { state: 'not_installed', installed: false, running: false, binary: null, version: null },
  { ready: false, action: 'install', message: '9Router belum terpasang. Jalankan: npm install -g 9router' }
)

const NEEDS_KEY = status(
  { has_api_key: false },
  {
    ready: false,
    action: 'api_key',
    message: '9Router berjalan, tetapi Neovarch belum punya API key-nya.',
    action_url: 'http://localhost:20128/dashboard'
  }
)

function fakeGateway(handler: (method: string, params: Record<string, unknown>) => unknown) {
  const request = vi.fn(async (method: string, params: Record<string, unknown> = {}) => handler(method, params))
  $gateway.set({ request } as never)

  return request
}

beforeEach(() => {
  openExternal.mockReset()
  $routerStatus.set(null)
  $routerError.set(null)
  $routerBusy.set('')
})

afterEach(() => {
  cleanup()
  $gateway.set(null as never)
})

describe('router9 store', () => {
  it('maps each setup action to one Indonesian one-tap action', () => {
    expect(routerPrimaryAction(READY)).toBeNull()
    expect(routerPrimaryAction(null)).toBeNull()
    expect(routerPrimaryAction(STOPPED)).toEqual({ kind: 'start', label: 'Jalankan' })
    expect(routerPrimaryAction(NOT_INSTALLED)).toEqual({ kind: 'copy', label: 'Salin perintah pasang' })
    expect(routerPrimaryAction(NEEDS_KEY)).toEqual({ kind: 'dashboard', label: 'Buka dashboard 9Router' })
    expect(routerStateLabel(READY)).toBe('Berjalan')
    expect(routerStateLabel(NEEDS_KEY)).toBe('Berjalan \u00b7 perlu API key')
    expect(routerStateLabel(NOT_INSTALLED)).toBe('Belum terpasang')
    expect(routerStateLabel(STOPPED)).toBe('Berhenti')
  })

  it('refreshes over router.status and follows live router.status events', async () => {
    const request = fakeGateway(() => STOPPED)

    await refreshRouterStatus()
    expect(request).toHaveBeenCalledWith('router.status', {})
    expect($routerStatus.get()?.state).toBe('stopped')

    const off = $routerStatus.listen(() => undefined)
    act(() => emitGatewayEvent({ payload: READY, session_id: null, type: 'router.status' } as never))
    expect($routerStatus.get()?.setup.ready).toBe(true)
    off()
  })

  it('reads the free 9Router models from model.options and badges them', () => {
    expect(freeModelSet([{ slug: '9router', free_models: ['oc/big-pickle'] }, { slug: 'openai' }])).toEqual(
      new Set(['oc/big-pickle'])
    )
    expect(freeModelSet(undefined).size).toBe(0)
    expect(isFreeRouterModel('9router', 'oc/big-pickle')).toBe(true)
    expect(isFreeRouterModel('9router', 'kr/glm-5')).toBe(false)
    expect(isFreeRouterModel('openai', 'oc/x')).toBe(false)
    expect(router9RowBadge.decorate({ label: 'big-pickle', model: 'oc/big-pickle', provider: '9router' })).toEqual({
      badge: 'Gratis'
    })
    expect(router9RowBadge.decorate({ label: 'x', model: 'kr/glm-5', provider: '9router' })).toBeNull()
  })

  it('gives the Office a per-agent model adapter over the gateway', async () => {
    const request = fakeGateway(method =>
      method === 'models.list'
        ? {
            models: [
              { id: 'oc/big-pickle', label: 'big-pickle', provider: '9router', free: true },
              { id: 'kr/glm-5', label: 'glm-5', provider: '9router', free: false }
            ]
          }
        : { ok: true }
    )

    const adapter = createGatewayOfficeModelAdapter()
    expect(adapter.available).toBe(true)
    expect(await adapter.listModels()).toEqual([
      { id: 'oc/big-pickle', label: 'big-pickle \u00b7 gratis', provider: '9router' },
      { id: 'kr/glm-5', label: 'glm-5', provider: '9router' }
    ])
    await adapter.setAgentModel({ id: 'session:abc' }, 'kr/glm-5', '9router')
    expect(request).toHaveBeenLastCalledWith('agent.model.set', {
      agent_id: 'session:abc',
      model: 'kr/glm-5',
      provider: '9router'
    })
    $gateway.set(null as never)
    expect(createGatewayOfficeModelAdapter().available).toBe(false)
  })
})

describe('Router9Card (Settings ▸ Model)', () => {
  it('shows the running state, version and the dashboard button, with no model selector', async () => {
    fakeGateway(() => READY)
    render(<Router9Card />)

    await waitFor(() => expect(screen.getByText('Berjalan')).toBeTruthy())
    expect(screen.getByText('v0.5.99')).toBeTruthy()
    expect(screen.queryByRole('combobox')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /Buka dashboard 9Router/ }))
    expect(openExternal).toHaveBeenCalledWith('http://localhost:20128/dashboard')
  })

  it('starts a stopped 9Router with one tap', async () => {
    const request = fakeGateway(method => (method === 'router.start' ? READY : STOPPED))
    render(<Router9Card />)

    const start = await screen.findByRole('button', { name: /Jalankan/ })
    fireEvent.click(start)
    await waitFor(() => expect(request).toHaveBeenCalledWith('router.start', {}))
    await waitFor(() => expect(screen.getByText('Berjalan')).toBeTruthy())
  })

  it('asks for the API key via the dashboard and saves a pasted key', async () => {
    const request = fakeGateway(method => (method === 'router.config' ? READY : NEEDS_KEY))
    render(<Router9Card />)

    await screen.findByText(/belum punya API key/)
    expect(screen.getAllByRole('button', { name: /Buka dashboard 9Router/ }).length).toBeGreaterThan(0)
    fireEvent.change(screen.getByLabelText('API key 9Router'), { target: { value: ' sk-9r-abc ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Simpan' }))
    await waitFor(() => expect(request).toHaveBeenCalledWith('router.config', { api_key: 'sk-9r-abc' }))
    await waitFor(() => expect(screen.queryByLabelText('API key 9Router')).toBeNull())
  })

  it('shows the install command when 9Router is not installed', async () => {
    fakeGateway(() => NOT_INSTALLED)
    render(<Router9Card />)

    await screen.findByText('Belum terpasang')
    expect(screen.getAllByText(/npm install -g 9router/).length).toBeGreaterThan(0)
    expect(screen.getByRole('button', { name: /Salin perintah pasang/ })).toBeTruthy()
  })

  it('reports a failed start', async () => {
    fakeGateway(method => {
      if (method === 'router.start') {
        throw new Error('9Router berhenti saat dinyalakan (kode 1)')
      }

      return STOPPED
    })
    render(<Router9Card />)

    fireEvent.click(await screen.findByRole('button', { name: /Jalankan/ }))
    expect((await screen.findByRole('alert')).textContent).toContain('kode 1')
  })
})

describe('Router9MenuRow (top of the composer model picker)', () => {
  function renderMenu() {
    return render(
      <DropdownMenu open>
        <DropdownMenuTrigger>model</DropdownMenuTrigger>
        <DropdownMenuContent>
          <Router9MenuRow />
        </DropdownMenuContent>
      </DropdownMenu>
    )
  }

  it('is absent when 9Router is ready', () => {
    $routerStatus.set(READY)
    renderMenu()
    expect(document.querySelector('[data-slot="model-menu-router9"]')).toBeNull()
  })

  it('offers the dashboard when 9Router needs a key, in one tap', () => {
    fakeGateway(() => NEEDS_KEY)
    $routerStatus.set(NEEDS_KEY)
    renderMenu()
    const row = document.querySelector<HTMLElement>('[data-slot="model-menu-router9"]')!

    expect(row.textContent).toContain('Buka dashboard 9Router')
    fireEvent.click(row)
    expect(openExternal).toHaveBeenCalledWith('http://localhost:20128/dashboard')
  })

  it('starts 9Router from the picker when it is stopped', async () => {
    const request = fakeGateway(method => (method === 'router.start' ? READY : STOPPED))
    $routerStatus.set(STOPPED)
    renderMenu()
    fireEvent.click(document.querySelector<HTMLElement>('[data-slot="model-menu-router9"]')!)
    await waitFor(() => expect(request).toHaveBeenCalledWith('router.start', {}))
  })
})

/**
 * 9Router — the built-in, default model provider (local OpenAI-compatible router,
 * https://9router.com). The core detects, starts and supervises it and hands its
 * state to us over the gateway (contract: docs/9router.md):
 *
 *   RPC  router.status | router.start | router.stop | router.config | models.list
 *        agent.model.set
 *   events  router.status (RouterStatus) · models.changed · agent.model.changed
 *
 * The desktop has ONE model selector (the composer picker). This store only feeds
 * it (status row, "Gratis" badges) and the read-only 9Router card in Settings.
 */
import { atom, onMount } from 'nanostores'

import { onGatewayEvent } from '@/contrib/events'
import { openExternalLink } from '@/lib/external-link'
import { $gateway } from '@/store/gateway'

export type RouterState = 'error' | 'not_installed' | 'running' | 'starting' | 'stopped'
export type RouterSetupAction = 'api_key' | 'install' | 'provider' | 'start' | null

export interface RouterStatus {
  state: RouterState
  installed: boolean
  running: boolean
  managed: boolean
  pid: null | number
  base_url: string
  dashboard_url: string
  version: null | string
  binary: null | string
  has_api_key: boolean
  autostart: boolean
  error: null | string
  setup: {
    ready: boolean
    action: RouterSetupAction
    message: null | string
    action_url: null | string
    install_command: string
  }
}

export interface RouterModelEntry {
  id: string
  label: string
  provider: string
  provider_label: string
  group: string
  alias: null | string
  free: boolean
  recommended: boolean
  context_length: null | number
}

export interface ModelRef {
  model: string
  provider: string
}

export interface RouterModelsResult {
  models: RouterModelEntry[]
  default: ModelRef
  router: RouterStatus
  error: null | string
}

type Request = <T>(method: string, params?: Record<string, unknown>) => Promise<T>

export const INSTALL_COMMAND = 'npm install -g 9router'
export const DEFAULT_DASHBOARD = 'http://localhost:20128/dashboard'

export const $routerStatus = atom<null | RouterStatus>(null)
export const $routerBusy = atom<'' | 'config' | 'start' | 'stop'>('')
export const $routerError = atom<null | string>(null)

function gatewayRequest(): null | Request {
  const gateway = $gateway.get() as null | { request?: Request }

  return gateway?.request ? (gateway.request.bind(gateway) as Request) : null
}

function message(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
}

export async function refreshRouterStatus(request: null | Request = gatewayRequest()): Promise<null | RouterStatus> {
  if (!request) {
    return null
  }

  try {
    const status = await request<RouterStatus>('router.status', {})
    $routerStatus.set(status)
    $routerError.set(null)

    return status
  } catch (err) {
    $routerError.set(message(err))

    return null
  }
}

async function run(
  busy: 'config' | 'start' | 'stop',
  method: string,
  params: Record<string, unknown>,
  request: null | Request
): Promise<null | RouterStatus> {
  if (!request || $routerBusy.get()) {
    return null
  }

  $routerBusy.set(busy)
  $routerError.set(null)

  try {
    const status = await request<RouterStatus>(method, params)
    $routerStatus.set(status)

    if (status.state === 'error' && status.error) {
      $routerError.set(status.error)
    }

    return status
  } catch (err) {
    $routerError.set(message(err))

    return null
  } finally {
    $routerBusy.set('')
  }
}

export const startRouter = (request: null | Request = gatewayRequest()) => run('start', 'router.start', {}, request)
export const stopRouter = (request: null | Request = gatewayRequest()) => run('stop', 'router.stop', {}, request)

export const saveRouterApiKey = (apiKey: string, request: null | Request = gatewayRequest()) =>
  run('config', 'router.config', { api_key: apiKey.trim() }, request)

export const setRouterAutostart = (autostart: boolean, request: null | Request = gatewayRequest()) =>
  run('config', 'router.config', { autostart }, request)

export function openRouterDashboard(status: null | RouterStatus = $routerStatus.get()): void {
  openExternalLink(status?.setup.action_url || status?.dashboard_url || DEFAULT_DASHBOARD)
}

/** What the one-tap button next to the status should do, in Indonesian. */
export function routerPrimaryAction(
  status: null | RouterStatus
): null | { kind: 'copy' | 'dashboard' | 'start'; label: string } {
  if (!status || status.setup.ready) {
    return null
  }

  switch (status.setup.action) {
    case 'start':
      return status.installed ? { kind: 'start', label: 'Jalankan' } : { kind: 'dashboard', label: 'Buka dashboard 9Router' }

    case 'install':
      return { kind: 'copy', label: 'Salin perintah pasang' }

    case 'api_key':

    case 'provider':
      return { kind: 'dashboard', label: 'Buka dashboard 9Router' }

    default:
      return null
  }
}

/** Short Indonesian state label for the badge. */
export function routerStateLabel(status: null | RouterStatus): string {
  if (!status) {
    return 'Memeriksa\u2026'
  }

  if (status.running) {
    return status.setup.ready ? 'Berjalan' : 'Berjalan \u00b7 perlu API key'
  }

  return (
    {
      error: 'Gagal',
      not_installed: 'Belum terpasang',
      running: 'Berjalan',
      starting: 'Menyalakan\u2026',
      stopped: 'Berhenti'
    } satisfies Record<RouterState, string>
  )[status.state]
}

/** The 9Router row's free models (from `model.options`), for "Gratis" badges. */
export function freeModelSet(providers: readonly { slug: string; free_models?: string[] }[] | undefined): Set<string> {
  return new Set(providers?.find(p => p.slug === '9router')?.free_models ?? [])
}

/**
 * Office per-agent model adapter backed by the gateway (structurally the
 * `OfficeModelAdapter` the Office popover consumes): lists the live models and
 * sets an agent's own model. The change comes back on the desk's `model` field
 * in the next `office.update`, on the PC and the phone alike.
 */
export function createGatewayOfficeModelAdapter(request: null | Request = gatewayRequest()) {
  return {
    available: Boolean(request),
    listModels: async () => {
      if (!request) {
        return []
      }

      const res = await request<RouterModelsResult>('models.list', {})

      return res.models.map(m => ({
        id: m.id,
        label: m.free ? `${m.label} \u00b7 gratis` : m.label,
        provider: m.provider
      }))
    },
    setAgentModel: async (agent: { id: string }, model: string, provider?: string) => {
      if (!request) {
        throw new Error('Gateway belum terhubung')
      }

      await request('agent.model.set', { agent_id: agent.id, model, ...(provider ? { provider } : {}) })
    }
  }
}

onMount($routerStatus, () => {
  void refreshRouterStatus()

  const offStatus = onGatewayEvent('router.status', event => {
    const payload = (event as { payload?: RouterStatus }).payload

    if (payload && typeof payload.state === 'string') {
      $routerStatus.set(payload)
    }
  })

  const offReady = onGatewayEvent('gateway.ready', () => void refreshRouterStatus())
  const offGateway = $gateway.listen(() => void refreshRouterStatus())

  return () => {
    offStatus()
    offReady()
    offGateway()
  }
})

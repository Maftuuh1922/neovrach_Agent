/**
 * Per-agent model for the Office ("Model" in the agent popover).
 *
 * A small adapter so the popover does not care how the gateway exposes the
 * model list and the per-agent model. The real one speaks the 9Router
 * contract (GET /api/models, PUT /api/agents/{agent_id}/model); a core
 * without those routes leaves the adapter UNAVAILABLE: the selector still
 * shows the agent's current model (live from the office snapshot) but cannot
 * change it. Tests and the screenshot run install `createMockModelAdapter()`.
 *
 * Live updates need nothing extra: the chosen model comes back on the
 * agent's `model` field in the next `office.update`, whoever changed it
 * (PC or phone).
 */
import { atom } from 'nanostores'

import { hermesApi } from '@/api/client'
import { createGatewayOfficeModelAdapter } from '@/store/router9'

import type { OfficeAgent } from './office-store'

export interface OfficeModelOption {
  id: string
  label: string
  provider?: string
}

export interface OfficeModelAdapter {
  /** False when the gateway cannot change an agent's model yet. */
  available: boolean
  listModels: () => Promise<OfficeModelOption[]>
  setAgentModel: (agent: Pick<OfficeAgent, 'id' | 'kind' | 'name' | 'session_id'>, model: string) => Promise<void>
}

export const unavailableModelAdapter: OfficeModelAdapter = {
  available: false,
  listModels: async () => [],
  setAgentModel: async () => {
    throw new Error('Gateway belum mendukung model per agen')
  }
}

export const $officeModelAdapter = atom<OfficeModelAdapter>(unavailableModelAdapter)

export function setOfficeModelAdapter(adapter: OfficeModelAdapter): void {
  $officeModelAdapter.set(adapter)
}

/** In-memory adapter for tests and demo screenshots. `onChange` lets the
 *  caller echo the change back into the office snapshot, like the gateway's
 *  `office.update` will. */
export function createMockModelAdapter(
  models: OfficeModelOption[],
  onChange?: (agentId: string, model: string) => void
): OfficeModelAdapter {
  return {
    available: true,
    listModels: async () => models,
    setAgentModel: async (agent, model) => {
      onChange?.(agent.id, model)
    }
  }
}

/** The options to render: the adapter's list, with the agent's current model
 *  kept first-class even when the list does not (yet) contain it. */
export function modelOptionsFor(current: string, models: OfficeModelOption[]): OfficeModelOption[] {
  if (!current || models.some(model => model.id === current)) {
    return models
  }

  return [{ id: current, label: current }, ...models]
}

/** One entry of `GET /api/models` (9Router contract). */
interface GatewayModelEntry {
  id: string
  label?: string
  provider?: string
  provider_label?: string
}

type Api = <T>(request: { body?: unknown; method?: string; path: string }) => Promise<T>

/** The adapter for a core that serves the 9Router model routes. */
export function createGatewayModelAdapter(api: Api = hermesApi as Api): OfficeModelAdapter {
  const providerOf = new Map<string, string>()

  return {
    available: true,
    listModels: async () => {
      const res = await api<{ models?: GatewayModelEntry[] }>({ path: '/api/models' })

      return (res.models ?? []).map(entry => {
        if (entry.provider) {
          providerOf.set(entry.id, entry.provider)
        }

        return { id: entry.id, label: entry.label || entry.id, provider: entry.provider_label || entry.provider }
      })
    },
    setAgentModel: async (agent, model) => {
      await api({
        body: { model, ...(providerOf.has(model) ? { provider: providerOf.get(model) } : {}) },
        method: 'PUT',
        path: `/api/agents/${encodeURIComponent(agent.id)}/model`
      })
    }
  }
}

/** The Office adapter over the gateway RPCs (`models.list` / `agent.model.set`,
 *  from store/router9.ts), remembering each model's provider for the set call. */
export function createRpcOfficeModelAdapter(
  rpc: ReturnType<typeof createGatewayOfficeModelAdapter> = createGatewayOfficeModelAdapter()
): OfficeModelAdapter {
  const providerOf = new Map<string, string>()

  return {
    available: rpc.available,
    listModels: async () => {
      const models = await rpc.listModels()

      for (const m of models) {
        if (m.provider) {
          providerOf.set(m.id, m.provider)
        }
      }

      return models
    },
    setAgentModel: (agent, model) => rpc.setAgentModel(agent, model, providerOf.get(model))
  }
}

let probed = false

/** Switch to the gateway adapter once the core answers `GET /api/models`
 *  (older cores 404 and stay read-only). Runs once per app session. */
export async function probeOfficeModels(api: Api = hermesApi as Api): Promise<boolean> {
  if (probed) {
    return $officeModelAdapter.get().available
  }

  probed = true

  const rpc = createRpcOfficeModelAdapter()

  if (rpc.available) {
    try {
      await rpc.listModels()
      setOfficeModelAdapter(rpc)

      return true
    } catch {
      // older core without the RPCs: fall back to the REST routes
    }
  }

  try {
    await api({ path: '/api/models' })
    setOfficeModelAdapter(createGatewayModelAdapter(api))

    return true
  } catch {
    probed = false

    return false
  }
}

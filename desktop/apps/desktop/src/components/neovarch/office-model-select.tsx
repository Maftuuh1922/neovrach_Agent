import { useStore } from '@nanostores/react'
import { useEffect, useState } from 'react'

import { onGatewayEvent } from '@/contrib/events'

import { $officeModelAdapter, modelOptionsFor, type OfficeModelOption, probeOfficeModels } from './office-models'
import type { OfficeAgent } from './office-store'

/** "Model" for one Office agent: shows the live model and lets the user pick
 *  another. The value always follows the snapshot, so a change made on the
 *  phone shows up here on the next office.update. */
export function OfficeModelSelect({ agent }: { agent: OfficeAgent }) {
  const adapter = useStore($officeModelAdapter)
  const [models, setModels] = useState<OfficeModelOption[]>([])
  const [pending, setPending] = useState<null | string>(null)
  const [error, setError] = useState<null | string>(null)
  const id = `nv-model-${agent.id}`

  const [listEpoch, setListEpoch] = useState(0)

  useEffect(() => {
    if (!adapter.available) {
      void probeOfficeModels()
    }
  }, [adapter])

  // 9Router re-fetched its model list: load it again (no polling).
  useEffect(() => onGatewayEvent('models.changed', () => setListEpoch(n => n + 1)), [])

  useEffect(() => {
    let alive = true

    if (!adapter.available) {
      setModels([])

      return
    }

    adapter
      .listModels()
      .then(list => alive && setModels(list))
      .catch(err => alive && setError(err instanceof Error ? err.message : String(err)))

    return () => {
      alive = false
    }
  }, [adapter, listEpoch])

  // A confirmed change arrives via the snapshot; drop the optimistic value then.
  useEffect(() => {
    setPending(null)
  }, [agent.model])

  const value = pending ?? agent.model
  const options = modelOptionsFor(value, models)

  const change = async (model: string) => {
    if (model === agent.model) {
      return
    }

    setPending(model)
    setError(null)

    try {
      await adapter.setAgentModel(agent, model)
    } catch (err) {
      setPending(null)
      setError(err instanceof Error ? err.message : String(err))
    }
  }

  return (
    <div className="nv-office-model" data-slot="nv-office-model">
      <label htmlFor={id}>Model</label>
      <select
        disabled={!adapter.available || pending !== null}
        id={id}
        onChange={event => void change(event.target.value)}
        title={adapter.available ? undefined : 'Ganti model per agen belum didukung gateway ini'}
        value={value}
      >
        {options.length === 0 && <option value="">{agent.model || 'Model bawaan'}</option>}
        {options.map(option => (
          <option key={option.id} value={option.id}>
            {option.provider ? `${option.label} · ${option.provider}` : option.label}
          </option>
        ))}
      </select>
      {error && (
        <p className="nv-office-model-error" role="alert">
          {error}
        </p>
      )}
    </div>
  )
}

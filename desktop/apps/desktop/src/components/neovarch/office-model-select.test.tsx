// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { OfficeModelSelect } from './office-model-select'
import {
  createGatewayModelAdapter,
  createMockModelAdapter,
  modelOptionsFor,
  setOfficeModelAdapter,
  unavailableModelAdapter
} from './office-models'
import type { OfficeAgent } from './office-store'

const AGENT: OfficeAgent = {
  current_task: null,
  current_tool: null,
  id: 'session:a',
  kind: 'session',
  last_activity: 0,
  last_activity_text: null,
  message_count: 0,
  model: 'gpt-mini',
  name: 'Sari',
  pending_approval: null,
  role: 'Agen utama',
  session_id: 'a',
  source: 'desktop',
  status: 'idle',
  title: null
}

const MODELS = [
  { id: 'gpt-mini', label: 'GPT mini' },
  { id: 'claude-sonnet', label: 'Claude Sonnet', provider: '9Router' }
]

afterEach(() => {
  cleanup()
  setOfficeModelAdapter(unavailableModelAdapter)
})

describe('modelOptionsFor', () => {
  it('keeps the current model selectable even when the list lacks it', () => {
    expect(modelOptionsFor('local-llama', MODELS).map(m => m.id)).toEqual(['local-llama', 'gpt-mini', 'claude-sonnet'])
    expect(modelOptionsFor('gpt-mini', MODELS)).toBe(MODELS)
  })
})

describe('createGatewayModelAdapter (9Router contract)', () => {
  it('lists GET /api/models and sets PUT /api/agents/{id}/model with the provider', async () => {
    const api = vi.fn(async (req: { path: string }) =>
      req.path === '/api/models'
        ? { models: [{ id: 'oc/big-pickle', label: 'Big Pickle', provider: '9router', provider_label: '9Router' }] }
        : { ok: true }
    )
    const adapter = createGatewayModelAdapter(api as never)

    expect(await adapter.listModels()).toEqual([{ id: 'oc/big-pickle', label: 'Big Pickle', provider: '9Router' }])
    await adapter.setAgentModel(AGENT, 'oc/big-pickle')
    expect(api).toHaveBeenLastCalledWith({
      body: { model: 'oc/big-pickle', provider: '9router' },
      method: 'PUT',
      path: '/api/agents/session%3Aa/model'
    })
  })
})

describe('OfficeModelSelect', () => {
  it('shows the live model, read-only while the gateway cannot change it', () => {
    render(<OfficeModelSelect agent={AGENT} />)
    const select = screen.getByLabelText('Model') as HTMLSelectElement

    expect(select.value).toBe('gpt-mini')
    expect(select.disabled).toBe(true)
  })

  it('changes the model through the adapter and follows the next snapshot', async () => {
    const onChange = vi.fn()
    setOfficeModelAdapter(createMockModelAdapter(MODELS, onChange))
    const view = render(<OfficeModelSelect agent={AGENT} />)
    const select = screen.getByLabelText('Model') as HTMLSelectElement
    await waitFor(() => expect(select.options).toHaveLength(2))

    fireEvent.change(select, { target: { value: 'claude-sonnet' } })
    expect(onChange).toHaveBeenCalledWith('session:a', 'claude-sonnet')
    expect(select.value).toBe('claude-sonnet')

    // office.update echoes it back (from this PC or the phone).
    act(() => view.rerender(<OfficeModelSelect agent={{ ...AGENT, model: 'claude-sonnet' }} />))
    expect(select.value).toBe('claude-sonnet')
    expect(select.disabled).toBe(false)

    // A change made elsewhere shows up live too.
    act(() => view.rerender(<OfficeModelSelect agent={{ ...AGENT, model: 'gpt-mini' }} />))
    expect(select.value).toBe('gpt-mini')
  })

  it('reverts and explains when the change fails', async () => {
    setOfficeModelAdapter({
      available: true,
      listModels: async () => MODELS,
      setAgentModel: async () => {
        throw new Error('model tidak dikenal')
      }
    })
    render(<OfficeModelSelect agent={AGENT} />)
    const select = screen.getByLabelText('Model') as HTMLSelectElement
    await waitFor(() => expect(select.options).toHaveLength(2))
    fireEvent.change(select, { target: { value: 'claude-sonnet' } })

    expect((await screen.findByRole('alert')).textContent).toBe('model tidak dikenal')
    expect(select.value).toBe('gpt-mini')
  })
})

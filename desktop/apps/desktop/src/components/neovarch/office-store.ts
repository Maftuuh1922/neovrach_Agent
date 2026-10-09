import { atom, onMount } from 'nanostores'

import { pluginRest } from '@/api/plugins'
import { onGatewayEvent } from '@/contrib/events'
import { $gateway } from '@/store/gateway'

/** One agent at its desk, as the core's `office.snapshot` / `office.update` describe it. */
export interface OfficeAgent {
  current_task: null | string
  current_tool: null | string
  id: string
  kind: 'kanban' | 'session'
  last_activity: number
  last_activity_text: null | string
  message_count: number
  model: string
  /** 9Router contract: the per-agent override, when one is set. */
  model_override?: null | { model: string; provider: string }
  model_provider?: string
  model_source?: 'agent' | 'global'
  name: string
  pending_approval: null | {
    command?: string
    description?: string
    request_id?: string
  }
  role: string
  session_id: null | string
  source: string
  status: 'idle' | 'waiting-approval' | 'working'
  tasks?: { id: string; status: string; title: string }[]
  title: null | string
}

export interface OfficeFeedItem {
  agent: string
  id: number
  kind: string
  session_id: null | string
  text: string
  ts: number
}

export interface OfficeVault {
  configured: boolean
  connected: boolean
  error?: string
  note_count: number
  path: string
}

export interface OfficeSnapshot {
  agents: OfficeAgent[]
  counts: {
    idle: number
    total: number
    'waiting-approval': number
    working: number
  }
  feed: OfficeFeedItem[]
  generated_at: number
  host: string
  kanban: Record<string, number>
  seq: number
  vault: OfficeVault
}

export const OFFICE_ROUTE = '/office'

/** Kantor view: the live 3D room (default) or the plain desk list. */
export type OfficeView = '3d' | 'list'
export const OFFICE_VIEW_KEY = 'neovarch.desktop.office-view.v1'

function readOfficeView(): OfficeView {
  try {
    return window.localStorage.getItem(OFFICE_VIEW_KEY) === 'list' ? 'list' : '3d'
  } catch {
    return '3d'
  }
}

export const $officeView = atom<OfficeView>(readOfficeView())

export function setOfficeView(view: OfficeView): void {
  $officeView.set(view)

  try {
    window.localStorage.setItem(OFFICE_VIEW_KEY, view)
  } catch {
    // Private mode / storage full: the choice still holds for this run.
  }
}

/** "Kasih tugas": a Kanban card assigned to this agent, through the Kanban
 *  plugin's own REST door (`POST /api/plugins/kanban/tasks`). The core then
 *  pushes `office.update`, so the desk picks the task up live. */
export async function assignOfficeTask(agent: Pick<OfficeAgent, 'name'>, title: string): Promise<unknown> {
  const trimmed = title.trim()

  if (!trimmed) {
    throw new Error('Judul tugas kosong')
  }

  return pluginRest('kanban', '/tasks', {
    method: 'POST',
    body: { assignee: agent.name, title: trimmed }
  })
}

export const OFFICE_STATUS_LABEL: Record<OfficeAgent['status'], string> = {
  idle: 'Santai',
  'waiting-approval': 'Menunggu persetujuan',
  working: 'Bekerja'
}

/** null = not loaded yet; the error string is shown instead of a toast. */
export const $office = atom<null | OfficeSnapshot>(null)
export const $officeError = atom<null | string>(null)

async function refresh(): Promise<void> {
  const gateway = $gateway.get()

  if (!gateway) {
    return
  }

  try {
    $office.set(await gateway.request<OfficeSnapshot>('office.snapshot', {}))
    $officeError.set(null)
  } catch (error) {
    $officeError.set(error instanceof Error ? error.message : String(error))
  }
}

// Live while anything shows the office: one snapshot on mount (and on every
// reconnect), then each `office.update` push replaces it.
onMount($office, () => {
  void refresh()
  const offUpdate = onGatewayEvent('office.update', event => {
    const payload = event.payload as OfficeSnapshot | undefined

    if (payload && Array.isArray(payload.agents)) {
      $office.set(payload)
    }
  })
  const offReady = onGatewayEvent('gateway.ready', () => void refresh())
  const offGateway = $gateway.listen(() => void refresh())

  return () => {
    offUpdate()
    offReady()
    offGateway()
  }
})

export function relativeTime(ts: number, now = Date.now() / 1000): string {
  if (!ts) {
    return '—'
  }

  const s = Math.max(0, Math.round(now - ts))

  if (s < 10) {
    return 'baru saja'
  }

  if (s < 60) {
    return `${s} dtk lalu`
  }

  if (s < 3600) {
    return `${Math.round(s / 60)} mnt lalu`
  }

  if (s < 86400) {
    return `${Math.round(s / 3600)} jam lalu`
  }

  return `${Math.round(s / 86400)} hari lalu`
}

export function initials(name: string): string {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map(part => part[0]!.toUpperCase())
      .join('') || '?'
  )
}

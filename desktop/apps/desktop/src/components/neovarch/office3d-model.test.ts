import { describe, expect, it } from 'vitest'

import {
  coatFor,
  DESK_SPACING_X,
  layoutDesks,
  MIN_ROOM,
  OFFICE3D_COATS,
  OFFICE3D_STATUS,
  sceneAgentsFromSnapshot,
  sceneStatusOf
} from './office3d-model'
import type { OfficeAgent, OfficeSnapshot } from './office-store'

function agent(over: Partial<OfficeAgent> = {}): OfficeAgent {
  return {
    current_task: null,
    current_tool: null,
    id: 'session:a',
    kind: 'session',
    last_activity: 0,
    last_activity_text: null,
    message_count: 0,
    model: '',
    name: 'Sari',
    pending_approval: null,
    role: 'Agen utama',
    session_id: 'a',
    source: 'desktop',
    status: 'idle',
    title: null,
    ...over
  }
}

function snapshot(agents: OfficeAgent[], feed: OfficeSnapshot['feed'] = []): OfficeSnapshot {
  return {
    agents,
    counts: { idle: 0, total: agents.length, 'waiting-approval': 0, working: 0 },
    feed,
    generated_at: 0,
    host: 'pc',
    kanban: {},
    seq: 1,
    vault: { configured: false, connected: false, note_count: 0, path: '' }
  }
}

describe('layoutDesks', () => {
  it('gives an empty office the minimum room', () => {
    expect(layoutDesks(0)).toEqual({ desks: [], room: MIN_ROOM })
  })

  it('centres a single desk', () => {
    expect(layoutDesks(1).desks).toEqual([{ x: 0, z: 0.4 }])
  })

  it('places rows of up to four, centred, with no two desks on one spot', () => {
    for (const n of [2, 3, 4, 5, 7, 9, 12, 13]) {
      const { desks, room } = layoutDesks(n)
      expect(desks).toHaveLength(n)
      expect(new Set(desks.map(d => `${d.x},${d.z}`)).size).toBe(n)

      // Every desk stays inside the room with a margin for the walls.
      for (const d of desks) {
        expect(Math.abs(d.x)).toBeLessThan(room.width / 2 - 1)
        expect(Math.abs(d.z)).toBeLessThan(room.depth / 2 - 1)
      }

      const xs = desks.map(d => d.x)
      expect(Math.max(...xs) + Math.min(...xs)).toBeCloseTo(0)
    }
  })

  it('grows the room for big teams', () => {
    const { desks, room } = layoutDesks(16)
    expect(new Set(desks.map(d => d.x)).size).toBe(4)
    expect(room.width).toBe(4 * DESK_SPACING_X + 5)
    expect(room.depth).toBeGreaterThan(MIN_ROOM.depth)
  })
})

describe('sceneStatusOf', () => {
  it('maps the core statuses', () => {
    expect(sceneStatusOf(agent({ status: 'working' }))).toBe('working')
    expect(sceneStatusOf(agent({ status: 'waiting-approval' }))).toBe('waiting')
    expect(sceneStatusOf(agent({ status: 'idle' }))).toBe('idle')
  })

  it('shows error when the session last failed, and recovers after a newer event', () => {
    const failed = [{ agent: 'Sari', id: 4, kind: 'error', session_id: 'a', text: 'gagal: timeout', ts: 1 }]
    expect(sceneStatusOf(agent(), failed)).toBe('error')
    expect(
      sceneStatusOf(agent(), [...failed, { agent: 'Sari', id: 5, kind: 'message', session_id: 'a', text: 'ok', ts: 2 }])
    ).toBe('idle')
    // Another agent's failure is not ours.
    expect(sceneStatusOf(agent({ session_id: 'b' }), failed)).toBe('idle')
  })

  it('shows error for a Kanban worker with a blocked task, unless it is working', () => {
    const kanban = agent({
      id: 'kanban:budi',
      kind: 'kanban',
      session_id: null,
      tasks: [{ id: 't1', status: 'blocked', title: 'Deploy' }]
    })
    expect(sceneStatusOf(kanban)).toBe('error')
    expect(sceneStatusOf({ ...kanban, status: 'working' })).toBe('working')
  })
})

describe('sceneAgentsFromSnapshot', () => {
  it('is empty before the first snapshot', () => {
    expect(sceneAgentsFromSnapshot(null)).toEqual([])
  })

  it('maps each agent to a desk, colour and label', () => {
    const snap = snapshot([
      agent({ current_task: 'Tulis laporan', current_tool: 'terminal: pytest', id: 'session:a', status: 'working' }),
      agent({
        current_task: 'Hapus cache',
        id: 'session:b',
        name: 'Budi',
        pending_approval: { command: 'rm -rf build' },
        session_id: 'b',
        status: 'waiting-approval'
      }),
      agent({ id: 'session:c', name: 'Citra', session_id: 'c' })
    ])
    const [a, b, c] = sceneAgentsFromSnapshot(snap)
    const desks = layoutDesks(3).desks

    expect(a).toMatchObject({
      id: 'session:a',
      label: 'terminal: pytest',
      name: 'Sari',
      sessionId: 'a',
      status: 'working'
    })
    expect(a!.statusText).toBe(OFFICE3D_STATUS.working.text)
    expect(b).toMatchObject({ label: 'rm -rf build', status: 'waiting' })
    expect(c).toMatchObject({ label: OFFICE3D_STATUS.idle.text, status: 'idle' })
    expect([a, b, c].map(s => ({ x: s!.x, z: s!.z }))).toEqual(desks)
    expect(OFFICE3D_COATS).toContain(a!.coat as (typeof OFFICE3D_COATS)[number])
    expect(coatFor('session:a')).toBe(a!.coat)
  })

  it('follows a live update: a new agent and a status change re-map without moving others', () => {
    const first = sceneAgentsFromSnapshot(
      snapshot([agent({ id: 'session:a' }), agent({ id: 'session:b', session_id: 'b' })])
    )
    const next = sceneAgentsFromSnapshot(
      snapshot([agent({ id: 'session:a', status: 'working' }), agent({ id: 'session:b', session_id: 'b' })])
    )
    expect(next.map(s => s.status)).toEqual(['working', 'idle'])
    expect(next.map(s => [s.x, s.z])).toEqual(first.map(s => [s.x, s.z]))
  })
})

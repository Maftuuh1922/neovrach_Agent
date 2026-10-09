import { describe, expect, it } from 'vitest'

import {
  coatFor,
  DESK_SPACING_X,
  layoutDesks,
  MIN_ROOM,
  OFFICE3D_COATS,
  OFFICE3D_STATUS,
  OFFICE3D_STROLL,
  pathLength,
  pointAlong,
  sceneAgentsFromSnapshot,
  sceneStatusOf,
  strollPlan,
  waterCoolerSpot
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

describe('strolls', () => {
  const { desks, room } = layoutDesks(5)

  /** True when the point is on a desk top or another agent's cushion. */
  function blocked(p: { x: number; z: number }, self: { x: number; z: number }) {
    return desks.some(d => {
      const onDesk = Math.abs(p.x - d.x) < 0.75 + 0.2 && p.z > d.z + 0.15 && p.z < d.z + 0.95
      const onCushion = d !== self && Math.abs(p.x - d.x) < 0.4 + 0.2 && Math.abs(p.z - (d.z - 0.2)) < 0.4 + 0.2

      return onDesk || onCushion
    })
  }

  function walk(points: { x: number; z: number }[]) {
    const out: { x: number; z: number }[] = []

    for (let s = 0; s <= pathLength(points); s += 0.05) {
      out.push(pointAlong(points, s))
    }

    return out
  }

  it('starts at the seat and keeps every path on free floor inside the room', () => {
    for (const self of desks) {
      for (const kind of ['cooler', 'neighbour', 'stretch'] as const) {
        for (const pick of [0, 0.5, 0.99]) {
          const plan = strollPlan(self, desks, room, kind, pick)
          expect(plan.points[0]).toEqual({ x: self.x, z: Math.round((self.z + OFFICE3D_STROLL.seatZ) * 100) / 100 })

          for (const p of walk(plan.points.slice(1))) {
            expect(blocked(p, self)).toBe(false)
            expect(Math.abs(p.x)).toBeLessThan(room.width / 2)
            expect(Math.abs(p.z)).toBeLessThan(room.depth / 2)
          }
        }
      }
    }
  })

  it('goes to the cooler along the left corridor, and to a same-row neighbour', () => {
    const cooler = waterCoolerSpot(room)
    const toCooler = strollPlan(desks[2]!, desks, room, 'cooler', 0.5)
    expect(toCooler.points.at(-1)!.x).toBeCloseTo(cooler.x + 0.6)
    expect(toCooler.points.at(-1)!.z).toBeCloseTo(cooler.z)
    expect(toCooler.face.x).toBe(cooler.x)

    // Desk 3 and 4 share the short front row.
    const toNeighbour = strollPlan(desks[3]!, desks, room, 'neighbour', 0.5)
    expect(toNeighbour.kind).toBe('neighbour')
    expect(toNeighbour.face.x).toBe(desks[4]!.x)

    // A lone agent has no neighbour: the stroll becomes a cooler trip.
    const lone = layoutDesks(1)
    expect(strollPlan(lone.desks[0]!, lone.desks, lone.room, 'neighbour').kind).toBe('cooler')
  })

  it('walks a polyline by distance with a heading (0 faces +z)', () => {
    const pts = [
      { x: 0, z: 0 },
      { x: 0, z: -1 },
      { x: -2, z: -1 }
    ]

    expect(pathLength(pts)).toBe(3)
    expect(pointAlong(pts, 0.5)).toMatchObject({ x: 0, z: -0.5 })
    expect(pointAlong(pts, 0.5).heading).toBeCloseTo(Math.PI)
    expect(pointAlong(pts, 2)).toMatchObject({ x: -1, z: -1 })
    expect(pointAlong(pts, 2).heading).toBeCloseTo(-Math.PI / 2)
    expect(pointAlong(pts, 9)).toMatchObject({ x: -2, z: -1 })
  })
})

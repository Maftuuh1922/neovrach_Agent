import { describe, expect, it } from 'vitest'

import {
  cameraFrame,
  coatFor,
  DESK_SPACING_X,
  doorTarget,
  gardenLayout,
  groundHeight,
  isOutdoorStroll,
  layoutDesks,
  MIN_ROOM,
  newStroll,
  OFFICE3D_CAMERA,
  OFFICE3D_COATS,
  OFFICE3D_GARDEN,
  OFFICE3D_STATUS,
  OFFICE3D_STROLL,
  pathLength,
  perchTarget,
  pointAlong,
  sceneAgentsFromSnapshot,
  sceneBounds,
  sceneStatusOf,
  stepDoor,
  stepStroll,
  strollKindFor,
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

describe('garden + outdoor strolls', () => {
  const { desks, room } = layoutDesks(5)
  const g = gardenLayout(room)

  function walk(points: { x: number; z: number }[]) {
    const out: { x: number; z: number }[] = []

    for (let s = 0; s <= pathLength(points); s += 0.05) {
      out.push(pointAlong(points, s))
    }

    return out
  }

  function inPond(p: { x: number; z: number }) {
    return ((p.x - g.pond.x) / (g.pond.rx + 0.15)) ** 2 + ((p.z - g.pond.z) / (g.pond.rz + 0.15)) ** 2 < 1
  }

  it('lays the door in the left wall near the front, the engawa and the garden beyond it', () => {
    expect(g.wallX).toBe(-room.width / 2)
    expect(g.door.x).toBe(g.wallX)
    expect(g.door.z).toBeCloseTo(room.depth / 2 - OFFICE3D_GARDEN.doorFromFront)
    expect(Math.abs(g.door.z - waterCoolerSpot(room).z)).toBeGreaterThan(g.door.width / 2 + 0.3)
    expect(g.engawaX).toBeCloseTo(g.wallX - OFFICE3D_GARDEN.engawaWidth)
    expect(g.garden.x1).toBe(g.engawaX)
    expect(g.garden.x0).toBeLessThan(g.pond.x - g.pond.rx)
    // The tea tray sits on the engawa; pond, bench, lantern and trees in the garden.
    expect(g.tea.x).toBeGreaterThan(g.engawaX)
    expect(g.tea.x).toBeLessThan(g.wallX)

    for (const spot of [g.pond, g.bench, g.lantern, g.maple, g.pine]) {
      expect(spot.x).toBeLessThan(g.engawaX)
      expect(spot.x).toBeGreaterThan(g.garden.x0)
      expect(spot.z).toBeGreaterThan(g.garden.z0)
      expect(spot.z).toBeLessThan(g.garden.z1)
    }
  })

  it('steps down into the garden: floor and engawa at 0, gravel below', () => {
    expect(groundHeight(0, room)).toBe(0)
    expect(groundHeight(g.wallX - 0.5, room)).toBe(0)
    expect(groundHeight(g.engawaX - 2, room)).toBeCloseTo(OFFICE3D_GARDEN.groundY)
    const mid = groundHeight(g.engawaX - OFFICE3D_GARDEN.stepRun / 2, room)
    expect(mid).toBeLessThan(0)
    expect(mid).toBeGreaterThan(OFFICE3D_GARDEN.groundY)
  })

  it('sends outdoor strolls through the door gap only, to spots outside, clear of the pond', () => {
    for (const self of desks) {
      for (const kind of ['tea', 'bench', 'pond'] as const) {
        for (const pick of [0, 0.5, 0.99]) {
          const plan = strollPlan(self, desks, room, kind, pick)
          expect(plan.kind).toBe(kind)
          expect(isOutdoorStroll(plan.kind)).toBe(true)
          const end = plan.points.at(-1)!
          // The destination is outside the room.
          expect(end.x).toBeLessThan(g.wallX)

          if (kind === 'tea') {
            expect(end.x).toBeGreaterThan(g.engawaX)
          } else {
            expect(end.x).toBeLessThan(g.engawaX)
          }

          const pts = walk(plan.points)

          for (let i = 1; i < pts.length; i++) {
            const a = pts[i - 1]!
            const b = pts[i]!

            // Crossing the wall plane happens only inside the door opening.
            if ((a.x - g.wallX) * (b.x - g.wallX) <= 0 && a.x !== b.x) {
              expect(Math.abs(b.z - g.door.z)).toBeLessThan(g.door.width / 2 - 0.15)
            }

            expect(inPond(b)).toBe(false)
            expect(b.z).toBeLessThan(g.garden.z1)
            expect(b.x).toBeGreaterThan(g.garden.x0)
          }
        }
      }
    }
  })

  it('keeps waiting agents inside or on the engawa; idle agents may go into the garden; workers stay put', () => {
    const waiting = new Set<string>()
    const idle = new Set<string>()

    for (let r = 0; r < 1; r += 0.01) {
      waiting.add(strollKindFor('waiting', r)!)
      idle.add(strollKindFor('idle', r)!)
    }

    expect([...waiting].sort()).toEqual(['cooler', 'neighbour', 'stretch', 'tea'])
    expect(idle.has('bench') && idle.has('pond') && idle.has('tea')).toBe(true)
    expect(strollKindFor('working', 0.5)).toBeNull()
    expect(strollKindFor('error', 0.5)).toBeNull()

    for (const kind of waiting) {
      for (const p of strollPlan(desks[0]!, desks, room, kind as never, 0.5).points) {
        expect(p.x).toBeGreaterThan(g.engawaX)
      }
    }
  })

  it('opens the door while a walker is near it and closes it after', () => {
    expect(doorTarget([], room)).toBe(0)
    expect(doorTarget([{ x: g.door.x + 0.4, z: g.door.z }], room)).toBe(1)
    expect(doorTarget([{ x: g.door.x - 1, z: g.door.z + 0.3 }], room)).toBe(1)
    expect(doorTarget([{ x: 0, z: 0 }], room)).toBe(0)

    let open = 0

    for (let i = 0; i < 10; i++) {
      open = stepDoor(open, 1, 0.1)
    }

    expect(open).toBe(1)
    open = stepDoor(open, 0, 0.1)
    expect(open).toBeLessThan(1)
    expect(open).toBeGreaterThan(0)

    for (let i = 0; i < 10; i++) {
      open = stepDoor(open, 0, 0.1)
    }

    expect(open).toBe(0)
  })

  it('walks out to the bench, sits, and hurries back to the desk when work arrives', () => {
    const plan = strollPlan(desks[0]!, desks, room, 'bench', 0.2)
    const st = newStroll(plan, 8)
    let t = 0

    // Stand up, walk out at the normal pace, sit on the bench.
    while (st.phase !== 'pause' && t < 60) {
      stepStroll(st, 0.05, true)
      t += 0.05
    }

    expect(st.phase).toBe('pause')
    expect(st.s).toBeCloseTo(st.length)
    expect(t).toBeGreaterThan(st.length / OFFICE3D_STROLL.speed)
    stepStroll(st, 0.5, true)
    expect(perchTarget(st)).toBe(1)

    // Work arrives: up off the bench, back along the path at hurry speed.
    const step = stepStroll(st, 0.1, false)
    expect(st.hurry).toBe(true)
    expect(st.phase).toBe('back')
    expect(perchTarget(st)).toBe(0)
    expect(step.moved).toBeCloseTo(OFFICE3D_STROLL.hurrySpeed * 0.1)

    let back = 0.1

    while (st.phase === 'back' && back < 60) {
      stepStroll(st, 0.05, false)
      back += 0.05
    }

    expect(back).toBeLessThan(st.length / OFFICE3D_STROLL.speed)
    expect(st.phase).toBe('sit')
    let done = false

    for (let i = 0; i < 20 && !done; i++) {
      done = stepStroll(st, 0.05, false).done
    }

    expect(done).toBe(true)
  })

  it('frames room + garden by default and room + engawa for the thumbnail', () => {
    const all = cameraFrame(room, 16 / 9)
    const mini = cameraFrame(room, 2.1, 'room')
    const b = sceneBounds(room)
    expect(all.target.x).toBeCloseTo((b.x0 + b.x1) / 2)
    expect(all.target.x).toBeLessThan(0)
    expect(all.distance).toBeLessThanOrEqual(OFFICE3D_CAMERA.maxDistance)
    expect(all.distance).toBeGreaterThan(mini.distance)
    expect(sceneBounds(room, 'room').x0).toBe(g.engawaX)
    // A narrow (portrait) view backs off further.
    expect(cameraFrame(room, 0.8).distance).toBeGreaterThan(all.distance)
    // Never round behind the walls.
    expect(OFFICE3D_CAMERA.minAzimuthAngle).toBeGreaterThan(-Math.PI / 4)
    expect(OFFICE3D_CAMERA.maxAzimuthAngle).toBeLessThan(Math.PI / 2 + 0.3)
  })
})

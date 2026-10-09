/**
 * Office 3D — the pure model behind the scene: palette, desk layout for N
 * agents, and the office-snapshot → scene-agent mapping.
 *
 * Framework-agnostic on purpose: no React, no three.js, no app imports (types
 * only), so the phone's WebView build can mirror it file-for-file. The look is
 * documented for the phone side in office3d-spec.md.
 */
import type { OfficeAgent, OfficeFeedItem, OfficeSnapshot } from './office-store'

/** How a desk shows its agent. `error` is derived (the core reports idle). */
export type SceneStatus = 'error' | 'idle' | 'waiting' | 'working'

export interface SceneAgent {
  /** Clothing colour, stable per agent id. */
  coat: string
  id: string
  /** Second label line: the tool or task, else the status word. */
  label: string
  name: string
  sessionId: null | string
  status: SceneStatus
  statusText: string
  /** Desk centre on the floor (x, z); the agent sits behind it facing +z. */
  x: number
  z: number
}

export interface RoomSize {
  depth: number
  width: number
}

export interface SceneLayout {
  desks: { x: number; z: number }[]
  room: RoomSize
}

/** Every colour the scene uses, as hex. Warm, muted, a little red. */
export const OFFICE3D_PALETTE = {
  tatami: '#c9b98a',
  tatamiWeave: '#b3a271',
  tatamiBorder: '#2e2a24',
  engawa: '#8a6a48',
  woodLight: '#c79a63',
  woodDark: '#5a3b24',
  deskTop: '#6b4429',
  plaster: '#e7dcc8',
  shojiPaper: '#f3ebdc',
  shojiGlow: '#ffe3b5',
  lanternPaper: '#f6e3c0',
  lanternGlow: '#ffb866',
  lanternCap: '#2b211b',
  zabuton: '#2f3a56',
  enso: '#b5262e',
  scroll: '#efe6d2',
  bonsaiLeaf: '#4f6b3a',
  bonsaiTrunk: '#4a3322',
  pot: '#3c3f44',
  skin: '#e8c6a0',
  hair: '#1e1a18',
  laptop: '#2a2a2e',
  coolerStand: '#d9cfbd',
  coolerWater: '#8fbfd4',
  hemiSky: '#fff1dc',
  hemiGround: '#6b5a44',
  sun: '#ffe2b8'
} as const

/** Clothing colours handed out by agent id (indigo, oxblood, pine, wisteria, ochre, charcoal). */
export const OFFICE3D_COATS = ['#3a4a6e', '#7a2e2e', '#3e5a4a', '#6a5a8c', '#8a6a3a', '#45434a'] as const

export const OFFICE3D_STATUS: Record<SceneStatus, { color: string; text: string }> = {
  error: { color: '#ff3b30', text: 'Galat' },
  idle: { color: '#9c9488', text: 'Santai' },
  waiting: { color: '#f2b544', text: 'Menunggu persetujuan' },
  working: { color: '#6fcf8a', text: 'Bekerja' }
}

/** Desk pitch in scene units (1 unit ≈ 1 m; a tatami mat is 2 × 1). */
export const DESK_SPACING_X = 3
export const DESK_SPACING_Z = 2.8
export const MIN_ROOM: RoomSize = { width: 12, depth: 9 }

/** Orbit camera limits shared by desktop and phone. */
export const OFFICE3D_CAMERA = {
  fov: 40,
  minDistance: 5,
  maxDistance: 24,
  minPolarAngle: 0.35,
  maxPolarAngle: 1.25,
  /** Azimuth around +y, 0 = looking from +z; the walls stand at -z and -x. */
  minAzimuthAngle: -0.3,
  maxAzimuthAngle: 1.75
} as const

/**
 * Idle strolls: an idle or waiting agent now and then stands up, walks a short
 * path (to the water cooler, to a neighbour's desk, or a few steps along the
 * aisle) and comes back to sit. Working and error agents stay seated; an agent
 * that gets work mid-stroll hurries straight back. Times in seconds, distances
 * in scene units (m).
 */
export const OFFICE3D_STROLL = {
  /** Walking speed, and the faster speed when work arrives mid-stroll. */
  speed: 0.9,
  hurrySpeed: 1.5,
  /** Sit ↔ stand blend. */
  standUp: 0.6,
  /** Time spent at the destination. */
  pauseMin: 2,
  pauseMax: 4,
  /** Gap before an agent's first stroll, and between strolls after that. */
  firstMin: 3,
  firstMax: 12,
  gapMin: 10,
  gapMax: 24,
  /** Walk-cycle stride (one left + right step) and swing amplitudes (rad). */
  stride: 1.1,
  legSwing: 0.55,
  armSwing: 0.45,
  /** Standing body height (seated body sits at 0.12). */
  standY: 0.34,
  /** Seat point behind the desk, and the free aisle behind each seat (z offsets from the desk centre). */
  seatZ: -0.22,
  aisleZ: -1.2,
  /** Chance of each destination (the rest are aisle stretches). */
  coolerChance: 0.45,
  neighbourChance: 0.35
} as const

export type StrollKind = 'cooler' | 'neighbour' | 'stretch'

export interface StrollPlan {
  kind: StrollKind
  /** Polyline on the floor, from the seat to the destination. Walk it out, then back. */
  points: { x: number; z: number }[]
  /** Where the agent looks while paused at the destination. */
  face: { x: number; z: number }
}

/** The water cooler: against the left shoji wall, near the front of the room. */
export function waterCoolerSpot(room: RoomSize): { x: number; z: number } {
  return { x: round2(-room.width / 2 + 0.45), z: round2(room.depth / 2 - 1.5) }
}

/**
 * The path for one stroll. Paths only use free floor: the aisle behind the
 * agent's own seat (no desk is within 0.7 m of it), and a corridor along the
 * left wall (at least 3 m clear of the leftmost desks by `layoutDesks`).
 * `pick` is a random number in [0, 1) that chooses the side / the spot.
 * A `neighbour` stroll without a same-row neighbour becomes a `cooler` one.
 */
export function strollPlan(
  agent: { x: number; z: number },
  desks: { x: number; z: number }[],
  room: RoomSize,
  kind: StrollKind,
  pick = 0.5
): StrollPlan {
  const S = OFFICE3D_STROLL
  const seat = { x: agent.x, z: round2(agent.z + S.seatZ) }
  const aisle = round2(agent.z + S.aisleZ)
  const out = { x: agent.x, z: aisle }

  if (kind === 'neighbour') {
    const sameRow = desks
      .filter(d => Math.abs(d.z - agent.z) < 0.01 && Math.abs(d.x - agent.x) > 0.01)
      .sort((a, b) => Math.abs(a.x - agent.x) - Math.abs(b.x - agent.x))

    const nearest = sameRow.filter(d => Math.abs(Math.abs(d.x - agent.x) - Math.abs(sameRow[0]!.x - agent.x)) < 0.01)
    const target = nearest.length ? nearest[Math.min(nearest.length - 1, Math.floor(pick * nearest.length))]! : null

    if (target) {
      const dir = Math.sign(target.x - agent.x)

      return {
        kind,
        points: [seat, out, { x: round2(target.x - dir * 0.6), z: aisle }],
        face: { x: target.x, z: round2(target.z + S.seatZ) }
      }
    }

    kind = 'cooler'
  }

  if (kind === 'stretch') {
    // Toward the room's centre line, or either way at the centre.
    const dir = Math.abs(agent.x) < 0.01 ? (pick < 0.5 ? -1 : 1) : -Math.sign(agent.x)
    const end = { x: round2(agent.x + dir * 1.5), z: aisle }

    return { kind, points: [seat, out, end], face: { x: end.x, z: round2(end.z + 2) } }
  }

  const cooler = waterCoolerSpot(room)
  const corridor = round2(cooler.x + 0.6)
  // Two agents at the cooler at once stand a little apart.
  const spotZ = round2(cooler.z + (pick - 0.5) * 0.6)

  return {
    kind: 'cooler',
    points: [seat, out, { x: corridor, z: aisle }, { x: corridor, z: spotZ }],
    face: { x: cooler.x, z: spotZ }
  }
}

/** Length of a stroll polyline. */
export function pathLength(points: { x: number; z: number }[]): number {
  let total = 0

  for (let i = 1; i < points.length; i++) {
    total += Math.hypot(points[i]!.x - points[i - 1]!.x, points[i]!.z - points[i - 1]!.z)
  }

  return total
}

/** Point and heading (rotation.y; 0 faces +z) at distance `s` along a polyline. */
export function pointAlong(points: { x: number; z: number }[], s: number): { heading: number; x: number; z: number } {
  let left = Math.max(0, s)

  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]!
    const b = points[i]!
    const len = Math.hypot(b.x - a.x, b.z - a.z)

    if (len === 0) {
      continue
    }

    if (left <= len || i === points.length - 1) {
      const k = Math.min(1, left / len)

      return { heading: Math.atan2(b.x - a.x, b.z - a.z), x: a.x + (b.x - a.x) * k, z: a.z + (b.z - a.z) * k }
    }

    left -= len
  }

  const p = points[0] ?? { x: 0, z: 0 }

  return { heading: 0, x: p.x, z: p.z }
}

export function deskColumns(n: number): number {
  if (n <= 2) {
    return Math.max(1, n)
  }

  if (n <= 4) {
    return 2
  }

  if (n <= 9) {
    return 3
  }

  return 4
}

/** Desk centres for `n` agents: rows of up to four, centred, row 0 at the back. */
export function layoutDesks(n: number): SceneLayout {
  const count = Math.max(0, Math.floor(n))
  const cols = deskColumns(count)
  const rows = count === 0 ? 0 : Math.ceil(count / cols)
  const desks: { x: number; z: number }[] = []

  for (let i = 0; i < count; i++) {
    const row = Math.floor(i / cols)
    // The last row may be short; centre it too.
    const inRow = row === rows - 1 ? count - row * cols : cols
    const col = i - row * cols
    desks.push({
      x: round2((col - (inRow - 1) / 2) * DESK_SPACING_X),
      z: round2((row - (rows - 1) / 2) * DESK_SPACING_Z + 0.4)
    })
  }

  return {
    desks,
    room: {
      width: Math.max(MIN_ROOM.width, cols * DESK_SPACING_X + 5),
      depth: Math.max(MIN_ROOM.depth, rows * DESK_SPACING_Z + 4.5)
    }
  }
}

function round2(v: number): number {
  return Math.round(v * 100) / 100 + 0
}

export function coatFor(id: string): string {
  let h = 0

  for (let i = 0; i < id.length; i++) {
    h = (h * 31 + id.charCodeAt(i)) >>> 0
  }

  return OFFICE3D_COATS[h % OFFICE3D_COATS.length]!
}

const ERROR_TASK_STATUSES = new Set(['blocked', 'error', 'failed'])

/** The desk's look: the core's status, with `error` when the agent's latest
 *  event was a failure (sessions) or a task of theirs is blocked/failed (Kanban). */
export function sceneStatusOf(agent: OfficeAgent, feed: OfficeFeedItem[] = []): SceneStatus {
  const raw = agent.status as string

  if (raw === 'error') {
    return 'error'
  }

  if (raw === 'waiting-approval') {
    return 'waiting'
  }

  if (raw === 'working') {
    return 'working'
  }

  if (agent.session_id) {
    const last = latestFeedFor(agent.session_id, feed)

    if (last?.kind === 'error') {
      return 'error'
    }
  } else if (agent.tasks?.some(task => ERROR_TASK_STATUSES.has(task.status))) {
    return 'error'
  }

  return 'idle'
}

function latestFeedFor(sessionId: string, feed: OfficeFeedItem[]): OfficeFeedItem | undefined {
  let best: OfficeFeedItem | undefined

  for (const item of feed) {
    if (item.session_id === sessionId && (!best || item.id > best.id)) {
      best = item
    }
  }

  return best
}

/** Snapshot → what the scene draws. Order follows the snapshot (stable desks). */
export function sceneAgentsFromSnapshot(snapshot: null | OfficeSnapshot): SceneAgent[] {
  if (!snapshot) {
    return []
  }

  const { desks } = layoutDesks(snapshot.agents.length)

  return snapshot.agents.map((agent, i) => {
    const status = sceneStatusOf(agent, snapshot.feed)
    const statusText = OFFICE3D_STATUS[status].text
    const detail =
      status === 'waiting'
        ? agent.pending_approval?.command || agent.current_task
        : status === 'error'
          ? agent.last_activity_text || agent.current_task
          : agent.current_tool || agent.current_task

    return {
      coat: coatFor(agent.id),
      id: agent.id,
      label: (detail || statusText).trim(),
      name: agent.name,
      sessionId: agent.session_id,
      status,
      statusText,
      x: desks[i]!.x,
      z: desks[i]!.z
    }
  })
}

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
  gravel: '#cfc6b4',
  gravelRake: '#b5ab97',
  gardenEdge: '#6f665a',
  stone: '#8d8a83',
  stoneDark: '#6d6a64',
  pond: '#2f5a63',
  koi: '#e0662e',
  maple: '#b5402e',
  mapleDeep: '#8f2f25',
  pine: '#3f5a3a',
  moss: '#6f7f4a',
  teaCup: '#efe6d2',
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
  maxDistance: 30,
  minPolarAngle: 0.35,
  maxPolarAngle: 1.25,
  /** Azimuth around +y, 0 = looking from +z; the walls stand at -z and -x.
   *  A little negative so the garden beyond the left shoji can be seen from
   *  the front-left; never round behind the walls. */
  minAzimuthAngle: -0.55,
  maxAzimuthAngle: 1.75,
  /** Default view: the whole room + engawa + garden, from the front, slightly right. */
  azimuth: 0.05,
  polar: 0.95,
  /** Room-only framing (mini Kantor thumbnail, which crops to room + engawa). */
  roomAzimuth: 0.62
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

/** Indoor kinds stay in the room; `tea` goes out to the engawa (veranda);
 *  `bench` and `pond` go down into the garden. */
export type StrollKind = 'bench' | 'cooler' | 'neighbour' | 'pond' | 'stretch' | 'tea'

/**
 * Where a stroll goes, by status. Idle (santai) agents may go out into the
 * garden; waiting agents stay close (inside, or the engawa just outside the
 * door). Cumulative odds, checked in order; the last kind takes the rest.
 */
export const OFFICE3D_STROLL_ODDS: Record<'idle' | 'waiting', [StrollKind, number][]> = {
  idle: [
    ['cooler', 0.24],
    ['neighbour', 0.42],
    ['stretch', 0.52],
    ['tea', 0.66],
    ['bench', 0.83],
    ['pond', 1]
  ],
  waiting: [
    ['cooler', 0.4],
    ['neighbour', 0.7],
    ['stretch', 0.85],
    ['tea', 1]
  ]
}

/** Pick a stroll kind for an agent's status from a random number r in [0, 1).
 *  Working and error agents never stroll (null). */
export function strollKindFor(status: SceneStatus, r: number): null | StrollKind {
  if (status !== 'idle' && status !== 'waiting') {
    return null
  }

  const odds = OFFICE3D_STROLL_ODDS[status]

  return (odds.find(([, upTo]) => r < upTo) ?? odds[odds.length - 1]!)[0]
}

/** True for strolls that go through the sliding door (engawa or garden). */
export function isOutdoorStroll(kind: StrollKind): boolean {
  return kind === 'tea' || kind === 'bench' || kind === 'pond'
}

/** Pause at the destination (s): longer outside (a sit on the bench, a cup of tea). */
export function strollPauseRange(kind: StrollKind): [number, number] {
  if (kind === 'bench') {
    return [6, 10]
  }

  if (kind === 'pond' || kind === 'tea') {
    return [4, 7]
  }

  return [OFFICE3D_STROLL.pauseMin, OFFICE3D_STROLL.pauseMax]
}

/**
 * The garden beyond the left (-x) shoji: a sliding door near the front of the
 * wall opens onto a wooden engawa (veranda) and a small raked-gravel garden one
 * step down, with stepping stones, a koi pond, a stone lantern, a maple, a pine,
 * a bench and a tea tray on the engawa. Distances in m from the room's walls.
 */
export const OFFICE3D_GARDEN = {
  /** Door opening in the left wall: width, and its centre's distance from the front edge. */
  doorWidth: 1,
  doorFromFront: 3,
  /** Engawa deck width outside the wall (the slab's own 0.3 m lip included). */
  engawaWidth: 1.4,
  /** Garden width beyond the engawa, and how far it reaches past the room's front. */
  gardenWidth: 5.6,
  frontReach: 1.6,
  /** Gravel sits one step below the floor; the step is eased over this run. */
  groundY: -0.24,
  stepRun: 0.45,
  /** The door slides open when a walker is this close to its centre, at this rate (1/s). */
  doorRadius: 1.6,
  doorRate: 2.2,
  /** Bench seat height above the gravel, and the seated body height above the gravel. */
  benchSeat: 0.36,
  perchY: 0.2
} as const

export interface GardenLayout {
  /** Left wall plane (x). */
  wallX: number
  door: { width: number; x: number; z: number }
  /** Outer edge of the engawa deck (x); the deck runs from here to the wall. */
  engawaX: number
  /** Gravel area. */
  garden: { x0: number; x1: number; z0: number; z1: number }
  groundY: number
  pond: { rx: number; rz: number; x: number; z: number }
  bench: { length: number; x: number; z: number }
  /** Tea tray on the engawa. */
  tea: { x: number; z: number }
  lantern: { x: number; z: number }
  maple: { x: number; z: number }
  pine: { x: number; z: number }
  /** Stepping stones from the engawa step toward the bench and pond. */
  stones: { r: number; x: number; z: number }[]
}

export function gardenLayout(room: RoomSize): GardenLayout {
  const G = OFFICE3D_GARDEN
  const L = -room.width / 2
  const hd = room.depth / 2
  const door = { width: G.doorWidth, x: L, z: round2(hd - G.doorFromFront) }
  const engawaX = round2(L - G.engawaWidth)
  const x0 = round2(engawaX - G.gardenWidth)
  const bench = { length: 1.4, x: round2(L - 4.4), z: round2(hd - 3.1) }

  return {
    wallX: L,
    door,
    engawaX,
    garden: { x0, x1: engawaX, z0: round2(-hd - 0.3), z1: round2(hd + G.frontReach) },
    groundY: G.groundY,
    pond: { rx: 1.25, rz: 0.85, x: round2(L - 4.4), z: round2(hd - 0.85) },
    bench,
    tea: { x: round2(L - 1.05), z: round2(door.z + 1.5) },
    lantern: { x: round2(L - 6.15), z: round2(hd + 0.5) },
    maple: { x: round2(L - 6), z: round2(hd - 5) },
    pine: { x: round2(L - 2.5), z: round2(-hd + 1.3) },
    stones: [
      { r: 0.26, x: round2(L - 1.75), z: door.z },
      { r: 0.24, x: round2(L - 2.35), z: round2(door.z + 0.35) },
      { r: 0.25, x: round2(L - 2.95), z: round2(door.z + 0.8) },
      { r: 0.22, x: round2(L - 3.55), z: round2(door.z + 0.85) },
      { r: 0.24, x: round2(L - 2.9), z: round2(door.z + 1.45) }
    ]
  }
}

/** Floor height under (x, z): 0 in the room and on the engawa, the gravel's
 *  height in the garden, eased over one stepping-stone run between them. */
export function groundHeight(x: number, room: RoomSize): number {
  const { engawaX, groundY } = gardenLayout(room)

  if (x >= engawaX) {
    return 0
  }

  const k = Math.min(1, (engawaX - x) / OFFICE3D_GARDEN.stepRun)

  return groundY * k * k * (3 - 2 * k)
}

/** Door target: open (1) while any walker is near the doorway, else closed (0). */
export function doorTarget(walkers: { x: number; z: number }[], room: RoomSize): 0 | 1 {
  const { door } = gardenLayout(room)

  return walkers.some(w => Math.hypot(w.x - door.x, w.z - door.z) < OFFICE3D_GARDEN.doorRadius) ? 1 : 0
}

/** Ease the door's open amount (0 shut … 1 open) toward its target. */
export function stepDoor(open: number, target: number, dt: number): number {
  const step = OFFICE3D_GARDEN.doorRate * Math.max(0, dt)

  return target > open ? Math.min(target, open + step) : Math.max(target, open - step)
}

/** Bounds of the whole scene on the floor: room + engawa + garden (`all`), or
 *  room + engawa only (`room`, for the thumbnail). */
export function sceneBounds(room: RoomSize, scope: 'all' | 'room' = 'all') {
  const g = gardenLayout(room)
  const hw = room.width / 2
  const hd = room.depth / 2

  return scope === 'all'
    ? { x0: g.garden.x0, x1: hw, z0: -hd, z1: g.garden.z1 }
    : { x0: g.engawaX, x1: hw, z0: -hd, z1: hd }
}

/**
 * The default camera ("Atur ulang kamera"): aimed at the middle of the bounds
 * and backed off until every corner of the bounds (floor up to the wall tops)
 * fits the view at this aspect ratio, with a small margin.
 */
export function cameraFrame(
  room: RoomSize,
  aspect: number,
  scope: 'all' | 'room' = 'all'
): { azimuth: number; distance: number; polar: number; target: { x: number; y: number; z: number } } {
  const C = OFFICE3D_CAMERA
  const b = sceneBounds(room, scope)
  const azimuth = scope === 'all' ? C.azimuth : C.roomAzimuth
  const polar = C.polar
  const target = { x: round2((b.x0 + b.x1) / 2), y: 0.5, z: round2((b.z0 + b.z1) / 2) }
  // Camera basis: forward (toward the target), right, up.
  const f = { x: -Math.sin(polar) * Math.sin(azimuth), y: -Math.cos(polar), z: -Math.sin(polar) * Math.cos(azimuth) }
  const r = { x: Math.cos(azimuth), y: 0, z: -Math.sin(azimuth) }
  const u = { x: r.y * f.z - r.z * f.y, y: r.z * f.x - r.x * f.z, z: r.x * f.y - r.y * f.x }

  if (scope === 'room') {
    // Thumbnail: the room's own framing (as before the garden, it may crop the
    // corners a little so the figures stay big), nudged left for the engawa.
    const dist = Math.min(C.maxDistance - 1, Math.max(11, Math.max(room.width, room.depth) * 1.15))

    return { azimuth, distance: round2(dist), polar, target: { ...target, y: 0.6 } }
  }

  const tanV = Math.tan(((C.fov / 2) * Math.PI) / 180) * 0.94
  const tanH = tanV * Math.max(0.2, aspect)
  let distance = 0

  // Floor corners, the wall tops (back and left walls) and, with the garden, the maple's crown.
  const hw = room.width / 2
  const hd = room.depth / 2
  const g = gardenLayout(room)

  const points = [
    { x: b.x0, y: 0, z: b.z0 },
    { x: b.x1, y: 0, z: b.z0 },
    { x: b.x0, y: 0, z: b.z1 },
    { x: b.x1, y: 0, z: b.z1 },
    { x: -hw, y: 3.2, z: -hd },
    { x: hw, y: 3.2, z: -hd },
    { x: -hw, y: 3.2, z: hd },
    ...(scope === 'all' ? [{ x: g.maple.x, y: 3, z: g.maple.z }] : [])
  ]

  for (const q of points) {
    const p = { x: q.x - target.x, y: q.y - target.y, z: q.z - target.z }
    const across = Math.abs(p.x * r.x + p.y * r.y + p.z * r.z)
    const upward = Math.abs(p.x * u.x + p.y * u.y + p.z * u.z)
    const depth = p.x * f.x + p.y * f.y + p.z * f.z
    distance = Math.max(distance, across / tanH - depth, upward / tanV - depth)
  }

  return {
    azimuth,
    distance: round2(Math.min(C.maxDistance - 0.5, Math.max(C.minDistance + 1, distance))),
    polar,
    target
  }
}

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

  if (isOutdoorStroll(kind)) {
    // Along the left corridor to the sliding door, through it onto the engawa.
    const g = gardenLayout(room)
    const inside = { x: round2(g.wallX + 0.45), z: g.door.z }
    const outside = { x: round2(g.wallX - 0.7), z: g.door.z }
    const toDoor = [seat, out, { x: corridor, z: aisle }, { x: corridor, z: g.door.z }, inside, outside]

    if (kind === 'tea') {
      // A cup of tea standing by the tray on the engawa.
      const spot = { x: round2(g.wallX - 0.55), z: round2(g.tea.z + (pick - 0.5) * 0.5) }

      return { kind, points: [...toDoor, spot], face: { x: g.tea.x, z: g.tea.z } }
    }

    // Down the step onto the stepping stones, past the front of the bench.
    const step = { x: g.stones[0]!.x, z: g.door.z }
    const lawn = { x: round2(g.wallX - 3), z: round2(g.bench.z + 0.85) }

    if (kind === 'bench') {
      const seatX = round2(g.bench.x + (pick < 0.5 ? -0.35 : 0.35))

      return {
        kind,
        points: [...toDoor, step, lawn, { x: seatX, z: lawn.z }, { x: seatX, z: round2(g.bench.z + 0.08) }],
        // Sits facing the pond (+z, toward the camera).
        face: { x: seatX, z: round2(g.bench.z + 3) }
      }
    }

    // Pond: stand at its near (right) rim and watch the koi.
    const rim = { x: round2(g.pond.x + g.pond.rx + 0.3), z: round2(g.pond.z - 0.3 + pick * 0.6) }

    return { kind: 'pond', points: [...toDoor, step, lawn, rim], face: { x: g.pond.x, z: g.pond.z } }
  }

  // Two agents at the cooler at once stand a little apart.
  const spotZ = round2(cooler.z + (pick - 0.5) * 0.6)

  return {
    kind: 'cooler',
    points: [seat, out, { x: corridor, z: aisle }, { x: corridor, z: spotZ }],
    face: { x: cooler.x, z: spotZ }
  }
}

export type StrollPhase = 'back' | 'out' | 'pause' | 'sit' | 'stand'

/** One stroll in progress (the scene keeps one per figure). */
export interface StrollState {
  /** Time in the current phase (s). */
  elapsed: number
  /** Work arrived: walk back at hurry speed. */
  hurry: boolean
  length: number
  pause: number
  phase: StrollPhase
  plan: StrollPlan
  /** Distance walked along the path (m). */
  s: number
}

export function newStroll(plan: StrollPlan, pause: number): StrollState {
  return { elapsed: 0, hurry: false, length: pathLength(plan.points), pause, phase: 'stand', plan, s: 0 }
}

/**
 * Advance a stroll by dt: stand → out → pause → back → sit. `free` is false
 * once the agent has work (or an error): it turns round and hurries back to
 * the desk from wherever it is, garden included. Returns the distance walked
 * this step, the sit (0) ↔ stand (1) blend and whether the stroll is over.
 */
export function stepStroll(st: StrollState, dt: number, free: boolean): { done: boolean; moved: number; stand: number } {
  const S = OFFICE3D_STROLL
  st.elapsed += dt

  if (!free && !st.hurry) {
    st.hurry = true

    if (st.phase === 'stand') {
      st.phase = 'sit'
      st.elapsed = Math.max(0, S.standUp - st.elapsed)
    } else if (st.phase === 'out' || st.phase === 'pause') {
      st.phase = 'back'
      st.elapsed = 0
    }
  }

  const speed = st.hurry ? S.hurrySpeed : S.speed
  let moved = 0
  let stand = 1

  switch (st.phase) {
    case 'stand': {
      stand = Math.min(1, st.elapsed / S.standUp)

      if (stand >= 1) {
        st.phase = 'out'
        st.elapsed = 0
      }

      break
    }

    case 'out': {
      moved = Math.min(speed * dt, st.length - st.s)
      st.s += moved

      if (st.s >= st.length - 1e-6) {
        st.phase = 'pause'
        st.elapsed = 0
      }

      break
    }

    case 'pause': {
      if (st.elapsed >= st.pause) {
        st.phase = 'back'
        st.elapsed = 0
      }

      break
    }

    case 'back': {
      moved = Math.min(speed * dt, st.s)
      st.s -= moved

      if (st.s <= 1e-6) {
        st.s = 0
        st.phase = 'sit'
        st.elapsed = 0
      }

      break
    }

    case 'sit': {
      stand = Math.max(0, 1 - st.elapsed / S.standUp)

      return { done: stand <= 0, moved: 0, stand }
    }
  }

  return { done: false, moved, stand }
}

/** Sitting on the garden bench during the pause (eased by the scene); up
 *  again a moment before the pause ends, or at once when work arrives. */
export function perchTarget(st: null | StrollState): 0 | 1 {
  return st?.plan.kind === 'bench' && st.phase === 'pause' && !st.hurry && st.elapsed < st.pause - OFFICE3D_STROLL.standUp
    ? 1
    : 0
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

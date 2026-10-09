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

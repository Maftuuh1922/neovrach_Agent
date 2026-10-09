/**
 * Office 3D — the three.js scene: a semi-Japanese room (tatami, shoji, paper
 * lanterns, low desks, a bonsai) with one seated figure per agent.
 *
 * Plain three.js + DOM, no React and no app imports, so the phone's WebView
 * can reuse it as-is. Loaded lazily (dynamic import) so three.js stays out of
 * the startup bundle.
 *
 *   const scene = createOfficeScene({ container, labelLayer, onSelect })
 *   scene.setAgents(sceneAgents)   // on every office update
 *   scene.dispose()
 *
 * Labels are the caller's DOM: every element in `labelLayer` with
 * `data-agent-label="<id>"` is moved over that agent's head each frame.
 *
 * Idle and waiting agents now and then stand up and stroll (water cooler, a
 * neighbour's desk, a few steps along the aisle) with a walk cycle, then sit
 * back down; see OFFICE3D_STROLL / strollPlan in the model. Idle agents may
 * also slide the left shoji door open and go out to the engawa and the small
 * garden beyond it (tea, the bench, the koi pond); see OFFICE3D_GARDEN.
 */
import * as THREE from 'three'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'

import {
  cameraFrame,
  doorTarget,
  gardenLayout,
  groundHeight,
  layoutDesks,
  newStroll,
  OFFICE3D_CAMERA,
  OFFICE3D_GARDEN,
  OFFICE3D_STATUS,
  OFFICE3D_PALETTE as P,
  perchTarget,
  pointAlong,
  type RoomSize,
  type SceneAgent,
  sceneBounds,
  stepDoor,
  stepStroll,
  OFFICE3D_STROLL as STROLL,
  strollKindFor,
  strollPauseRange,
  strollPlan,
  type StrollState,
  waterCoolerSpot
} from './office3d-model'

export interface OfficeSceneOptions {
  container: HTMLElement
  /** What "Atur ulang kamera" frames: room + engawa + garden (`all`, the
   *  default) or room + engawa only (`room`, the default for thumbnails). */
  framing?: 'all' | 'room'
  labelLayer?: HTMLElement | null
  onHover?: (id: null | string) => void
  onSelect?: (id: null | string) => void
  /** Calmer motion (prefers-reduced-motion). */
  reducedMotion?: boolean
  /** Thumbnail mode (right-sidebar mini Kantor): no orbit/picking, no
   *  shadows or antialiasing, capped pixel ratio and frame rate. */
  thumbnail?: { fps?: number; pixelRatio?: number }
}

export interface OfficeScene {
  dispose: () => void
  /** Frame the camera on the whole room again. */
  resetCamera: () => void
  setAgents: (agents: SceneAgent[]) => void
  setSelected: (id: null | string) => void
  /** Stop / resume the render loop (hidden or offscreen). */
  setPaused: (paused: boolean) => void
}

const LABEL_HEIGHT = 1.75
const WALL_HEIGHT = 3.2

interface Figure {
  agent: SceneAgent
  armL: THREE.Object3D
  armR: THREE.Object3D
  body: THREE.Object3D
  coat: THREE.MeshStandardMaterial
  /** Walk-cycle angle, advanced by the distance walked. */
  gait: number
  group: THREE.Group
  head: THREE.Object3D
  heading: number
  legL: THREE.Object3D
  legR: THREE.Object3D
  lidLight: THREE.MeshStandardMaterial
  nextStroll: number
  /** Sitting on the garden bench (0 … 1). */
  perch: number
  phase: number
  ring: THREE.Mesh<THREE.RingGeometry, THREE.MeshBasicMaterial>
  /** Folded legs of the seated pose (hidden while standing). */
  seatLegs: THREE.Object3D
  /** Sit (0) ↔ stand (1). */
  stand: number
  stroll: null | StrollState
  /** Walk-cycle amplitude, eased in and out so steps start and stop smoothly. */
  swing: number
  torso: THREE.Object3D
}

const rand = (min: number, max: number) => min + Math.random() * (max - min)
const lerp = (a: number, b: number, k: number) => a + (b - a) * k
const smooth = (k: number) => k * k * (3 - 2 * k)

function turnToward(from: number, to: number, k: number): number {
  let d = to - from

  while (d > Math.PI) {
    d -= Math.PI * 2
  }

  while (d < -Math.PI) {
    d += Math.PI * 2
  }

  return from + d * k
}

export function createOfficeScene(options: OfficeSceneOptions): OfficeScene {
  const { container, labelLayer } = options
  const motion = options.reducedMotion ? 0.35 : 1
  const thumb = options.thumbnail
  const frameGap = thumb ? 1000 / Math.max(1, thumb.fps ?? 15) : 0

  const renderer = new THREE.WebGLRenderer({
    alpha: true,
    antialias: !thumb,
    powerPreference: 'low-power'
  })

  renderer.setPixelRatio(thumb ? (thumb.pixelRatio ?? 0.75) : Math.min(window.devicePixelRatio || 1, 1.5))
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.05
  renderer.shadowMap.enabled = !thumb
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  renderer.setClearColor(0x000000, 0)
  renderer.domElement.setAttribute('data-slot', 'nv-office3d-canvas')
  renderer.domElement.style.display = 'block'
  container.appendChild(renderer.domElement)

  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera(OFFICE3D_CAMERA.fov, 1, 0.1, 100)
  const controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true
  controls.dampingFactor = 0.08
  controls.minDistance = OFFICE3D_CAMERA.minDistance
  controls.maxDistance = OFFICE3D_CAMERA.maxDistance
  controls.minPolarAngle = OFFICE3D_CAMERA.minPolarAngle
  controls.maxPolarAngle = OFFICE3D_CAMERA.maxPolarAngle
  controls.minAzimuthAngle = OFFICE3D_CAMERA.minAzimuthAngle
  controls.maxAzimuthAngle = OFFICE3D_CAMERA.maxAzimuthAngle
  controls.screenSpacePanning = false
  controls.enabled = !thumb

  // Everything we allocate, so dispose() frees it.
  const disposables: { dispose: () => void }[] = []

  const track = <T extends { dispose: () => void }>(thing: T): T => {
    disposables.push(thing)

    return thing
  }

  const mat = (color: string, extra: THREE.MeshStandardMaterialParameters = {}) =>
    track(
      new THREE.MeshStandardMaterial({
        color,
        roughness: 0.85,
        metalness: 0,
        ...extra
      })
    )

  const M = {
    woodDark: mat(P.woodDark, { roughness: 0.7 }),
    woodLight: mat(P.woodLight, { roughness: 0.6 }),
    deskTop: mat(P.deskTop, { roughness: 0.55 }),
    plaster: mat(P.plaster, { roughness: 0.95 }),
    paper: mat(P.shojiPaper, {
      emissive: new THREE.Color(P.shojiGlow),
      emissiveIntensity: 0.32,
      roughness: 1
    }),
    engawa: mat(P.engawa, { roughness: 0.6 }),
    border: mat(P.tatamiBorder, { roughness: 0.9 }),
    zabuton: mat(P.zabuton, { roughness: 1 }),
    skin: mat(P.skin, { roughness: 0.8 }),
    hair: mat(P.hair, { roughness: 0.9 }),
    laptop: mat(P.laptop, { roughness: 0.4, metalness: 0.3 }),
    lantern: mat(P.lanternPaper, {
      emissive: new THREE.Color(P.lanternGlow),
      emissiveIntensity: 1.1,
      roughness: 1
    }),
    lanternCap: mat(P.lanternCap),
    leaf: mat(P.bonsaiLeaf, { flatShading: true }),
    trunk: mat(P.bonsaiTrunk),
    pot: mat(P.pot, { roughness: 0.5 }),
    coolerStand: mat(P.coolerStand, { roughness: 0.7 }),
    coolerWater: mat(P.coolerWater, { roughness: 0.15, transparent: true, opacity: 0.75 }),
    gardenEdge: mat(P.gardenEdge, { roughness: 1 }),
    rake: mat(P.gravelRake, { roughness: 1 }),
    stone: mat(P.stone, { flatShading: true, roughness: 0.95 }),
    stoneDark: mat(P.stoneDark, { flatShading: true, roughness: 0.95 }),
    pond: mat(P.pond, { roughness: 0.18, metalness: 0.1 }),
    koi: mat(P.koi, { roughness: 0.6 }),
    koiWhite: mat(P.teaCup, { roughness: 0.6 }),
    maple: mat(P.maple, { flatShading: true }),
    mapleDeep: mat(P.mapleDeep, { flatShading: true }),
    pine: mat(P.pine, { flatShading: true }),
    moss: mat(P.moss, { flatShading: true }),
    cup: mat(P.teaCup, { roughness: 0.5 })
  }

  const G = {
    box: track(new THREE.BoxGeometry(1, 1, 1)),
    cyl: track(new THREE.CylinderGeometry(0.5, 0.5, 1, 10)),
    sphere: track(new THREE.SphereGeometry(0.5, 14, 10)),
    ico: track(new THREE.IcosahedronGeometry(0.5, 0)),
    ring: track(new THREE.RingGeometry(0.62, 0.78, 36)),
    cone: track(new THREE.ConeGeometry(0.5, 1, 4)),
    rake: track(new THREE.RingGeometry(0.96, 1, 40))
  }

  const box = (
    parent: THREE.Object3D,
    material: THREE.Material,
    [sx, sy, sz]: [number, number, number],
    [x, y, z]: [number, number, number],
    shadow = true
  ) => {
    const mesh = new THREE.Mesh(G.box, material)
    mesh.scale.set(sx, sy, sz)
    mesh.position.set(x, y, z)
    mesh.castShadow = shadow
    mesh.receiveShadow = true
    parent.add(mesh)

    return mesh
  }

  // ── lights ────────────────────────────────────────────────────────────────
  scene.add(new THREE.HemisphereLight(P.hemiSky, P.hemiGround, 1.15))
  const sun = new THREE.DirectionalLight(P.sun, 1.6)
  sun.castShadow = true
  sun.shadow.mapSize.set(1024, 1024)
  sun.shadow.bias = -0.0005
  sun.shadow.radius = 4
  scene.add(sun, sun.target)

  // ── room (rebuilt when the desk count changes the room size) ──────────────
  const room = new THREE.Group()
  scene.add(room)
  const lanternLights: THREE.PointLight[] = []
  const lanterns: THREE.Object3D[] = []
  let roomKey = ''

  const tatamiTexture = track(makeTatamiTexture())
  const gravelTexture = track(makeGravelTexture())
  const koi: THREE.Object3D[] = []
  let doorPanel: null | THREE.Object3D = null
  let doorOpen = 0
  let roomSize: RoomSize = { width: 12, depth: 9 }
  // buildRoom runs once before the camera helpers exist.
  let cameraReady = false

  function buildRoom(width: number, depth: number) {
    const key = `${width}x${depth}`

    if (key === roomKey) {
      return
    }

    roomKey = key
    roomSize = { width, depth }
    room.traverse(obj => {
      if (obj instanceof THREE.InstancedMesh) {
        obj.dispose()
      }
    })
    room.clear()
    lanternLights.length = 0
    lanterns.length = 0
    koi.length = 0
    doorPanel = null

    const hw = width / 2
    const hd = depth / 2

    // Raised floor slab with an engawa (wooden edge) all round.
    box(room, M.engawa, [width + 0.6, 0.3, depth + 0.6], [0, -0.15, 0], false)

    // Tatami: 2 × 1 mats in running bond, each with dark cloth borders (heri).
    const matMaterial = track(
      new THREE.MeshStandardMaterial({
        color: P.tatami,
        map: tatamiTexture,
        roughness: 0.95
      })
    )

    const mats: { x: number; z: number; w: number; d: number }[] = []

    for (let row = 0, z = -hd; z < hd - 0.01; row++, z += 1) {
      const d = Math.min(1, hd - z)
      let x = -hw - (row % 2 ? 1 : 0)

      while (x < hw - 0.01) {
        const x0 = Math.max(x, -hw)
        const x1 = Math.min(x + 2, hw)
        mats.push({ x: (x0 + x1) / 2, z: z + d / 2, w: x1 - x0, d })
        x += 2
      }
    }

    const matMesh = new THREE.InstancedMesh(G.box, matMaterial, mats.length)
    const heriMesh = new THREE.InstancedMesh(G.box, M.border, mats.length * 2)
    const m4 = new THREE.Matrix4()

    mats.forEach((tile, i) => {
      m4.compose(
        new THREE.Vector3(tile.x, 0.02, tile.z),
        new THREE.Quaternion(),
        new THREE.Vector3(tile.w - 0.02, 0.04, tile.d - 0.02)
      )
      matMesh.setMatrixAt(i, m4)

      // Heri run along the long sides of each mat.
      for (const side of [-1, 1]) {
        m4.compose(
          new THREE.Vector3(tile.x, 0.042, tile.z + side * (tile.d / 2 - 0.035)),
          new THREE.Quaternion(),
          new THREE.Vector3(tile.w - 0.02, 0.006, 0.05)
        )
        heriMesh.setMatrixAt(i * 2 + (side < 0 ? 0 : 1), m4)
      }
    })
    matMesh.receiveShadow = true
    heriMesh.receiveShadow = true
    room.add(matMesh, heriMesh)

    // Walls: back (-z) and left (-x) are shoji screens between posts; the
    // front and right stay open so the camera sees in.
    buildShojiWall(room, width, [0, -hd], 0)
    buildLeftWallWithDoor(width, depth)
    buildGarden({ width, depth })

    // Corner posts and a top beam on the open sides for structure.
    box(room, M.woodDark, [0.18, WALL_HEIGHT, 0.18], [hw, WALL_HEIGHT / 2, -hd])
    box(room, M.woodDark, [0.18, WALL_HEIGHT, 0.18], [-hw, WALL_HEIGHT / 2, hd])

    // Tokonoma corner: a hanging scroll with a red ensō, a bonsai on a stand.
    const scroll = new THREE.Mesh(
      track(new THREE.PlaneGeometry(0.9, 1.7)),
      track(
        new THREE.MeshStandardMaterial({
          map: track(makeEnsoTexture()),
          roughness: 1
        })
      )
    )

    scroll.position.set(hw - 1.6, 1.75, -hd + 0.09)
    room.add(scroll)
    box(room, M.woodDark, [1.05, 0.06, 0.06], [hw - 1.6, 2.63, -hd + 0.1])
    box(room, M.woodDark, [1.0, 0.05, 0.05], [hw - 1.6, 0.88, -hd + 0.1])
    box(room, M.woodLight, [1.6, 0.16, 0.8], [hw - 1.6, 0.08, -hd + 0.55])
    buildBonsai(room, [hw - 1.6, 0.16, -hd + 0.55])

    // Water cooler against the left shoji, where strolling agents go.
    const cooler = waterCoolerSpot({ width, depth })
    box(room, M.coolerStand, [0.36, 0.86, 0.36], [cooler.x, 0.43, cooler.z])
    box(room, M.woodDark, [0.38, 0.04, 0.38], [cooler.x, 0.88, cooler.z])
    const bottle = new THREE.Mesh(G.cyl, M.coolerWater)
    bottle.scale.set(0.26, 0.42, 0.26)
    bottle.position.set(cooler.x, 1.11, cooler.z)
    room.add(bottle)
    box(room, M.laptop, [0.05, 0.05, 0.06], [cooler.x + 0.2, 0.7, cooler.z])

    // Paper lanterns (chōchin) hanging in a row; two carry real lights.
    const count = Math.max(2, Math.round(width / 5))

    for (let i = 0; i < count; i++) {
      const x = -hw + ((i + 0.5) * width) / count
      const lantern = buildLantern(room, [x, 2.55, -hd + depth * 0.42])
      lanterns.push(lantern)

      if (i === 0 || i === count - 1) {
        const light = new THREE.PointLight(P.lanternGlow, 5, 7, 1.6)
        light.position.set(x, 2.45, -hd + depth * 0.42)
        room.add(light)
        lanternLights.push(light)
      }
    }

    // Daylight through the left shoji.
    sun.position.set(-hw - 4, 9, hd * 0.6)
    sun.target.position.set(0, 0, 0)
    const reach = Math.max(width, depth) * 0.75
    Object.assign(sun.shadow.camera, {
      left: -reach,
      right: reach,
      top: reach,
      bottom: -reach,
      near: 1,
      far: 40
    })
    sun.shadow.camera.updateProjectionMatrix()

    if (!userMoved && cameraReady) {
      frameCamera()
    }
  }

  /** The left shoji in two runs either side of a sliding door, with the
   *  kamoi, plaster and top beam carried across the opening. */
  function buildLeftWallWithDoor(width: number, depth: number) {
    const hd = depth / 2
    const g = gardenLayout({ width, depth })
    const half = g.door.width / 2
    const a0 = -hd
    const a1 = g.door.z - half
    const b0 = g.door.z + half
    const b1 = hd
    buildShojiWall(room, a1 - a0, [g.wallX, (a0 + a1) / 2], Math.PI / 2)
    buildShojiWall(room, b1 - b0, [g.wallX, (b0 + b1) / 2], Math.PI / 2)

    const base = 0.32
    const paperH = 2.1
    const x = g.wallX
    box(room, M.plaster, [0.08, WALL_HEIGHT - base - paperH, g.door.width], [x - 0.04, (WALL_HEIGHT + base + paperH) / 2, g.door.z], false)
    box(room, M.woodDark, [0.14, 0.12, g.door.width], [x + 0.02, base + paperH + 0.06, g.door.z], false)
    box(room, M.woodDark, [0.16, 0.14, g.door.width], [x + 0.02, WALL_HEIGHT - 0.07, g.door.z], false)
    // Sill (shikii) and the outside rails the door slides in.
    box(room, M.woodDark, [0.18, 0.05, g.door.width], [x, 0.025, g.door.z], false)
    box(room, M.woodDark, [0.08, 0.03, g.door.width * 2.2], [x - 0.14, 0.015, g.door.z + half], false)
    box(room, M.woodDark, [0.08, 0.06, g.door.width * 2.2], [x - 0.14, base + paperH + 0.03, g.door.z + half], false)

    // The sliding panel: a shoji leaf outside the posts; slides toward +z.
    const leaf = new THREE.Group()
    leaf.position.set(x - 0.14, 0, g.door.z)
    room.add(leaf)
    const h = base + paperH - 0.04
    const w = g.door.width - 0.02
    const paper = new THREE.Mesh(G.box, M.paper)
    paper.scale.set(0.015, h - 0.1, w - 0.06)
    paper.position.y = 0.03 + h / 2
    leaf.add(paper)

    const bars: [number, number, number, number, number][] = [
      [0.05, h, 0.05, 0.03 + h / 2, -w / 2 + 0.025],
      [0.05, h, 0.05, 0.03 + h / 2, w / 2 - 0.025],
      [0.05, 0.06, w, 0.06, 0],
      [0.05, 0.05, w, 0.03 + h - 0.025, 0],
      // Kick panel (koshi) at the bottom, like the wall's skirting.
      [0.04, base - 0.06, w, 0.03 + (base - 0.06) / 2 + 0.03, 0]
    ]

    for (let k = 1; k < 3; k++) {
      bars.push([0.03, h - base, 0.022, base + (h - base) / 2, -w / 2 + (k * w) / 3])
    }

    for (let k = 1; k < 6; k++) {
      bars.push([0.03, 0.022, w, base + (k * (h - base)) / 6, 0])
    }

    for (const [sx, sy, sz, y, z] of bars) {
      box(leaf, M.woodDark, [sx, sy, sz], [0, y, z], false)
    }

    doorPanel = leaf
    leaf.position.z = g.door.z + doorOpen * (g.door.width - 0.04)
  }

  /** Engawa deck, raked gravel one step down, stepping stones, a koi pond,
   *  a stone lantern, a maple and a pine, a bench and a tea tray. Low-poly,
   *  no shadow casting (it sits outside the sun's shadow frustum anyway). */
  function buildGarden(size: RoomSize) {
    const g = gardenLayout(size)
    const hd = size.depth / 2
    const gy = g.groundY
    const deckZ0 = -hd - 0.3
    const deckZ1 = hd + 0.3

    // Engawa: a plank deck along the outside of the left wall, flush with the floor.
    const deckW = g.wallX - 0.3 - g.engawaX
    const deckX = g.engawaX + deckW / 2
    box(room, M.engawa, [deckW, 0.3, deckZ1 - deckZ0], [deckX, -0.15, 0], false)
    const planks = Math.max(2, Math.round((g.wallX - g.engawaX) / 0.2))
    const seams = new THREE.InstancedMesh(G.box, M.woodDark, planks - 1)
    const m4 = new THREE.Matrix4()

    for (let i = 1; i < planks; i++) {
      const px = g.engawaX + (i * (g.wallX - g.engawaX)) / planks
      m4.compose(new THREE.Vector3(px, 0.002, 0), new THREE.Quaternion(), new THREE.Vector3(0.012, 0.004, deckZ1 - deckZ0))
      seams.setMatrixAt(i - 1, m4)
    }

    room.add(seams)
    // Edge beam along the deck's outer side.
    box(room, M.woodDark, [0.1, 0.32, deckZ1 - deckZ0], [g.engawaX + 0.05, -0.15, 0], false)

    // Gravel bed with a darker kerb below it.
    const gw = g.garden.x1 - g.garden.x0
    const gd = g.garden.z1 - g.garden.z0
    const gx = (g.garden.x0 + g.garden.x1) / 2
    const gz = (g.garden.z0 + g.garden.z1) / 2
    box(room, M.gardenEdge, [gw + 0.24, 0.4, gd + 0.24], [gx - 0.12, gy - 0.22, gz], false)
    const gravelMat = track(new THREE.MeshStandardMaterial({ color: '#ffffff', map: gravelTexture, roughness: 1 }))
    gravelTexture.repeat.set(gw / 2, gd / 2)
    box(room, gravelMat, [gw, 0.3, gd], [gx, gy - 0.15, gz], false)

    // Raked rings round the pond and the lantern (flat rings on the gravel).
    const ring = (x: number, z: number, rx: number, rz: number) => {
      const r = new THREE.Mesh(G.rake, M.rake)
      r.rotation.x = -Math.PI / 2
      r.scale.set(rx, rz, 1)
      r.position.set(x, gy + 0.004, z)
      room.add(r)
    }

    for (const k of [1.25, 1.5, 1.75]) {
      ring(g.pond.x, g.pond.z, g.pond.rx * k, g.pond.rz * k)
    }

    for (const k of [0.55, 0.8]) {
      ring(g.lantern.x, g.lantern.z, k, k)
    }

    // Shoe stone at the engawa step, then the stepping stones.
    box(room, M.stone, [0.5, 0.16, 0.34], [g.engawaX - 0.3, gy + 0.06, g.door.z], false)

    for (const st of g.stones) {
      const stone = new THREE.Mesh(G.cyl, M.stone)
      stone.scale.set(st.r * 2, 0.06, st.r * 1.7)
      stone.position.set(st.x, gy + 0.02, st.z)
      stone.rotation.y = st.x * 1.7
      room.add(stone)
    }

    // Koi pond: dark water in an ellipse, a rim of rocks, two koi circling.
    const water = new THREE.Mesh(G.cyl, M.pond)
    water.scale.set(g.pond.rx * 2, 0.04, g.pond.rz * 2)
    water.position.set(g.pond.x, gy + 0.012, g.pond.z)
    room.add(water)

    for (let i = 0; i < 11; i++) {
      const a = (i / 11) * Math.PI * 2 + 0.3
      const rock = new THREE.Mesh(G.ico, i % 3 ? M.stone : M.stoneDark)
      const s = 0.2 + ((i * 37) % 7) * 0.025
      rock.scale.set(s * 1.3, s * 0.7, s)
      rock.position.set(g.pond.x + Math.cos(a) * (g.pond.rx + 0.05), gy + 0.05, g.pond.z + Math.sin(a) * (g.pond.rz + 0.05))
      rock.rotation.y = a
      room.add(rock)
    }

    for (const [i, material] of [M.koi, M.koiWhite].entries()) {
      const fish = new THREE.Group()
      fish.position.set(g.pond.x, gy + 0.04, g.pond.z)
      fish.userData.offset = i * Math.PI
      const fishBody = new THREE.Mesh(G.sphere, material)
      fishBody.scale.set(0.09, 0.04, 0.24)
      fish.add(fishBody)
      const tail = new THREE.Mesh(G.box, i ? M.koi : M.koiWhite)
      tail.scale.set(0.1, 0.01, 0.07)
      tail.position.z = -0.14
      fish.add(tail)
      room.add(fish)
      koi.push(fish)
    }

    // Stone lantern (tōrō) by the pond, with a warm light window.
    const L = g.lantern

    const cyl = (material: THREE.Material, [sx, sy, sz]: [number, number, number], y: number) => {
      const m = new THREE.Mesh(G.cyl, material)
      m.scale.set(sx, sy, sz)
      m.position.set(L.x, gy + y, L.z)
      room.add(m)

      return m
    }

    cyl(M.stoneDark, [0.46, 0.12, 0.46], 0.06)
    cyl(M.stone, [0.16, 0.62, 0.16], 0.43)
    box(room, M.stone, [0.42, 0.06, 0.42], [L.x, gy + 0.77, L.z], false)
    box(room, M.stone, [0.32, 0.26, 0.32], [L.x, gy + 0.93, L.z], false)
    box(room, M.lantern, [0.34, 0.12, 0.2], [L.x, gy + 0.94, L.z], false)
    box(room, M.lantern, [0.2, 0.12, 0.34], [L.x, gy + 0.94, L.z], false)
    const roof = new THREE.Mesh(G.cone, M.stoneDark)
    roof.scale.set(0.7, 0.24, 0.7)
    roof.rotation.y = Math.PI / 4
    roof.position.set(L.x, gy + 1.18, L.z)
    room.add(roof)
    const knob = new THREE.Mesh(G.sphere, M.stone)
    knob.scale.setScalar(0.1)
    knob.position.set(L.x, gy + 1.33, L.z)
    room.add(knob)

    // Maple (momiji) with red pads, and a cloud-pruned pine.
    const tree = (x: number, z: number, height: number, lean: number, pads: [number, number, number, number, THREE.Material][]) => {
      const trunk = new THREE.Mesh(G.cyl, M.trunk)
      trunk.scale.set(0.16, height, 0.16)
      trunk.position.set(x, gy + height / 2, z)
      trunk.rotation.z = lean
      room.add(trunk)

      for (const [px, py, pz, s, material] of pads) {
        const pad = new THREE.Mesh(G.ico, material)
        pad.scale.set(s * 1.25, s * 0.62, s)
        pad.position.set(x + px, gy + py, z + pz)
        pad.rotation.y = px * 3
        room.add(pad)
      }
    }

    tree(g.maple.x, g.maple.z, 2.1, -0.12, [
      [0.25, 2.35, 0, 1.3, M.maple],
      [-0.45, 2.05, 0.35, 0.95, M.mapleDeep],
      [0.6, 1.95, -0.3, 0.85, M.maple],
      [0.1, 2.75, -0.15, 0.9, M.mapleDeep]
    ])
    tree(g.pine.x, g.pine.z, 1.6, 0.1, [
      [0.15, 1.75, 0, 0.95, M.pine],
      [-0.35, 1.3, 0.1, 0.7, M.pine],
      [0.45, 1.1, -0.1, 0.6, M.pine]
    ])

    // A few mossy shrubs (azalea mounds).
    for (const [x, z, s] of [
      [L.x + 0.55, L.z - 0.6, 0.55],
      [g.maple.x + 1.1, g.maple.z + 0.9, 0.6],
      [g.engawaX - 0.55, g.door.z - 1.8, 0.5],
      [g.pond.x - g.pond.rx - 0.4, g.pond.z - 0.5, 0.45]
    ] as const) {
      const shrub = new THREE.Mesh(G.ico, M.moss)
      shrub.scale.set(s * 1.3, s * 0.7, s)
      shrub.position.set(x, gy + s * 0.25, z)
      room.add(shrub)
    }

    // Bench facing the pond.
    const B = g.bench
    const seatY = gy + OFFICE3D_GARDEN.benchSeat
    box(room, M.woodLight, [B.length, 0.06, 0.42], [B.x, seatY - 0.03, B.z], false)

    for (const side of [-1, 1]) {
      box(room, M.stoneDark, [0.16, OFFICE3D_GARDEN.benchSeat - 0.06, 0.34], [B.x + side * (B.length / 2 - 0.2), gy + (OFFICE3D_GARDEN.benchSeat - 0.06) / 2, B.z], false)
    }

    // Tea tray on the engawa: a pot and two cups.
    const T = g.tea
    box(room, M.woodDark, [0.42, 0.03, 0.3], [T.x, 0.015, T.z], false)
    const pot = new THREE.Mesh(G.sphere, M.pot)
    pot.scale.set(0.15, 0.12, 0.15)
    pot.position.set(T.x - 0.08, 0.09, T.z)
    room.add(pot)

    for (const dz of [-0.08, 0.08]) {
      const cup = new THREE.Mesh(G.cyl, M.cup)
      cup.scale.set(0.06, 0.05, 0.06)
      cup.position.set(T.x + 0.11, 0.055, T.z + dz)
      room.add(cup)
    }

    // Low bamboo fence along the far side and the back of the garden.
    const fence: THREE.Matrix4[] = []

    const post = (x: number, z: number) =>
      fence.push(new THREE.Matrix4().compose(new THREE.Vector3(x, gy + 0.45, z), new THREE.Quaternion(), new THREE.Vector3(0.07, 0.9, 0.07)))

    const rail = (x: number, z: number, sx: number, sz: number, y: number) =>
      fence.push(new THREE.Matrix4().compose(new THREE.Vector3(x, gy + y, z), new THREE.Quaternion(), new THREE.Vector3(sx, 0.04, sz)))

    for (let z = g.garden.z0; z <= g.garden.z1 + 0.01; z += (g.garden.z1 - g.garden.z0) / Math.round((g.garden.z1 - g.garden.z0) / 1.2)) {
      post(g.garden.x0, z)
    }

    for (let x = g.garden.x0; x <= g.garden.x1 + 0.01; x += gw / Math.round(gw / 1.2)) {
      post(x, g.garden.z0)
    }

    for (const y of [0.35, 0.75]) {
      rail(g.garden.x0, gz, 0.05, gd, y)
      rail(gx, g.garden.z0, gw, 0.05, y)
    }

    const fenceMesh = new THREE.InstancedMesh(G.box, M.woodLight, fence.length)
    fence.forEach((m, i) => fenceMesh.setMatrixAt(i, m))
    room.add(fenceMesh)
  }

  function buildShojiWall(parent: THREE.Object3D, length: number, [cx, cz]: [number, number], rotY: number) {
    const wall = new THREE.Group()
    wall.position.set(cx, 0, cz)
    wall.rotation.y = rotY
    parent.add(wall)

    const half = length / 2
    const panels = Math.max(2, Math.round(length / 1.5))
    const pw = length / panels
    const paperH = 2.1
    const base = 0.32
    const frames: THREE.Matrix4[] = []

    const add = (sx: number, sy: number, sz: number, x: number, y: number, z: number) =>
      frames.push(
        new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion(), new THREE.Vector3(sx, sy, sz))
      )

    // Plaster band above, wooden kamoi beam, skirting below.
    box(
      wall,
      M.plaster,
      [length, WALL_HEIGHT - base - paperH, 0.08],
      [0, (WALL_HEIGHT + base + paperH) / 2, -0.04],
      false
    )
    add(length, 0.12, 0.14, 0, base + paperH + 0.06, 0.02)
    add(length, base, 0.14, 0, base / 2, 0.02)
    add(length, 0.14, 0.16, 0, WALL_HEIGHT - 0.07, 0.02)

    // One paper plane across, kumiko lattice on top of it.
    const paper = new THREE.Mesh(G.box, M.paper)
    paper.scale.set(length, paperH, 0.02)
    paper.position.set(0, base + paperH / 2, 0)
    paper.receiveShadow = true
    wall.add(paper)

    for (let i = 0; i <= panels; i++) {
      const x = -half + i * pw
      // Stiles (thick at panel joins).
      add(0.07, paperH, 0.07, x, base + paperH / 2, 0.03)
    }

    for (let i = 0; i < panels; i++) {
      const x0 = -half + i * pw

      for (let k = 1; k < 3; k++) {
        add(0.022, paperH, 0.03, x0 + (k * pw) / 3, base + paperH / 2, 0.03)
      }

      for (let k = 1; k < 6; k++) {
        add(pw, 0.022, 0.03, x0 + pw / 2, base + (k * paperH) / 6, 0.03)
      }
    }

    // Posts at both ends.
    add(0.18, WALL_HEIGHT, 0.18, -half, WALL_HEIGHT / 2, 0.02)
    add(0.18, WALL_HEIGHT, 0.18, half, WALL_HEIGHT / 2, 0.02)

    const lattice = new THREE.InstancedMesh(G.box, M.woodDark, frames.length)
    frames.forEach((m, i) => lattice.setMatrixAt(i, m))
    lattice.castShadow = true
    lattice.receiveShadow = true
    wall.add(lattice)
  }

  function buildBonsai(parent: THREE.Object3D, [x, y, z]: [number, number, number]) {
    const g = new THREE.Group()
    g.position.set(x, y, z)
    parent.add(g)
    const pot = new THREE.Mesh(G.box, M.pot)
    pot.scale.set(0.55, 0.16, 0.36)
    pot.position.y = 0.08
    pot.castShadow = true
    g.add(pot)
    const trunk = new THREE.Mesh(G.cyl, M.trunk)
    trunk.scale.set(0.07, 0.42, 0.07)
    trunk.position.set(0.02, 0.36, 0)
    trunk.rotation.z = -0.35
    trunk.castShadow = true
    g.add(trunk)

    const pads: [number, number, number, number][] = [
      [0.14, 0.58, 0, 0.36],
      [-0.12, 0.5, 0.05, 0.28],
      [0.03, 0.72, -0.04, 0.24]
    ]

    for (const [px, py, pz, s] of pads) {
      const leaf = new THREE.Mesh(G.ico, M.leaf)
      leaf.scale.set(s * 1.3, s * 0.6, s)
      leaf.position.set(px, py, pz)
      leaf.castShadow = true
      g.add(leaf)
    }
  }

  function buildLantern(parent: THREE.Object3D, [x, y, z]: [number, number, number]) {
    const g = new THREE.Group()
    g.position.set(x, y, z)
    parent.add(g)
    const body = new THREE.Mesh(G.sphere, M.lantern)
    body.scale.set(0.42, 0.55, 0.42)
    g.add(body)

    for (const dy of [0.27, -0.27]) {
      const cap = new THREE.Mesh(G.cyl, M.lanternCap)
      cap.scale.set(0.26, 0.05, 0.26)
      cap.position.y = dy
      g.add(cap)
    }

    const cord = new THREE.Mesh(G.cyl, M.lanternCap)
    cord.scale.set(0.012, WALL_HEIGHT - y, 0.012)
    cord.position.y = (WALL_HEIGHT - y) / 2 + 0.27
    g.add(cord)

    return g
  }

  // ── desks + figures ───────────────────────────────────────────────────────
  const figures = new Map<string, Figure>()
  const pickables: THREE.Object3D[] = []
  let selected: null | string = null

  function buildFigure(agent: SceneAgent): Figure {
    const group = new THREE.Group()
    group.userData.agentId = agent.id
    scene.add(group)

    // Low desk (in front of the agent, toward +z) with a laptop on it.
    box(group, M.deskTop, [1.5, 0.06, 0.75], [0, 0.42, 0.55])

    for (const sx of [-0.68, 0.68]) {
      for (const sz of [0.25, 0.85]) {
        box(group, M.woodDark, [0.06, 0.39, 0.06], [sx, 0.2, sz])
      }
    }

    box(group, M.laptop, [0.5, 0.025, 0.34], [0, 0.465, 0.5])
    const lid = box(group, M.laptop, [0.5, 0.32, 0.02], [0, 0.63, 0.67])
    lid.rotation.x = 0.25

    // A status light on the back of the lid, facing the camera.
    const lidLight = track(
      new THREE.MeshStandardMaterial({
        color: '#111',
        emissive: new THREE.Color('#000'),
        emissiveIntensity: 1.4
      })
    )

    const lamp = new THREE.Mesh(G.box, lidLight)
    lamp.scale.set(0.12, 0.05, 0.01)
    lamp.position.set(0, 0.64, 0.69)
    lamp.rotation.x = 0.25
    group.add(lamp)

    // Zabuton cushion.
    box(group, M.zabuton, [0.8, 0.09, 0.8], [0, 0.07, -0.2])

    // Status ring on the tatami around the cushion.
    const ring = new THREE.Mesh(
      G.ring,
      track(
        new THREE.MeshBasicMaterial({
          color: '#888',
          transparent: true,
          opacity: 0.8,
          depthWrite: false
        })
      )
    )

    ring.rotation.x = -Math.PI / 2
    ring.position.set(0, 0.05, -0.15)
    ring.scale.setScalar(0.85)
    group.add(ring)

    // Seated figure, facing +z: torso, head with hair, two arms, folded legs.
    const coat = mat(agent.coat, { roughness: 0.9 })
    const body = new THREE.Group()
    body.position.set(0, 0.12, -0.22)
    group.add(body)
    const legs = new THREE.Mesh(G.box, coat)
    legs.scale.set(0.56, 0.16, 0.5)
    legs.position.set(0, 0.08, 0.08)
    legs.castShadow = true
    body.add(legs)

    // Standing legs for strolls: pivots at the hips, hidden while seated.
    const leg = (side: number) => {
      const pivot = new THREE.Group()
      pivot.position.set(side * 0.12, 0.16, 0)
      pivot.visible = false
      body.add(pivot)
      const limb = new THREE.Mesh(G.cyl, coat)
      limb.scale.set(0.15, 0.46, 0.15)
      limb.position.y = -0.23
      limb.castShadow = true
      pivot.add(limb)
      const foot = new THREE.Mesh(G.box, M.hair)
      foot.scale.set(0.13, 0.06, 0.22)
      foot.position.set(0, -0.46, 0.04)
      pivot.add(foot)

      return pivot
    }

    const torso = new THREE.Group()
    torso.position.y = 0.16
    body.add(torso)
    const chest = new THREE.Mesh(G.cyl, coat)
    chest.scale.set(0.42, 0.5, 0.3)
    chest.position.y = 0.25
    chest.castShadow = true
    torso.add(chest)

    const head = new THREE.Group()
    head.position.y = 0.66
    torso.add(head)
    const face = new THREE.Mesh(G.sphere, M.skin)
    face.scale.setScalar(0.3)
    face.castShadow = true
    head.add(face)
    const hair = new THREE.Mesh(G.sphere, M.hair)
    hair.scale.set(0.32, 0.24, 0.32)
    hair.position.set(0, 0.06, -0.025)
    head.add(hair)

    const arm = (side: number) => {
      const pivot = new THREE.Group()
      pivot.position.set(side * 0.25, 0.45, 0)
      torso.add(pivot)
      const limb = new THREE.Mesh(G.cyl, coat)
      limb.scale.set(0.09, 0.38, 0.09)
      limb.position.y = -0.19
      limb.castShadow = true
      pivot.add(limb)
      const hand = new THREE.Mesh(G.sphere, M.skin)
      hand.scale.setScalar(0.09)
      hand.position.y = -0.39
      pivot.add(hand)

      return pivot
    }

    // Invisible hit box so the whole desk is clickable.
    const hit = new THREE.Mesh(G.box, track(new THREE.MeshBasicMaterial({ visible: false })))
    hit.scale.set(1.7, 1.5, 1.8)
    hit.position.set(0, 0.75, 0.25)
    hit.userData.agentId = agent.id
    group.add(hit)
    pickables.push(hit)

    return {
      agent,
      armL: arm(-1),
      armR: arm(1),
      body,
      coat,
      gait: 0,
      group,
      head,
      heading: 0,
      legL: leg(-1),
      legR: leg(1),
      lidLight,
      nextStroll: clock.getElapsedTime() + rand(STROLL.firstMin, STROLL.firstMax),
      perch: 0,
      phase: Math.random() * Math.PI * 2,
      ring,
      seatLegs: legs,
      stand: 0,
      stroll: null,
      swing: 0,
      torso
    }
  }

  function applyAgent(figure: Figure, agent: SceneAgent) {
    if (figure.agent.x !== agent.x || figure.agent.z !== agent.z) {
      // The desk moved (layout changed): drop any stroll, sit at the new desk.
      figure.stroll = null
      figure.stand = 0
      figure.perch = 0
      figure.heading = 0
    }

    figure.agent = agent
    figure.group.position.set(agent.x, 0, agent.z)
    figure.coat.color.set(agent.coat)
    const color = new THREE.Color(OFFICE3D_STATUS[agent.status].color)
    figure.ring.material.color.copy(color)
    figure.lidLight.emissive.copy(color)
    figure.lidLight.color.copy(color)
  }

  function removeFigure(id: string) {
    const figure = figures.get(id)

    if (!figure) {
      return
    }

    scene.remove(figure.group)
    const idx = pickables.findIndex(obj => obj.userData.agentId === id)

    if (idx >= 0) {
      pickables.splice(idx, 1)
    }

    figures.delete(id)
  }

  function setAgents(agents: SceneAgent[]) {
    const { room: size } = layoutDesks(agents.length)
    buildRoom(size.width, size.depth)
    const keep = new Set(agents.map(a => a.id))

    for (const id of [...figures.keys()]) {
      if (!keep.has(id)) {
        removeFigure(id)
      }
    }

    for (const agent of agents) {
      let figure = figures.get(agent.id)

      if (!figure) {
        figure = buildFigure(agent)
        figures.set(agent.id, figure)
      }

      applyAgent(figure, agent)
    }

    if (selected && !keep.has(selected)) {
      selected = null
    }
  }

  // ── camera ────────────────────────────────────────────────────────────────
  // Until the user orbits/zooms, the camera re-frames itself when the room
  // grows or the view is resized. The full Kantor frames room + engawa +
  // garden; the thumbnail crops to room + engawa.
  let userMoved = false

  function resetCamera() {
    userMoved = false
    frameCamera()
  }

  function frameCamera() {
    const frame = cameraFrame(roomSize, camera.aspect || 1, options.framing ?? (thumb ? 'room' : 'all'))
    const { azimuth, distance, polar, target } = frame
    controls.target.set(target.x, target.y, target.z)
    camera.position.set(
      target.x + distance * Math.sin(polar) * Math.sin(azimuth),
      target.y + distance * Math.cos(polar),
      target.z + distance * Math.sin(polar) * Math.cos(azimuth)
    )
    controls.update()
  }

  function clampTarget() {
    // The pan target stays over the floor (room, engawa or garden).
    const b = sceneBounds(roomSize, 'all')
    const t = controls.target
    t.x = THREE.MathUtils.clamp(t.x, b.x0, b.x1)
    t.z = THREE.MathUtils.clamp(t.z, b.z0, b.z1)
    t.y = THREE.MathUtils.clamp(t.y, 0.2, 2)
  }

  const onControlStart = () => {
    userMoved = true
  }

  controls.addEventListener('start', onControlStart)
  controls.addEventListener('change', clampTarget)

  // ── picking ───────────────────────────────────────────────────────────────
  const raycaster = new THREE.Raycaster()
  const pointer = new THREE.Vector2()
  let down: null | { x: number; y: number } = null
  let hovered: null | string = null

  const pick = (event: PointerEvent): null | string => {
    const rect = renderer.domElement.getBoundingClientRect()
    pointer.set(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1)
    raycaster.setFromCamera(pointer, camera)
    const hit = raycaster.intersectObjects(pickables, false)[0]

    return (hit?.object.userData.agentId as string | undefined) ?? null
  }

  const onPointerDown = (event: PointerEvent) => {
    down = { x: event.clientX, y: event.clientY }
  }

  const onPointerUp = (event: PointerEvent) => {
    if (!down || Math.hypot(event.clientX - down.x, event.clientY - down.y) > 5) {
      down = null

      return
    }

    down = null
    const id = pick(event)
    setSelected(id)
    options.onSelect?.(id)
  }

  const onPointerMove = (event: PointerEvent) => {
    if (down) {
      return
    }

    const id = pick(event)

    if (id !== hovered) {
      hovered = id
      renderer.domElement.style.cursor = id ? 'pointer' : 'grab'
      options.onHover?.(id)
    }
  }

  renderer.domElement.style.cursor = 'grab'

  if (!thumb) {
    renderer.domElement.addEventListener('pointerdown', onPointerDown)
    renderer.domElement.addEventListener('pointerup', onPointerUp)
    renderer.domElement.addEventListener('pointermove', onPointerMove)
  }

  function setSelected(id: null | string) {
    selected = id
  }

  // ── resize + loop ─────────────────────────────────────────────────────────
  const resize = () => {
    const width = Math.max(1, container.clientWidth)
    const height = Math.max(1, container.clientHeight)
    renderer.setSize(width, height, false)
    renderer.domElement.style.width = `${width}px`
    renderer.domElement.style.height = `${height}px`
    camera.aspect = width / height
    camera.updateProjectionMatrix()

    if (!userMoved) {
      frameCamera()
    }
  }

  const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(resize)
  observer?.observe(container)
  resize()

  const clock = new THREE.Clock()
  const projected = new THREE.Vector3()
  let frame = 0
  let disposed = false
  let paused = false
  let lastFrame = 0
  let lastT = 0

  function animate(now = performance.now()) {
    if (disposed || paused) {
      return
    }

    frame = requestAnimationFrame(animate)

    if (document.hidden) {
      return
    }

    if (frameGap && now - lastFrame < frameGap) {
      return
    }

    lastFrame = now

    const t = clock.getElapsedTime()
    // Clamped so a long pause (hidden tab, offscreen mini) never teleports a walker.
    const dt = Math.min(0.1, Math.max(0, t - lastT))
    lastT = t
    controls.update()

    for (const figure of figures.values()) {
      updateStroll(figure, t, dt)
      animateFigure(figure, t)
    }

    // The sliding door opens while someone is passing through it.
    const walkers: { x: number; z: number }[] = []

    for (const f of figures.values()) {
      if (f.stroll) {
        walkers.push({ x: f.agent.x + f.body.position.x, z: f.agent.z + f.body.position.z })
      }
    }

    doorOpen = stepDoor(doorOpen, doorTarget(walkers, roomSize), dt)

    if (doorPanel) {
      const door = gardenLayout(roomSize).door
      doorPanel.position.z = door.z + smooth(doorOpen) * (door.width - 0.04)
    }

    // Koi circle the pond.
    if (koi.length) {
      const pond = gardenLayout(roomSize).pond
      koi.forEach(fish => {
        const a = t * 0.35 * motion + (fish.userData.offset as number)
        fish.position.x = pond.x + Math.cos(a) * pond.rx * 0.55
        fish.position.z = pond.z + Math.sin(a) * pond.rz * 0.55
        fish.rotation.y = -a + Math.PI
      })
    }

    lanterns.forEach((lantern, i) => {
      lantern.rotation.z = Math.sin(t * 0.6 + i) * 0.03 * motion
    })
    lanternLights.forEach((light, i) => {
      light.intensity = 5 + Math.sin(t * 2.1 + i * 1.7) * 0.25 * motion
    })

    renderer.render(scene, camera)
    placeLabels()
  }

  function animateFigure(f: Figure, t: number) {
    const p = t + f.phase
    const ringMat = f.ring.material
    const isSelected = selected === f.agent.id
    f.ring.scale.setScalar(isSelected ? 1 : 0.85)
    f.armL.rotation.set(0, 0, 0)
    f.armR.rotation.set(0, 0, 0)
    f.head.rotation.set(0, 0, 0)
    f.torso.rotation.set(0, 0, 0)
    f.torso.scale.y = 1

    switch (f.agent.status) {
      case 'working': {
        // Arms forward on the keyboard, quick alternating taps, slight nod.
        f.armL.rotation.x = -1.05 + Math.sin(p * 14) * 0.08 * motion
        f.armR.rotation.x = -1.05 + Math.sin(p * 14 + Math.PI) * 0.08 * motion
        f.head.rotation.x = 0.18 + Math.sin(p * 2.2) * 0.05 * motion
        f.torso.rotation.x = 0.1
        ringMat.opacity = 0.85
        f.lidLight.emissiveIntensity = 1.2 + Math.sin(p * 9) * 0.3 * motion

        break
      }

      case 'waiting': {
        // Right hand raised, gently waving; ring pulses amber.
        f.armR.rotation.z = 2.5 + Math.sin(p * 3) * 0.2 * motion
        f.armL.rotation.x = -0.4
        f.head.rotation.y = Math.sin(p * 0.8) * 0.25 * motion
        ringMat.opacity = 0.45 + (Math.sin(p * 4) * 0.5 + 0.5) * 0.5
        f.lidLight.emissiveIntensity = 1.4

        break
      }

      case 'error': {
        // Head down, hands on knees; ring blinks red.
        f.head.rotation.x = 0.55
        f.torso.rotation.x = 0.22
        f.armL.rotation.x = -0.5
        f.armR.rotation.x = -0.5
        ringMat.opacity = Math.sin(t * 6) > 0 ? 0.95 : 0.25 + 0.7 * (1 - motion)
        f.lidLight.emissiveIntensity = ringMat.opacity * 1.6

        break
      }

      default: {
        // Idle: leaning back, slow breathing, looking around now and then.
        f.torso.rotation.x = -0.12
        f.torso.scale.y = 1 + Math.sin(p * 1.3) * 0.015 * motion
        f.head.rotation.y = Math.sin(p * 0.35) * 0.45 * motion
        f.armL.rotation.set(0.35, 0, 0.18)
        f.armR.rotation.set(0.35, 0, -0.18)
        ringMat.opacity = 0.45
        f.lidLight.emissiveIntensity = 0.5
      }
    }

    if (isSelected) {
      ringMat.opacity = Math.max(ringMat.opacity, 0.95)
    }

    poseStanding(f, p)
  }

  // ── strolls ───────────────────────────────────────────────────────────────
  function startStroll(f: Figure) {
    const kind = strollKindFor(f.agent.status, Math.random())

    if (!kind) {
      return
    }

    const desks = [...figures.values()].map(other => other.agent)
    const plan = strollPlan(f.agent, desks, roomSize, kind, Math.random())
    const [min, max] = strollPauseRange(plan.kind)
    f.stroll = newStroll(plan, rand(min, max))
  }

  /** Advance the stroll state machine (stepStroll in the model) and the heading. */
  function updateStroll(f: Figure, t: number, dt: number) {
    const free = !options.reducedMotion && (f.agent.status === 'idle' || f.agent.status === 'waiting')

    if (!f.stroll) {
      if (!free) {
        f.nextStroll = Math.max(f.nextStroll, t + STROLL.firstMin)
      } else if (t >= f.nextStroll) {
        startStroll(f)
      }

      if (!f.stroll) {
        f.perch = 0

        return
      }
    }

    const st = f.stroll
    const step = stepStroll(st, dt, free)
    const moved = step.moved
    f.stand = step.stand

    if (step.done) {
      f.stroll = null
      f.nextStroll = t + rand(STROLL.gapMin, STROLL.gapMax)
    }

    // Sit down on the bench / get up again, eased over the stand-up time.
    const perch = perchTarget(f.stroll)
    f.perch = perch > f.perch ? Math.min(1, f.perch + dt / STROLL.standUp) : Math.max(0, f.perch - dt / (STROLL.standUp * 0.6))

    f.gait += (moved / STROLL.stride) * Math.PI * 2
    f.swing = lerp(f.swing, moved > 0 ? 1 : 0, Math.min(1, dt * 7))

    // Heading: along the path when walking, at the destination's focus when
    // paused, back to facing the desk when sitting down.
    let target = 0

    if (f.stroll) {
      const here = pointAlong(st.plan.points, st.s)

      if (st.phase === 'out' || (st.phase === 'stand' && st.length > 0)) {
        target = pointAlong(st.plan.points, Math.max(st.s, 0.01)).heading
      } else if (st.phase === 'back') {
        target = here.heading + Math.PI
      } else if (st.phase === 'pause') {
        target = Math.atan2(st.plan.face.x - here.x, st.plan.face.z - here.z)
      }
    }

    const h = turnToward(f.heading, target, Math.min(1, dt * 7))
    f.heading = Math.atan2(Math.sin(h), Math.cos(h))
  }

  /** Blend the seated pose (already set) toward standing / walking by `f.stand`. */
  function poseStanding(f: Figure, p: number) {
    const k = smooth(f.stand)
    const st = f.stroll

    if (!st && k === 0) {
      f.body.position.set(0, 0.12, STROLL.seatZ)
      f.body.rotation.y = 0
      f.seatLegs.visible = true
      f.legL.visible = false
      f.legR.visible = false

      return
    }

    const at = st ? pointAlong(st.plan.points, st.s) : { x: f.agent.x, z: f.agent.z + STROLL.seatZ }
    const swing = Math.sin(f.gait) * f.swing
    const bob = Math.abs(Math.sin(f.gait)) * 0.035 * f.swing
    // One step down into the garden (0 inside and on the engawa).
    const ground = groundHeight(at.x, roomSize)
    const perch = smooth(f.perch)
    const standingY = lerp(0.12, STROLL.standY, k) + bob + ground * k
    f.body.position.set(at.x - f.agent.x, lerp(standingY, ground + OFFICE3D_GARDEN.perchY, perch), at.z - f.agent.z)
    f.body.rotation.y = f.heading
    f.seatLegs.visible = false
    f.legL.visible = true
    f.legR.visible = true
    // Legs unfold from pointing forward (seated) to hanging (standing), then swing.
    f.legL.rotation.x = lerp(-Math.PI / 2, swing * STROLL.legSwing, k)
    f.legR.rotation.x = lerp(-Math.PI / 2, -swing * STROLL.legSwing, k)

    let armL = -swing * STROLL.armSwing
    let armR = swing * STROLL.armSwing
    let armRz = 0

    let headPitch = 0

    if (st?.phase === 'pause') {
      if (st.plan.kind === 'cooler' || st.plan.kind === 'tea') {
        // A cup of water (or tea): right hand up to the mouth now and then.
        armR = -1.9 + Math.max(0, Math.sin(p * 0.9)) * -0.5
      } else if (st.plan.kind === 'neighbour') {
        armR = -0.5 + Math.sin(p * 2.4) * 0.25
      } else if (st.plan.kind === 'pond') {
        // Hands behind the back, looking down at the koi.
        armL = 0.35
        armR = 0.35
        headPitch = 0.32
      }

      if (f.agent.status === 'waiting') {
        armRz = 2.5 + Math.sin(p * 3) * 0.2
        armR = 0
      }
    }

    f.armL.rotation.set(lerp(f.armL.rotation.x, armL, k), 0, lerp(f.armL.rotation.z, 0.06, k))
    f.armR.rotation.set(lerp(f.armR.rotation.x, armR, k), 0, lerp(f.armR.rotation.z, armRz || -0.06, k))
    f.torso.rotation.x = lerp(f.torso.rotation.x, 0.04 * f.swing, k)
    f.torso.scale.y = lerp(f.torso.scale.y, 1, k)
    f.head.rotation.x = lerp(f.head.rotation.x, headPitch, k)

    if (perch > 0) {
      // Seated on the bench: legs forward and down, hands on the knees,
      // leaning back a little and breathing.
      f.legL.rotation.x = lerp(f.legL.rotation.x, -1.0, perch)
      f.legR.rotation.x = lerp(f.legR.rotation.x, -1.0, perch)
      f.armL.rotation.x = lerp(f.armL.rotation.x, -0.75, perch)
      f.armR.rotation.x = lerp(f.armR.rotation.x, -0.75, perch)
      f.torso.rotation.x = lerp(f.torso.rotation.x, -0.08, perch)
      f.torso.scale.y = lerp(f.torso.scale.y, 1 + Math.sin(p * 1.3) * 0.015, perch)
      f.head.rotation.y = lerp(f.head.rotation.y, Math.sin(p * 0.3) * 0.35, perch)
    }
  }

  function placeLabels() {
    if (!labelLayer) {
      return
    }

    const width = container.clientWidth
    const height = container.clientHeight

    for (const el of labelLayer.querySelectorAll<HTMLElement>('[data-agent-label]')) {
      const figure = figures.get(el.dataset.agentLabel ?? '')

      if (!figure) {
        el.style.visibility = 'hidden'

        continue
      }

      // Follows the figure on a stroll (standing adds ~0.22 m).
      projected
        .set(
          figure.agent.x + figure.body.position.x,
          LABEL_HEIGHT +
            smooth(figure.stand) * (STROLL.standY - 0.12 + groundHeight(figure.agent.x + figure.body.position.x, roomSize)) -
            smooth(figure.perch) * (STROLL.standY - OFFICE3D_GARDEN.perchY),
          figure.agent.z + figure.body.position.z + 0.02
        )
        .project(camera)
      const visible = projected.z < 1 && Math.abs(projected.x) < 1.1 && Math.abs(projected.y) < 1.1
      el.style.visibility = visible ? 'visible' : 'hidden'
      el.style.transform = `translate(-50%, -100%) translate(${((projected.x + 1) / 2) * width}px, ${((1 - projected.y) / 2) * height}px)`
      // Nearer labels on top.
      el.style.zIndex = String(1000 - Math.round(projected.z * 1000))
    }
  }

  buildRoom(12, 9)
  cameraReady = true
  resetCamera()
  animate()

  return {
    dispose() {
      disposed = true
      cancelAnimationFrame(frame)
      observer?.disconnect()
      controls.removeEventListener('change', clampTarget)
      controls.removeEventListener('start', onControlStart)
      controls.dispose()
      renderer.domElement.removeEventListener('pointerdown', onPointerDown)
      renderer.domElement.removeEventListener('pointerup', onPointerUp)
      renderer.domElement.removeEventListener('pointermove', onPointerMove)
      room.clear()
      scene.clear()
      disposables.forEach(item => item.dispose())
      renderer.dispose()
      renderer.forceContextLoss()
      renderer.domElement.remove()
    },
    resetCamera,
    setAgents,
    setPaused(next: boolean) {
      if (next === paused || disposed) {
        return
      }

      paused = next
      cancelAnimationFrame(frame)

      if (!paused) {
        animate()
      }
    },
    setSelected
  }
}

/** Straw weave for the tatami: fine lines along the mat, drawn once. */
function makeTatamiTexture(): THREE.CanvasTexture {
  const canvas = document.createElement('canvas')
  canvas.width = 128
  canvas.height = 64
  const ctx = canvas.getContext('2d')

  if (ctx) {
    ctx.fillStyle = P.tatami
    ctx.fillRect(0, 0, 128, 64)

    for (let y = 0; y < 64; y += 3) {
      ctx.fillStyle = y % 6 ? P.tatamiWeave : '#bfae7d'
      ctx.globalAlpha = 0.55
      ctx.fillRect(0, y, 128, 1)
    }

    ctx.globalAlpha = 1
  }

  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.wrapS = THREE.RepeatWrapping
  texture.wrapT = THREE.RepeatWrapping

  return texture
}

/** Raked gravel: pale grit with straight rake lines, drawn once (2 × 2 m per tile). */
function makeGravelTexture(): THREE.CanvasTexture {
  const canvas = document.createElement('canvas')
  canvas.width = 128
  canvas.height = 128
  const ctx = canvas.getContext('2d')

  if (ctx) {
    ctx.fillStyle = P.gravel
    ctx.fillRect(0, 0, 128, 128)

    // Grit: a fixed speckle (deterministic, so every build looks the same).
    let seed = 7

    for (let i = 0; i < 900; i++) {
      seed = (seed * 16807) % 2147483647
      const x = seed % 128
      seed = (seed * 16807) % 2147483647
      const y = seed % 128
      ctx.fillStyle = i % 3 ? P.gravelRake : '#ddd5c4'
      ctx.globalAlpha = 0.5
      ctx.fillRect(x, y, 1, 1)
    }

    // Rake lines along the garden's length: thin, soft grooves.
    ctx.globalAlpha = 0.35
    ctx.fillStyle = P.gravelRake

    for (let y = 3; y < 128; y += 8) {
      ctx.fillRect(0, y, 128, 1)
    }

    ctx.globalAlpha = 1
  }

  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.wrapS = THREE.RepeatWrapping
  texture.wrapT = THREE.RepeatWrapping

  return texture
}

/** Hanging scroll: cream paper, one brush-like red ensō. */
function makeEnsoTexture(): THREE.CanvasTexture {
  const canvas = document.createElement('canvas')
  canvas.width = 128
  canvas.height = 240
  const ctx = canvas.getContext('2d')

  if (ctx) {
    ctx.fillStyle = P.scroll
    ctx.fillRect(0, 0, 128, 240)
    ctx.strokeStyle = P.enso
    ctx.lineCap = 'round'

    // A ring of overlapping strokes, thicker at the start, open at the end.
    for (let i = 0; i < 40; i++) {
      const a0 = -1.2 + i * 0.13
      ctx.lineWidth = 11 - i * 0.2
      ctx.globalAlpha = 0.85
      ctx.beginPath()
      ctx.arc(64, 100, 36, a0, a0 + 0.16)
      ctx.stroke()
    }

    ctx.globalAlpha = 1
  }

  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace

  return texture
}

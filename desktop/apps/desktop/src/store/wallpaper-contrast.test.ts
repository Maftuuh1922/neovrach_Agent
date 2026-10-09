// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'

import { backdropOf, contrast, minimumKeep, over, type Rgb, viewportRectToImage } from '@/lib/wallpaper-contrast'

import { computeFloors, computeShadows, type FloorInput } from './wallpaper-contrast'

const DARK = {
  ink: [13, 6, 6] as Rgb,
  ink2: [18, 9, 9] as Rgb,
  text: [244, 242, 237] as Rgb,
  text2: [185, 178, 172] as Rgb,
  accent: [238, 28, 28] as Rgb,
  chrome: [13, 6, 6] as Rgb
}
const LIGHT = {
  ink: [244, 242, 237] as Rgb,
  ink2: [235, 232, 225] as Rgb,
  text: [18, 13, 13] as Rgb,
  text2: [74, 66, 64] as Rgb,
  accent: [238, 28, 28] as Rgb,
  chrome: [244, 242, 237] as Rgb
}

const solid = (rgb: Rgb, w = 16, h = 10) => {
  const data = new Uint8ClampedArray(w * h * 4)

  for (let i = 0; i < w * h; i++) {
    data.set([...rgb, 255], i * 4)
  }

  return { data, width: w, height: h }
}

const input = (over_: Partial<FloorInput>): FloorInput => ({
  sample: solid([255, 255, 255]),
  rects: {
    frame: [{ left: 0, top: 0, right: 1280, bottom: 40 }],
    stage: [{ left: 60, top: 40, right: 1000, bottom: 800 }],
    sessions: [],
    context: [{ left: 1010, top: 40, right: 1280, bottom: 300 }]
  },
  viewport: { width: 1280, height: 800 },
  settings: { autoAccent: true, blur: 6, dim: 0, tint: 0 },
  style: 'bening',
  scheme: 'dark',
  colors: DARK,
  ...over_
})

/** Re-derive the final stage colour the CSS paints at the floor and check it. */
function stageContrast(i: FloorInput, floors: Record<string, number>, w: Rgb) {
  const b = backdropOf(w, { surface: i.colors.ink, chrome: i.colors.chrome, accent: i.colors.accent, text: i.colors.text2 }, {
    dim: i.settings.dim,
    tint: i.settings.tint,
    fillTint: 0.05
  })
  const frame = over(i.colors.ink, floors['--nv-floor-frame'] / 100, b)
  const fill = over(i.colors.accent, 0.05, i.colors.ink)

  return contrast(over(fill, floors['--nv-floor-stage'] / 100, frame), i.colors.text2)
}

describe('text contrast over the wallpaper', () => {
  it('a white wallpaper in dark mode forces dense glass that still reads at >= 4.5:1', () => {
    const i = input({})
    const floors = computeFloors(i)

    expect(floors['--nv-floor-frame']).toBeGreaterThan(50)
    expect(stageContrast(i, floors, [255, 255, 255])).toBeGreaterThanOrEqual(4.5)
  })

  it('a black wallpaper in dark mode lets the glass stay clear', () => {
    const floors = computeFloors(input({ sample: solid([0, 0, 0]) }))

    expect(floors['--nv-floor-frame']).toBe(0)
    expect(floors['--nv-floor-stage']).toBe(0)
  })

  it('a black wallpaper in light mode needs dense light glass for dark text', () => {
    const i = input({ sample: solid([0, 0, 0]), colors: LIGHT, scheme: 'light' })
    const floors = computeFloors(i)

    expect(floors['--nv-floor-frame']).toBeGreaterThan(50)
    expect(stageContrast(i, floors, [0, 0, 0])).toBeGreaterThanOrEqual(4.5)
  })

  it('the dim slider already covers part of the work', () => {
    const plain = computeFloors(input({}))
    const dimmed = computeFloors(input({ settings: { autoAccent: true, blur: 6, dim: 0.6, tint: 0 } }))

    expect(dimmed['--nv-floor-frame']).toBeLessThan(plain['--nv-floor-frame'])
  })

  it('measures only the wallpaper under each panel', () => {
    // Left half white, right half black.
    const w = 16
    const h = 10
    const data = new Uint8ClampedArray(w * h * 4)

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        data.set(x < w / 2 ? [255, 255, 255, 255] : [0, 0, 0, 255], (y * w + x) * 4)
      }
    }

    const floors = computeFloors(
      input({
        sample: { data, width: w, height: h },
        rects: {
          frame: [{ left: 1100, top: 0, right: 1280, bottom: 40 }],
          stage: [{ left: 0, top: 100, right: 400, bottom: 700 }],
          sessions: [],
          context: [{ left: 1000, top: 100, right: 1280, bottom: 700 }]
        },
        viewport: { width: 1280, height: 800 },
        settings: { autoAccent: true, blur: 0, dim: 0, tint: 0 }
      })
    )

    expect(floors['--nv-floor-context']).toBe(0)
    expect(floors['--nv-floor-stage']).toBeGreaterThan(50)
  })

  it('Tanpa efek makes every panel solid (the frame ground keeps its own floor)', () => {
    const floors = computeFloors(input({ style: 'tanpa' }))

    for (const k of ['--nv-floor-stage', '--nv-floor-sessions', '--nv-floor-context', '--nv-floor-bubble']) expect(floors[k]).toBe(100)
    expect(floors['--nv-floor-frame']).toBe(computeFloors(input({}))['--nv-floor-frame'])
  })

  it('adaptive shadow: deeper in dark mode, coloured by the wallpaper (spec §2.1)', () => {
    const shadows = computeShadows(input({ sample: solid([200, 40, 40]) }))
    expect(shadows['--nv-shadow-stage']).toMatch(/^rgb\(50 10 10 \/ 0\.(2\d|3[0-5])\)$/)
    const light = computeShadows(input({ sample: solid([255, 255, 255]), scheme: 'light' }))
    expect(light['--nv-shadow-stage']).toBe('rgb(64 64 64 / 0.10)')
  })

  it('helpers: contrast, minimumKeep, cover mapping', () => {
    expect(contrast([0, 0, 0], [255, 255, 255])).toBeCloseTo(21, 0)
    const k = minimumKeep([13, 6, 6], [185, 178, 172], [[255, 255, 255]])
    expect(contrast(over([13, 6, 6], k, [255, 255, 255]), [185, 178, 172])).toBeGreaterThanOrEqual(4.5)
    expect(contrast(over([13, 6, 6], k - 0.01, [255, 255, 255]), [185, 178, 172])).toBeLessThan(4.5)

    const r = viewportRectToImage({ left: 0, top: 0, right: 100, bottom: 100 }, { width: 100, height: 100 }, { width: 10, height: 10 }, 0)
    expect(r).toEqual({ x0: 0, y0: 0, x1: 10, y1: 10 })
  })
})

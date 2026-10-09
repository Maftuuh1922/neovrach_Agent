// @vitest-environment jsdom
import { atom } from 'nanostores'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const appearance = vi.hoisted(() => ({
  state: null as unknown as { get: () => { accent: string; base: 'dark' | 'light' } | null; set: (v: unknown) => void },
  saves: [] as { accent: string; base: string }[]
}))

vi.mock('@/components/neovarch/appearance', () => {
  const $nvAppearance = atom<{ accent: string; base: 'dark' | 'light' } | null>({ accent: '#EE1C1C', base: 'dark' })
  appearance.state = $nvAppearance as never

  return {
    $nvAppearance,
    DEFAULT_ACCENT: '#EE1C1C',
    applyAccent: vi.fn(),
    saveAppearance: vi.fn(async (next: { accent: string; base: 'dark' | 'light' }) => {
      appearance.saves.push(next)
      $nvAppearance.set(next)

      return next
    })
  }
})

const BLUE = { seed: '#2D5BE6', swatches: ['#2D5BE6', '#1B3FA8', '#7FA0FF'], monochrome: false }

async function load() {
  vi.resetModules()
  appearance.saves = []
  const wallpaper = await import('./wallpaper')
  const accent = await import('./wallpaper-accent')
  accent.paletteSource.compute = vi.fn(async () => BLUE)
  appearance.state.set({ accent: '#EE1C1C', base: 'dark' })
  appearance.saves = []

  return { ...wallpaper, ...accent }
}

beforeEach(() => window.localStorage.clear())

describe('Warna dari wallpaper', () => {
  it('takes the accent from the wallpaper, and gives the old one back when it is removed', async () => {
    const w = await load()
    w.setWallpaperSource('preset:remote')

    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#2D5BE6'))
    expect(w.$wallpaperPalette.get()).toEqual(BLUE)
    expect(w.$wallpaper.get()).toMatchObject({ autoAccent: true, restoreAccent: '#EE1C1C' })
    expect(JSON.parse(window.localStorage.getItem(w.WALLPAPER_KEY)!)).toMatchObject({
      autoAccent: true,
      restoreAccent: '#EE1C1C'
    })

    w.setWallpaperSource('')
    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#EE1C1C'))
    expect(w.$wallpaper.get().restoreAccent).toBe('')
  })

  it('a manual accent turns the toggle off and is kept', async () => {
    const w = await load()
    w.setWallpaperSource('preset:portal')
    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#2D5BE6'))

    await w.pickWallpaperSwatch('#7FA0FF')
    expect(w.$wallpaper.get()).toMatchObject({ autoAccent: false, restoreAccent: '' })
    expect(appearance.state.get()?.accent).toBe('#7FA0FF')

    // Leaving the wallpaper now does not bring the old accent back.
    w.setWallpaperSource('')
    await new Promise(r => setTimeout(r, 0))
    expect(appearance.state.get()?.accent).toBe('#7FA0FF')
  })

  it('switching the toggle off restores the previous accent; on again re-applies', async () => {
    const w = await load()
    w.setWallpaperSource('preset:automation')
    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#2D5BE6'))

    w.setWallpaperAutoAccent(false)
    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#EE1C1C'))

    w.setWallpaperAutoAccent(true)
    await vi.waitFor(() => expect(appearance.state.get()?.accent).toBe('#2D5BE6'))
  })

  it('stays off when the user turned it off before choosing a wallpaper', async () => {
    const w = await load()
    w.setWallpaper({ autoAccent: false })
    w.setWallpaperSource('preset:remote')
    await vi.waitFor(() => expect(w.$wallpaperPalette.get()).toEqual(BLUE))

    expect(appearance.saves).toEqual([])
    expect(appearance.state.get()?.accent).toBe('#EE1C1C')
  })
})

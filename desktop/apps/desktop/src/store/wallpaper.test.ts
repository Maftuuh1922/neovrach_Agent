// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const KEY = 'neovarch.desktop.wallpaper.v1'

async function load() {
  vi.resetModules()

  return import('./wallpaper')
}

beforeEach(() => {
  window.localStorage.clear()
  document.documentElement.removeAttribute('data-nv-wallpaper')
  document.documentElement.removeAttribute('style')
  delete window.neovarchWallpaper
})

afterEach(() => {
  delete window.neovarchWallpaper
})

describe('wallpaper settings persistence', () => {
  it('starts flat with the phone defaults and writes nothing', async () => {
    const w = await load()

    expect(w.$wallpaper.get()).toEqual(w.DEFAULT_WALLPAPER)
    expect(w.DEFAULT_WALLPAPER).toEqual({
      source: '',
      blur: 6,
      dim: 0.4,
      tint: 0.15,
      saturation: 1,
      glass: 22,
      autoAccent: true,
      restoreAccent: ''
    })
    expect(window.localStorage.getItem(KEY)).toBeNull()
    expect(document.documentElement.hasAttribute('data-nv-wallpaper')).toBe(false)
  })

  it('persists a preset and the sliders, and restores them on the next launch', async () => {
    let w = await load()
    w.setWallpaperSource('preset:portal')
    w.setWallpaper({ blur: 12, dim: 0.55, tint: 0.3, saturation: 1.4, glass: 30 })

    expect(JSON.parse(window.localStorage.getItem(KEY)!)).toMatchObject({
      source: 'preset:portal',
      blur: 12,
      dim: 0.55,
      tint: 0.3,
      saturation: 1.4,
      glass: 30
    })

    w = await load()
    expect(w.$wallpaper.get()).toMatchObject({
      source: 'preset:portal',
      blur: 12,
      dim: 0.55,
      tint: 0.3,
      saturation: 1.4,
      glass: 30
    })
  })

  it('clamps out-of-range values and drops unknown sources from storage', async () => {
    window.localStorage.setItem(
      KEY,
      JSON.stringify({ source: 'file:../../etc/passwd', blur: 99, dim: -1, tint: 'x', saturation: 5, glass: 41 })
    )
    const w = await load()

    expect(w.$wallpaper.get()).toEqual({
      source: '',
      blur: 30,
      dim: 0,
      tint: 0.15,
      saturation: 2,
      glass: 40,
      autoAccent: true,
      restoreAccent: ''
    })
  })

  it('Reset returns to the defaults, clears storage and the copied file', async () => {
    const clear = vi.fn(async () => true)
    window.neovarchWallpaper = {
      clear,
      importBytes: vi.fn(),
      importFile: vi.fn(),
      pathForFile: vi.fn(),
      pick: vi.fn(),
      read: vi.fn(async () => null)
    }
    const w = await load()
    w.setWallpaperSource('preset:remote')
    w.setWallpaper({ blur: 20 })
    w.resetWallpaper()

    expect(w.$wallpaper.get()).toEqual(w.DEFAULT_WALLPAPER)
    expect(window.localStorage.getItem(KEY)).toBeNull()
    expect(clear).toHaveBeenCalledOnce()
  })

  it('imports a picked file through the bridge and keeps only its bare name', async () => {
    const read = vi.fn(async () => ({ dataUrl: 'data:image/png;base64,AAAA', mime: 'image/png' }))
    window.neovarchWallpaper = {
      clear: vi.fn(async () => true),
      importBytes: vi.fn(),
      importFile: vi.fn(),
      pathForFile: vi.fn(),
      pick: vi.fn(async () => ({ ok: true, name: 'wallpaper-0123456789abcdef.png' })),
      read
    }
    const w = await load()

    await expect(w.pickWallpaperFile()).resolves.toBe(true)
    expect(w.$wallpaper.get().source).toBe('file:wallpaper-0123456789abcdef.png')
    await vi.waitFor(() => expect(w.$wallpaperUrl.get()).toBe('data:image/png;base64,AAAA'))
    expect(read).toHaveBeenCalledWith('wallpaper-0123456789abcdef.png')
    expect(document.documentElement.hasAttribute('data-nv-wallpaper')).toBe(true)
  })

  it('reports an import error without changing the wallpaper', async () => {
    window.neovarchWallpaper = {
      clear: vi.fn(async () => true),
      importBytes: vi.fn(),
      importFile: vi.fn(),
      pathForFile: vi.fn(),
      pick: vi.fn(async () => ({ ok: false, error: 'Format tidak didukung.' })),
      read: vi.fn(async () => null)
    }
    const w = await load()

    await expect(w.pickWallpaperFile()).resolves.toBe(false)
    expect(w.$wallpaper.get().source).toBe('')
    expect(w.$wallpaperError.get()).toBe('Format tidak didukung.')
  })
})

describe('glass panels', () => {
  it('stronger glass thins the panels', async () => {
    const { wallpaperPanelKeep } = await load()

    expect(wallpaperPanelKeep({ glass: 0 })).toBe(94)
    expect(wallpaperPanelKeep({ glass: 22 })).toBeLessThan(wallpaperPanelKeep({ glass: 10 }))
    expect(wallpaperPanelKeep({ glass: 40 })).toBe(46)
  })

  it('paints root variables only while a wallpaper is shown', async () => {
    const w = await load()
    const root = document.documentElement
    w.setWallpaperSource('preset:automation')
    w.setWallpaper({ glass: 30, blur: 10 })

    expect(root.hasAttribute('data-nv-wallpaper')).toBe(true)
    expect(root.style.getPropertyValue('--nv-wall-glass')).toBe('30px')
    expect(root.style.getPropertyValue('--nv-wall-blur')).toBe('10px')
    expect(root.style.getPropertyValue('--nv-wall-keep')).toBe(`${w.wallpaperPanelKeep({ glass: 30 })}%`)

    w.setWallpaperSource('')
    expect(root.hasAttribute('data-nv-wallpaper')).toBe(false)
    expect(root.style.getPropertyValue('--nv-wall-glass')).toBe('')
  })
})

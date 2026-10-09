// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { WallpaperSetting } from '@/app/settings/wallpaper-setting'
import { $wallpaper, $wallpaperError, DEFAULT_WALLPAPER, setWallpaper, setWallpaperSource, WALLPAPER_KEY } from '@/store/wallpaper'

import { NeovarchWallpaper } from './wallpaper'

beforeEach(() => {
  window.localStorage.clear()
  $wallpaperError.set(null)
  $wallpaper.set({ ...DEFAULT_WALLPAPER })
})

afterEach(() => {
  cleanup()
  $wallpaper.set({ ...DEFAULT_WALLPAPER })
})

describe('NeovarchWallpaper (background layer)', () => {
  it('renders nothing without a wallpaper, so the default look is unchanged', () => {
    const { container } = render(<NeovarchWallpaper />)

    expect(container.innerHTML).toBe('')
    expect(document.documentElement.hasAttribute('data-nv-wallpaper')).toBe(false)
  })

  it('renders one fixed layer with the chosen blur, saturation, tint and dim', () => {
    act(() => {
      setWallpaperSource('preset:portal')
      setWallpaper({ blur: 14, saturation: 1.6, tint: 0.25, dim: 0.5 })
    })
    const { container } = render(<NeovarchWallpaper />)
    const layers = container.querySelectorAll('[data-slot="nv-wallpaper"]')

    expect(layers).toHaveLength(1)
    const image = container.querySelector<HTMLElement>('[data-slot="nv-wallpaper-image"]')!
    expect(image.style.filter).toBe('blur(14px) saturate(1.6)')
    expect(image.style.backgroundImage).toContain('portal-banner')
    expect(container.querySelector<HTMLElement>('[data-slot="nv-wallpaper-tint"]')!.style.opacity).toBe('0.25')
    expect(container.querySelector<HTMLElement>('[data-slot="nv-wallpaper-dim"]')!.style.opacity).toBe('0.5')
    expect(document.documentElement.hasAttribute('data-nv-wallpaper')).toBe(true)
  })

  it('follows slider changes live and drops zeroed overlays', () => {
    act(() => setWallpaperSource('preset:remote'))
    const { container } = render(<NeovarchWallpaper />)

    act(() => setWallpaper({ blur: 0, saturation: 0, tint: 0, dim: 0 }))
    expect(container.querySelector<HTMLElement>('[data-slot="nv-wallpaper-image"]')!.style.filter).toBe(
      'blur(0px) saturate(0)'
    )
    expect(container.querySelector('[data-slot="nv-wallpaper-tint"]')).toBeNull()
    expect(container.querySelector('[data-slot="nv-wallpaper-dim"]')).toBeNull()
  })
})

describe('Settings ▸ Tampilan ▸ Latar belakang', () => {
  it('picks a preset, moves the sliders, persists, and resets', () => {
    render(<WallpaperSetting />)

    const blur = screen.getByRole('slider', { name: 'Blur' })
    expect((blur as HTMLInputElement).disabled).toBe(true)
    expect((screen.getByRole('slider', { name: 'Kekuatan kaca' }) as HTMLInputElement).disabled).toBe(false)

    fireEvent.click(screen.getByRole('button', { name: 'Otomasi' }))
    expect(screen.getByRole('button', { name: 'Otomasi' }).getAttribute('aria-pressed')).toBe('true')
    expect((blur as HTMLInputElement).disabled).toBe(false)

    fireEvent.change(blur, { target: { value: '18' } })
    fireEvent.change(screen.getByRole('slider', { name: 'Kegelapan' }), { target: { value: '0.6' } })
    fireEvent.change(screen.getByRole('slider', { name: 'Kekuatan kaca' }), { target: { value: '35' } })

    expect(JSON.parse(window.localStorage.getItem(WALLPAPER_KEY)!)).toMatchObject({
      source: 'preset:automation',
      blur: 18,
      dim: 0.6,
      glass: 35
    })

    fireEvent.click(screen.getByRole('button', { name: /Reset/ }))
    expect($wallpaper.get()).toEqual(DEFAULT_WALLPAPER)
    expect(window.localStorage.getItem(WALLPAPER_KEY)).toBeNull()
    expect(screen.getByRole('button', { name: 'Polos' }).getAttribute('aria-pressed')).toBe('true')
  })

  it('rejects a dropped non-image file with a message', async () => {
    render(<WallpaperSetting />)
    const section = screen.getByRole('region', { name: 'Latar belakang' })
    const file = new File(['hello'], 'notes.txt', { type: 'text/plain' })

    await act(async () => {
      fireEvent.drop(section, { dataTransfer: { files: [file], types: ['Files'] } })
    })

    expect((await screen.findByRole('alert')).textContent).toContain('Format tidak didukung')
    expect($wallpaper.get().source).toBe('')
  })
})

// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'

const listeners: ((e: { matches: boolean }) => void)[] = []

function mockMedia(matches: boolean) {
  listeners.length = 0
  window.matchMedia = vi.fn(() => ({
    matches,
    addEventListener: (_: string, cb: (e: { matches: boolean }) => void) => listeners.push(cb)
  })) as unknown as typeof window.matchMedia
}

async function load() {
  vi.resetModules()

  return import('./glass-style')
}

afterEach(() => {
  window.localStorage.clear()
  document.documentElement.removeAttribute('data-nv-glass-style')
})

describe('Gaya kaca', () => {
  it('uses the Android ids and defaults to reguler', async () => {
    mockMedia(false)
    const g = await load()

    expect(g.GLASS_STYLES).toEqual(['reguler', 'bening', 'gelap', 'warna', 'tanpa'])
    expect(g.$glassStyle.get()).toBe('reguler')
    expect(document.documentElement.getAttribute('data-nv-glass-style')).toBe('reguler')
    expect(window.localStorage.getItem(g.GLASS_STYLE_KEY)).toBeNull()
  })

  it('defaults to tanpa when the OS asks for reduced transparency / more contrast, and follows changes', async () => {
    mockMedia(true)
    const g = await load()

    expect(window.matchMedia).toHaveBeenCalledWith(g.REDUCED_TRANSPARENCY_QUERY)
    expect(g.$glassStyle.get()).toBe('tanpa')

    listeners.forEach(cb => cb({ matches: false }))
    expect(g.$glassStyle.get()).toBe('reguler')
  })

  it('persists an explicit choice, which beats the OS default', async () => {
    mockMedia(true)
    let g = await load()
    g.setGlassStyle('bening')

    expect(window.localStorage.getItem(g.GLASS_STYLE_KEY)).toBe('bening')
    expect(document.documentElement.getAttribute('data-nv-glass-style')).toBe('bening')

    g = await load()
    expect(g.$glassStyle.get()).toBe('bening')
  })

  it('ignores an unknown stored value', async () => {
    mockMedia(false)
    window.localStorage.setItem('neovarch.desktop.glass-style.v1', 'frosted')
    const g = await load()

    expect(g.$glassStyle.get()).toBe('reguler')
  })
})

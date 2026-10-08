import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { drawShareCard, mix, rgba, SHARE_SIZES, wrapLines } from './share-card'
import { ShareProfileDialog } from './share-dialog'
import type { SocialProfile } from './social-store'
import { techIconFor, TechLogo, TechStackChips } from './tech-logo'
import { TECH_ICONS } from './tech-icons.gen'

const profile: SocialProfile = {
  avatar_url: null,
  bio: 'Ngoding Flutter & Python tiap hari. Lagi bangun agen AI di PC sendiri.',
  heatmap: { active_days: 200, counts: Array.from({ length: 365 }, (_, i) => i % 5), days: 365, end: '2026-10-09', max: 4, start: '2025-10-10', streak: 3, total: 730 },
  html_url: 'https://github.com/aku',
  login: 'aku',
  name: 'Aku Dev',
  stack: { languages: [{ name: 'Python', share: 0.5 }, { name: 'C++', share: 0.3 }, { name: 'Brainfuck', share: 0.2 }], tools: [] },
  status: { coding: true, last_active_at: new Date().toISOString(), project: 'neovarch' }
}

/** A 2D context stand-in that records calls (jsdom has no canvas). */
function fakeContext() {
  const calls: string[] = []
  const gradient = { addColorStop: () => undefined }
  const ctx = new Proxy({} as Record<string, unknown>, {
    get(target, prop: string) {
      if (prop in target) {
        return target[prop]
      }

      if (prop === 'measureText') {
        return (s: string) => ({ width: s.length * 18 })
      }

      if (prop.startsWith('create')) {
        return () => gradient
      }

      return (...args: unknown[]) => {
        calls.push(`${prop}:${args.length}`)
      }
    },
    set(target, prop: string, value) {
      target[prop] = value

      return true
    }
  })

  return { calls, ctx }
}

describe('tech logos', () => {
  it('maps linguist names to bundled Simple Icons and falls back for unknown ones', () => {
    expect(Object.keys(TECH_ICONS).length).toBeGreaterThanOrEqual(40)
    expect(techIconFor('C++')?.slug).toBe('cplusplus')
    expect(techIconFor('Java')?.slug).toBe('openjdk')
    expect(techIconFor('Jupyter Notebook')?.slug).toBe('jupyter')
    expect(techIconFor('Next.js')?.slug).toBe('nextdotjs')
    expect(techIconFor('Brainfuck')).toBeUndefined()
    for (const s of ['python', 'typescript', 'javascript', 'dart', 'flutter', 'kotlin', 'go', 'rust', 'react', 'docker', 'electron', 'vite']) {
      expect(TECH_ICONS[s]?.path.length).toBeGreaterThan(10)
    }
  })

  it('renders logo chips with the name as tooltip', () => {
    const { container } = render(<TechStackChips items={profile.stack!.languages} />)
    expect(container.querySelector('[data-tech="python"] path')).toBeTruthy()
    expect(container.querySelector('[data-tech="cplusplus"]')).toBeTruthy()
    expect(container.querySelector('[data-tech="unknown"]')).toBeTruthy()
    expect(container.querySelector('li')?.getAttribute('title')).toBe('Python · 50%')
    render(<TechLogo brand name="Python" />)
    expect((document.querySelectorAll('[data-tech="python"]')[1] as SVGElement).style.color).toBe('rgb(55, 118, 171)')
    cleanup()
  })
})

describe('share card', () => {
  afterEach(() => {
    cleanup()
    vi.restoreAllMocks()
  })

  it('colour helpers and word wrap', () => {
    expect(rgba('#EE1C1C', 0.5)).toBe('rgba(238, 28, 28, 0.5)')
    expect(mix('#000000', '#ffffff', 0.5)).toBe('#808080')
    const lines = wrapLines('satu dua tiga empat lima enam tujuh delapan', 100, s => s.length * 10, 2)
    expect(lines).toHaveLength(2)
    expect(lines[1]!.endsWith('…')).toBe(true)
  })

  it('paints story 1080×1920 and square 1080×1080', () => {
    const { calls, ctx } = fakeContext()
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(ctx as never)
    const c = document.createElement('canvas')
    drawShareCard(c, profile, { format: 'story', theme: { accent: '#7C3AED', dark: true } })
    expect([c.width, c.height]).toEqual([1080, 1920])
    expect(calls.filter(x => x.startsWith('fillText')).length).toBeGreaterThan(8)
    drawShareCard(c, profile, { format: 'square', theme: { accent: '#0D9488', dark: false } })
    expect([c.width, c.height]).toEqual([SHARE_SIZES.square.width, SHARE_SIZES.square.height])
  })

  describe('dialog', () => {
    beforeEach(() => {
      const { ctx } = fakeContext()
      vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(ctx as never)
      HTMLCanvasElement.prototype.toBlob = function (cb: BlobCallback, type?: string) {
        cb(new Blob([`png ${this.width}x${this.height}`], { type: type ?? 'image/png' }))
      }
      window.matchMedia = vi.fn().mockReturnValue({ matches: true }) as never
    })

    it('exports a PNG download, copies the image and the gist link', async () => {
      const urls: Blob[] = []
      URL.createObjectURL = vi.fn((b: Blob) => (urls.push(b), 'blob:x')) as never
      URL.revokeObjectURL = vi.fn()
      const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => undefined)
      const write = vi.fn().mockResolvedValue(undefined)
      const writeText = vi.fn().mockResolvedValue(undefined)
      Object.assign(navigator, { clipboard: { write, writeText } })
      ;(window as unknown as { ClipboardItem: unknown }).ClipboardItem = class {
        constructor(public items: Record<string, Blob>) {}
      }
      const onClose = vi.fn()
      render(<ShareProfileDialog gistUrl="https://gist.github.com/aku/1" onClose={onClose} profile={profile} />)
      const canvas = screen.getByLabelText('Pratinjau kartu profil') as HTMLCanvasElement
      expect([canvas.width, canvas.height]).toEqual([1080, 1920])
      await act(async () => {
        fireEvent.click(screen.getByText('Simpan PNG'))
      })
      await waitFor(() => expect(click).toHaveBeenCalled())
      expect(urls[0]!.type).toBe('image/png')
      expect(await urls[0]!.text()).toBe('png 1080x1920')
      fireEvent.click(screen.getByText('Kotak 1:1'))
      expect([canvas.width, canvas.height]).toEqual([1080, 1080])
      await act(async () => {
        fireEvent.click(screen.getByText('Salin gambar'))
      })
      await waitFor(() => expect(write).toHaveBeenCalled())
      expect(await (write.mock.calls[0]![0][0].items['image/png'] as Blob).text()).toBe('png 1080x1080')
      await act(async () => {
        fireEvent.click(screen.getByText('Salin tautan Gist'))
      })
      expect(writeText).toHaveBeenCalledWith('https://gist.github.com/aku/1')
      fireEvent.click(screen.getByText('Batal'))
      expect(onClose).toHaveBeenCalled()
    })
  })
})

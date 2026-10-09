import { act, cleanup, render } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'

import { neovarchGreeting } from '@/components/neovarch/home'
import { I18nProvider, useI18n } from '@/i18n'
import type { I18nContextValue } from '@/i18n'

import { Intro } from './intro'
import stock from './intro-copy.jsonl?raw'

let i18n: I18nContextValue

function Controls() {
  i18n = useI18n()

  return null
}

function Fixture({ personality, seed = 0 }: { personality?: string; seed?: number }) {
  return (
    <I18nProvider configClient={null} initialLocale="en">
      <Controls />
      <Intro personality={personality} seed={seed} />
    </I18nProvider>
  )
}

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  vi.useRealTimers()
})

it('keeps every shipped locale aligned with the stock intro copy per personality', async () => {
  const entries = stock
    .trim()
    .split('\n')
    .map(line => JSON.parse(line) as { personality: string; body: string })

  render(<Fixture />)

  for (const locale of ['zh', 'zh-hant', 'ja', 'fr', 'de', 'es'] as const) {
    await act(() => i18n.setLocale(locale))

    for (const personality of new Set(entries.map(entry => entry.personality))) {
      expect(i18n.t.intro.stock[personality]).toHaveLength(
        entries.filter(entry => entry.personality === personality).length
      )
    }
  }
})

it('renders the minimal Neovarch start screen: only the time-of-day greeting, for any personality', () => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date(2026, 9, 9, 8, 0, 0))

  for (const personality of [undefined, 'none', 'My Custom Voice']) {
    const { container, unmount } = render(<Fixture personality={personality} seed={3} />)
    const intro = container.querySelector('[data-slot="aui_intro"]')!

    expect(intro).toBeTruthy()
    expect(intro.querySelector('h1')!.textContent).toBe(neovarchGreeting(new Date(2026, 9, 9, 8, 0, 0)))
    expect(intro.querySelector('h1')!.textContent).toBe('Selamat pagi.')
    // No intro body, cards or session index under the greeting.
    expect(intro.querySelectorAll('p')).toHaveLength(0)
    expect(intro.textContent).not.toContain('My Custom Voice')
    unmount()
  }
})

it('picks the greeting by hour', () => {
  expect(neovarchGreeting(new Date(2026, 0, 1, 6))).toBe('Selamat pagi.')
  expect(neovarchGreeting(new Date(2026, 0, 1, 12))).toBe('Selamat siang.')
  expect(neovarchGreeting(new Date(2026, 0, 1, 17))).toBe('Selamat sore.')
  expect(neovarchGreeting(new Date(2026, 0, 1, 21))).toBe('Selamat malam.')
})

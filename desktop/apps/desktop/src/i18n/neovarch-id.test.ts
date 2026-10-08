import { describe, expect, it } from 'vitest'

import { NEOVARCH_BASE } from './catalog'
import { en as enUpstream } from './en'
import { NEOVARCH_ID } from './neovarch-id'

type Tree = Record<string, unknown>

function leaves(tree: Tree, prefix = ''): [string, unknown][] {
  return Object.entries(tree).flatMap(([k, v]) =>
    v && typeof v === 'object' ? leaves(v as Tree, `${prefix}${k}.`) : [[`${prefix}${k}`, v] as [string, unknown]]
  )
}

function at(tree: Tree, path: string): unknown {
  return path.split('.').reduce<unknown>((o, k) => (o && typeof o === 'object' ? (o as Tree)[k] : undefined), tree)
}

describe('Neovarch Indonesian base catalog', () => {
  const overlay = leaves(NEOVARCH_ID as unknown as Tree)

  it('covers settings, assistant and onboarding', () => {
    for (const ns of ['settings', 'assistant', 'onboarding']) {
      const upstream = leaves(at(enUpstream as unknown as Tree, ns) as Tree).filter(([, v]) => typeof v === 'string')
      const translated = overlay.filter(([k]) => k.startsWith(`${ns}.`))
      expect(translated.length, ns).toBe(upstream.length)
    }
  })

  it('only translates keys that exist upstream, as strings', () => {
    for (const [key, value] of overlay) {
      expect(typeof at(enUpstream as unknown as Tree, key), key).toBe('string')
      expect(typeof value, key).toBe('string')
    }
  })

  it('is what the app shows', () => {
    const base = NEOVARCH_BASE as unknown as Tree
    expect(at(base, 'settings.nav.about')).toBe('Tentang')
    expect(at(base, 'assistant.thread.copy')).toBe('Salin')
    expect(at(base, 'onboarding.startChatting')).toBe('Mulai')
  })

  it('keeps every {placeholder}', () => {
    for (const [key, value] of overlay) {
      const want = String(at(enUpstream as unknown as Tree, key)).match(/\{\{?\w+\}?\}/g)?.sort() ?? []
      expect(String(value).match(/\{\{?\w+\}?\}/g)?.sort() ?? [], key).toEqual(want)
    }
  })

  it('mentions no other product', () => {
    for (const [key, value] of overlay) {
      expect(String(value), key).not.toMatch(/hermes|nous/i)
    }
  })
})

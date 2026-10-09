import { describe, expect, it } from 'vitest'

import { normalizeModelOptions } from './model-options'

describe('normalizeModelOptions', () => {
  it('turns a stub object into an empty catalog and drops junk rows/models', () => {
    expect(normalizeModelOptions({ items: [], ok: false, providers: { a: 1 } }).providers).toEqual([])
    const out = normalizeModelOptions({
      model: 'm',
      providers: [
        null,
        'x',
        { models: ['a', '', 'a', 3, null, 'b'], name: 'R', slug: 'custom:r' },
        { models: 'nope', slug: 'p2' },
        { slug: 'p3' }
      ]
    })

    expect(out.providers.map(p => p.slug)).toEqual(['custom:r', 'p2', 'p3'])
    expect(out.providers[0].models).toEqual(['a', 'b'])
    expect(out.providers[1].models).toEqual([])
    expect(out.providers[2].models).toBeUndefined()
    expect(out.model).toBe('m')
  })

  it('leaves an answer without a providers key alone', () => {
    expect(normalizeModelOptions({ model: 'm', provider: 'p' })).toEqual({ model: 'm', provider: 'p' })
    expect(normalizeModelOptions(undefined)).toEqual({})
  })
})

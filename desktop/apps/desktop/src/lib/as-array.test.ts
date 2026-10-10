import { describe, expect, it } from 'vitest'

import { asArray } from './as-array'

describe('asArray', () => {
  it('passes arrays through without null rows', () => {
    expect(asArray([1, null, 2])).toEqual([1, 2])
  })

  it('reads the named key, then the fallback keys, else []', () => {
    expect(asArray({ jobs: [1] }, 'jobs')).toEqual([1])
    expect(asArray({ ok: false, items: [], results: [] }, 'jobs')).toEqual([])
    expect(asArray({ results: ['a'] })).toEqual(['a'])
    expect(asArray(null)).toEqual([])
    expect(asArray('nope')).toEqual([])
    expect(asArray({ detail: 'Not Found' }, 'servers')).toEqual([])
  })
})

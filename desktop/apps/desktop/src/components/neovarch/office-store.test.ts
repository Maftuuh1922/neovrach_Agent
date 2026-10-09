import { describe, expect, it } from 'vitest'

import { normalizeOfficeSnapshot, officeWorkingCount } from './office-store'

describe('office snapshot normalization', () => {
  it('turns a partial or broken answer into arrays and recomputed counts', () => {
    const snap = normalizeOfficeSnapshot({ agents: { nope: true }, feed: null })

    expect(snap.agents).toEqual([])
    expect(snap.feed).toEqual([])
    expect(snap.counts.working).toBe(0)
    expect(normalizeOfficeSnapshot(null).agents).toEqual([])
  })

  it('drops nameless rows and counts working desks', () => {
    const snap = normalizeOfficeSnapshot({
      agents: [null, { id: 'session:a', name: 'Dimas', status: 'working' }, { id: 'session:b', status: 'idle' }],
      counts: { working: 0 }
    })

    expect(snap.agents).toHaveLength(2)
    expect(snap.counts.working).toBe(1)
    expect(snap.counts.idle).toBe(1)
  })

  it('counts a chat the renderer knows is mid-turn even when its desk lags', () => {
    const snap = normalizeOfficeSnapshot({ agents: [{ id: 'session:a', status: 'idle' }] })

    expect(officeWorkingCount(snap)).toBe(0)
    expect(officeWorkingCount(snap, ['a'])).toBe(1)
    expect(officeWorkingCount(null, ['a', null])).toBe(1)
  })
})

import { describe, expect, it } from 'vitest'

import { usableEntries } from './use-at-completions'

describe('@ completions: only usable rows', () => {
  it('drops nameless rows and non-array answers', () => {
    expect(usableEntries({ items: [] })).toEqual([])
    expect(usableEntries(null)).toEqual([])
    expect(
      usableEntries([{ text: '' }, { text: '@' }, null, { display: 'x' }, { text: '@file:a.ts', display: 'a.ts' }])
    ).toEqual([{ text: '@file:a.ts', display: 'a.ts' }])
  })
})

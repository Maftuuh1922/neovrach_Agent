import { describe, expect, it } from 'vitest'

import { brandText } from './brand-text'

describe('brandText', () => {
  it('rebrands upstream backend/gateway errors for display', () => {
    expect(brandText('Hermes backend did not become ready: timeout')).toBe('Neovarch backend did not become ready: timeout')
    expect(brandText('Could not connect to Hermes gateway')).toBe('Could not connect to Neovarch gateway')
    expect(brandText('Hermes Agent not installed yet')).toBe('Neovarch not installed yet')
    expect(brandText('Hermes-Backend')).toBe('Neovarch-Backend')
  })

  it('keeps third-party services, commands, paths and identifiers', () => {
    expect(brandText('Signed in to Hermes Cloud')).toBe('Signed in to Hermes Cloud')
    expect(brandText('run `hermes update` in ~/.hermes')).toBe('run `hermes update` in ~/.hermes')
    expect(brandText('HermesConfig restartHermes')).toBe('HermesConfig restartHermes')
  })

  it('passes non-strings and clean text through unchanged', () => {
    const clean = 'Backend siap'
    expect(brandText(clean)).toBe(clean)
    expect(brandText(null)).toBeNull()
    expect(brandText(undefined)).toBeUndefined()
  })
})

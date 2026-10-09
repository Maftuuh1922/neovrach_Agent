// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'

import { applyAccent, contrastRatio, ON_ACCENT_DARK, ON_ACCENT_LIGHT, onAccentColor } from './appearance'

describe('WCAG: text on accent fills', () => {
  it('computes the WCAG ratio', () => {
    expect(contrastRatio('#FFFFFF', '#000000')).toBeCloseTo(21, 0)
    expect(contrastRatio('#665E5A', '#F4F2ED')).toBeGreaterThanOrEqual(4.5)
    expect(contrastRatio('#665E5A', '#E1DDD4')).toBeGreaterThanOrEqual(4.5)
  })

  it('uses dark ink on orange and other light accents, white on deep ones', () => {
    expect(onAccentColor('#F28C28')).toBe(ON_ACCENT_DARK)
    expect(onAccentColor('#EA580C')).toBe(ON_ACCENT_DARK)
    expect(onAccentColor('#A3A3A3')).toBe(ON_ACCENT_DARK)
    expect(onAccentColor('#2563EB')).toBe(ON_ACCENT_LIGHT)
    expect(onAccentColor('#7C3AED')).toBe(ON_ACCENT_LIGHT)
    expect(onAccentColor('#EE1C1C')).toBe(ON_ACCENT_LIGHT)
    expect(contrastRatio(onAccentColor('#F28C28'), '#F28C28')).toBeGreaterThanOrEqual(4.5)
  })

  it('applyAccent publishes --nv-on-accent and clears it for the default red', () => {
    const root = document.documentElement

    applyAccent('#F28C28', 'light')
    expect(root.style.getPropertyValue('--nv-on-accent')).toBe(ON_ACCENT_DARK)
    applyAccent('#EE1C1C', 'light')
    expect(root.style.getPropertyValue('--nv-on-accent')).toBe('')
  })
})

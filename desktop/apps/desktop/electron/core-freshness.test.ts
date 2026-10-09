import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { describe, expect, it } from 'vitest'

import {
  readCoreUpdateAttempt,
  readInstalledCoreCommit,
  recordCoreUpdateAttempt,
  sameCommit,
  shouldUpdateCore
} from './core-freshness'

const BUILD = '4ca7c18e2f0b6d3a1c9e8f7a6b5c4d3e2f1a0b9c'
const OLD = 'e15a825aaaabbbbccccddddeeeeffff000011112'

describe('shouldUpdateCore', () => {
  it('updates a packaged app whose installed core is from another commit', () => {
    expect(shouldUpdateCore({ isPackaged: true, stampCommit: BUILD, installedCommit: OLD, attemptedCommit: null })).toBe(
      true
    )
  })

  it('updates when the installed core has no recorded commit (old installer)', () => {
    expect(shouldUpdateCore({ isPackaged: true, stampCommit: BUILD, installedCommit: null, attemptedCommit: null })).toBe(
      true
    )
  })

  it('leaves a core at the same commit alone (short or long sha)', () => {
    expect(
      shouldUpdateCore({ isPackaged: true, stampCommit: BUILD, installedCommit: BUILD.slice(0, 7), attemptedCommit: null })
    ).toBe(false)
  })

  it('tries only once per build', () => {
    expect(shouldUpdateCore({ isPackaged: true, stampCommit: BUILD, installedCommit: OLD, attemptedCommit: BUILD })).toBe(
      false
    )
  })

  it('never updates dev builds, fallback stamps or an opted-out core', () => {
    expect(shouldUpdateCore({ isPackaged: false, stampCommit: BUILD, installedCommit: OLD, attemptedCommit: null })).toBe(
      false
    )
    expect(
      shouldUpdateCore({ isPackaged: true, stampCommit: '0000000000', installedCommit: OLD, attemptedCommit: null })
    ).toBe(false)
    expect(
      shouldUpdateCore({ isPackaged: true, stampCommit: BUILD, installedCommit: OLD, attemptedCommit: null, optOut: true })
    ).toBe(false)
  })

  it('compares commits by prefix', () => {
    expect(sameCommit(BUILD, BUILD.slice(0, 12))).toBe(true)
    expect(sameCommit(BUILD, OLD)).toBe(false)
    expect(sameCommit(null, BUILD)).toBe(false)
  })
})

describe('core commit files', () => {
  it('reads the installer commit and records an attempt', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nv-core-'))
    fs.writeFileSync(path.join(dir, '.neovarch-source-commit'), `${OLD}\n`)
    expect(readInstalledCoreCommit(dir)).toBe(OLD)
    expect(readCoreUpdateAttempt(dir)).toBeNull()
    recordCoreUpdateAttempt(dir, BUILD)
    expect(readCoreUpdateAttempt(dir)).toBe(BUILD)
    fs.rmSync(dir, { recursive: true, force: true })
  })
})

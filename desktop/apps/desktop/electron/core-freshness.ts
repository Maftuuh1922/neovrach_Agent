// Keeps the installed Neovarch core in step with the desktop app.
//
// The first-launch bootstrap installs the core into ~/.neovarch/neovarch-agent
// at the commit this app was built from, and records it in
// `.neovarch-source-commit`. Once that core is usable it used to be launched
// forever: updating the desktop app left an old core behind, so every route the
// newer desktop needs answered 404 ("Not implemented in the Neovarch core") or
// left Settings pages on an endless skeleton. A packaged app whose build commit
// differs from the installed core's commit now re-runs the installer once to
// bring the core to its own commit.

import fs from 'node:fs'
import path from 'node:path'

const SHA_RE = /^[0-9a-f]{7,40}$/i
const FALLBACK_RE = /^0{7,40}$/

export const CORE_SOURCE_COMMIT_FILE = '.neovarch-source-commit'
export const CORE_UPDATE_ATTEMPT_FILE = '.neovarch-core-update-attempt'

export interface CoreFreshnessInput {
  /** Packaged app (dev builds run the core from the checkout). */
  isPackaged: boolean
  /** Commit baked into this app's install stamp. */
  stampCommit: null | string | undefined
  /** Commit recorded by the installer next to the installed core. */
  installedCommit: null | string | undefined
  /** Stamp commit an update was already attempted for (one try per build). */
  attemptedCommit: null | string | undefined
  /** NEOVARCH_DESKTOP_KEEP_CORE=1 opts out (a hand-managed core). */
  optOut?: boolean
}

function realSha(value: null | string | undefined): string | null {
  const sha = (value ?? '').trim().toLowerCase()

  return SHA_RE.test(sha) && !FALLBACK_RE.test(sha) ? sha : null
}

/** Two commits name the same revision when one is a prefix of the other. */
export function sameCommit(a: null | string | undefined, b: null | string | undefined): boolean {
  const x = realSha(a)
  const y = realSha(b)

  if (!x || !y) {
    return false
  }

  return x.startsWith(y) || y.startsWith(x)
}

/** Should this launch re-run the installer to update the core? */
export function shouldUpdateCore(input: CoreFreshnessInput): boolean {
  if (!input.isPackaged || input.optOut) {
    return false
  }

  const stamp = realSha(input.stampCommit)

  if (!stamp) {
    return false
  }

  if (sameCommit(stamp, input.installedCommit)) {
    return false
  }

  // One attempt per build: an offline launch must not loop through the
  // installer every time; the existing core keeps working meanwhile.
  return !sameCommit(stamp, input.attemptedCommit)
}

function readFirstLine(file: string): null | string {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/, 1)[0].trim() || null
  } catch {
    return null
  }
}

export function readInstalledCoreCommit(activeRoot: string): null | string {
  return readFirstLine(path.join(activeRoot, CORE_SOURCE_COMMIT_FILE))
}

export function readCoreUpdateAttempt(home: string): null | string {
  return readFirstLine(path.join(home, CORE_UPDATE_ATTEMPT_FILE))
}

export function recordCoreUpdateAttempt(home: string, commit: string): void {
  try {
    fs.mkdirSync(home, { recursive: true })
    fs.writeFileSync(path.join(home, CORE_UPDATE_ATTEMPT_FILE), `${commit}\n`, 'utf8')
  } catch {
    // Best effort: without the record the update is simply tried again.
  }
}

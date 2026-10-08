// neovarch-env.ts — keep Neovarch Desktop apart from a co-installed Hermes Agent.
//
// Neovarch's core is derived from Hermes Agent and still reads HERMES_HOME
// internally. Neovarch's own home is NEOVARCH_HOME (default ~/.neovarch,
// %LOCALAPPDATA%\neovarch on Windows). A machine that also runs Hermes may
// export HERMES_HOME=~/.hermes (install.ps1 even writes it to the user
// registry), HERMES_DATA_DIR_SUFFIX, or Hermes Desktop overrides. If any of
// those leaked into this process, every child (installer, backend, terminals)
// would read or write the Hermes install.
//
// pinNeovarchEnvironment() runs once, first thing in entry.ts, before main.ts
// loads: it drops the foreign values, resolves the Neovarch home, and pins
// HERMES_HOME to it so every module and child that still reads HERMES_HOME
// gets the Neovarch home. NEOVARCH_CORE=1 marks this process tree as
// Neovarch's (the core's process guard only signals marked processes).

import path from 'node:path'

import { resolveDesktopHermesHome } from './data-paths'

/** Hermes-owned variables a Neovarch process must never inherit. */
export const FOREIGN_HERMES_ENV: readonly string[] = [
  'HERMES_HOME',
  'HERMES_DATA_DIR_SUFFIX',
  'HERMES_DESKTOP_USER_DATA_DIR',
  'HERMES_DESKTOP_HERMES',
  'HERMES_DESKTOP_HERMES_ROOT',
  'HERMES_RUNTIME_DIR',
  'HERMES_INSTALL_ROOT',
  'HERMES_GATEWAY_LOCK_DIR'
]

/** Neovarch-named overrides and the internal names the desktop code reads. */
const OVERRIDE_ALIASES: ReadonlyArray<readonly [string, string]> = [
  ['NEOVARCH_DESKTOP_CORE', 'HERMES_DESKTOP_HERMES'],
  ['NEOVARCH_DESKTOP_CORE_ROOT', 'HERMES_DESKTOP_HERMES_ROOT']
]

export interface PinOptions {
  env?: NodeJS.ProcessEnv
  home: string
  platform?: NodeJS.Platform
  readWindowsHome?: () => string | null
}

export function pinNeovarchEnvironment({
  env = process.env,
  home,
  platform = process.platform,
  readWindowsHome = () => null
}: PinOptions): string {
  const dropped: string[] = []

  for (const key of FOREIGN_HERMES_ENV) {
    if (env[key] !== undefined) {
      delete env[key]
      dropped.push(key)
    }
  }

  for (const [ours, internal] of OVERRIDE_ALIASES) {
    if (env[ours]) {
      env[internal] = env[ours]
    }
  }

  const neovarchHome = resolveDesktopHermesHome({ home, env, platform, readWindowsHome })
  const paths = platform === 'win32' ? path.win32 : path.posix
  const resolved = paths.resolve(neovarchHome)

  env.NEOVARCH_HOME = resolved
  env.HERMES_HOME = resolved
  env.NEOVARCH_CORE = '1'

  if (env.NEOVARCH_DESKTOP_USER_DATA_DIR) {
    env.HERMES_DESKTOP_USER_DATA_DIR = env.NEOVARCH_DESKTOP_USER_DATA_DIR
  }

  if (dropped.length && env.NEOVARCH_DEBUG_ENV === '1') {
    console.log(`[neovarch] ignored inherited Hermes variables: ${dropped.join(', ')}`)
  }

  return resolved
}

/** True when `candidate` is inside (or equal to) the Neovarch home. */
export function isInsideNeovarchHome(candidate: string, neovarchHome: string, platform = process.platform): boolean {
  const paths = platform === 'win32' ? path.win32 : path.posix
  const rel = paths.relative(paths.resolve(neovarchHome), paths.resolve(candidate))

  return rel === '' || (!rel.startsWith('..') && !paths.isAbsolute(rel))
}

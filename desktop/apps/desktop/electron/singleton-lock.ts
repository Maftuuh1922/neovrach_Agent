import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

/**
 * Parse the PID encoded in Electron's Linux SingletonLock symlink.
 *
 * Chromium's ProcessSingleton on Linux/X11 owns `<userData>/SingletonLock`, a
 * symlink whose target is `<hostname>-<pid>` (#78101). The hostname prefix is
 * the guard against removing a lock owned from a different machine on a
 * shared home directory: a target that does not start with this host's
 * name is not ours to judge, so it parses to null and stays in place.
 */
export function parseSingletonLockPid(linkTarget: string | null | undefined, hostname: string): number | null {
  if (typeof linkTarget !== 'string' || linkTarget === '') {
    return null
  }

  const prefix = `${hostname}-`

  if (!linkTarget.startsWith(prefix)) {
    return null
  }

  const tail = linkTarget.slice(prefix.length)
  const pid = Number.parseInt(tail, 10)

  // Reject `123junk` / `+4`-style targets: only a bare decimal PID counts.
  if (!Number.isInteger(pid) || pid <= 0 || String(pid) !== tail) {
    return null
  }

  return pid
}

/**
 * Field 3 of `/proc/<pid>/stat` is the process state — but field 2, the comm,
 * is parenthesized and may contain spaces AND parentheses (`(hermes (v8))`),
 * so splitting on whitespace is wrong. The state is the first token after the
 * final `)`. Returns null for an unparseable line.
 */
export function parseProcStateField(statLine: string): string | null {
  const close = statLine.lastIndexOf(')')

  if (close === -1) {
    return null
  }

  const state = statLine
    .slice(close + 2)
    .split(' ')[0]
    .trim()

  return state === '' ? null : state
}

/**
 * Decide whether a SingletonLock owner is stale, from its `/proc` state.
 *
 * `kill(pid, 0)` succeeds for a zombie (the PID exists until its parent reaps
 * it), which is exactly the stale-owner case in #78101: Chromium's liveness
 * probe sees the defunct owner as alive, `requestSingleInstanceLock()`
 * returns false, and every later launch silently exits. A null state (no
 * `/proc` entry at all) is a dead owner and equally stale.
 */
export function isStaleSingletonLockOwner(procState: string | null | undefined): boolean {
  if (procState === null || procState === undefined) {
    return true
  }

  return procState.trim() === 'Z'
}

/** Read `/proc/<pid>/stat`'s state field, or null when the entry is gone. */
export function readLinuxProcState(pid: number): string | null {
  try {
    return parseProcStateField(fs.readFileSync(`/proc/${pid}/stat`, 'utf8'))
  } catch {
    return null
  }
}

/** `/proc/<pid>/exe` target, or null when unreadable/gone. */
export function readLinuxProcExe(pid: number): string | null {
  try {
    return fs.readlinkSync(`/proc/${pid}/exe`)
  } catch {
    return null
  }
}

/** Basename of an executable path, ignoring the kernel's ` (deleted)` suffix (unmounted AppImage). */
export function executableName(exePath: string | null | undefined): string | null {
  if (typeof exePath !== 'string' || exePath.trim() === '') {
    return null
  }

  const clean = exePath.trim().replace(/ \(deleted\)$/, '')
  const name = path.basename(clean)

  return name === '' ? null : name
}

/**
 * PID reuse: after a crash or reboot the lock's PID can belong to an unrelated
 * live process (a shell, a browser). Chromium then keeps failing to reach the
 * "owner" and every launch exits silently. A live owner whose executable name
 * provably differs from ours is not this app, so the lock is stale. Unknown
 * executables (unreadable /proc entry) are never judged.
 */
export function isForeignSingletonLockOwner(
  ownerExe: string | null | undefined,
  selfExe: string | null | undefined
): boolean {
  const owner = executableName(ownerExe)
  const self = executableName(selfExe)

  return owner !== null && self !== null && owner !== self
}

/**
 * Remove a provably-stale SingletonLock (Linux only) and return the dead
 * owner's PID, or null when the lock must be left alone: another machine's
 * lock (hostname mismatch), an unparseable target, or a live-looking owner.
 *
 * Live-looking means `/proc/<pid>/stat` shows a state other than Z — never
 * `kill(pid, 0)`, which reports zombies as alive — AND the owner is running an
 * executable with our name (a reused PID owned by another program is stale).
 */
export function removeStaleSingletonLock(
  userDataDir: string,
  deps: {
    platform?: NodeJS.Platform
    hostname?: string
    readProcState?: (pid: number) => string | null
    readProcExe?: (pid: number) => string | null
    selfExe?: string
  } = {}
): number | null {
  if ((deps.platform ?? process.platform) !== 'linux') {
    return null
  }

  const hostname = deps.hostname ?? os.hostname()
  const readProcState = deps.readProcState ?? readLinuxProcState

  let target: string

  try {
    target = fs.readlinkSync(path.join(userDataDir, 'SingletonLock'))
  } catch {
    // No lock (ENOENT), not a symlink (EINVAL), or unreadable: nothing to do.
    return null
  }

  const pid = parseSingletonLockPid(target, hostname)

  if (pid === null) {
    return null
  }

  if (!isStaleSingletonLockOwner(readProcState(pid))) {
    // Our own PID is never stale (a re-check after a lost race).
    if (pid === process.pid) {
      return null
    }

    const readProcExe = deps.readProcExe ?? readLinuxProcExe

    if (!isForeignSingletonLockOwner(readProcExe(pid), deps.selfExe ?? process.execPath)) {
      return null
    }
  }

  try {
    fs.unlinkSync(path.join(userDataDir, 'SingletonLock'))
  } catch {
    return null
  }

  return pid
}

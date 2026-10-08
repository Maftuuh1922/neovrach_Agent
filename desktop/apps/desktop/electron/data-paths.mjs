// data-paths.mjs — the pure path-resolution core, shared by the desktop app
// (via data-paths.ts, a typed re-export) and the CI smoke driver (which runs
// under Node's type-stripping and therefore cannot import the app's
// extensionless TypeScript directly). No Electron imports here; only node:path.
//
// data-paths.ts re-exports these names and adds the TypeScript-facing
// `HermesHomeOptions` interface. Keep the two in lockstep: every behavior in
// this file is exercised by data-paths.test.ts through the re-export.

import path from 'node:path'

/** A HERMES_HOME rooted inside a `profiles/` directory names the profile's
 * parent (the home), not the profile directory itself. */
function normalizeHermesHomeRoot(hermesHome, pathModule) {
  if (!hermesHome) {
    return hermesHome
  }
  const resolved = pathModule.resolve(String(hermesHome))
  const parent = pathModule.dirname(resolved)
  if (pathModule.basename(parent).toLowerCase() === 'profiles') {
    return pathModule.dirname(parent)
  }
  return resolved
}

// Neovarch: the data home is ~/.neovarch (%LOCALAPPDATA%\\neovarch on Windows),
// overridable with NEOVARCH_HOME. A co-installed Hermes Agent keeps ~/.hermes;
// nothing here ever reads HERMES_HOME or falls back to ~/.hermes.
export function platformDefaultHermesHome(home, env = process.env, platform = process.platform) {
  const suffix = env.NEOVARCH_DATA_DIR_SUFFIX || ''
  if (platform === 'win32') {
    const base = (env.LOCALAPPDATA || '').trim() || path.win32.join(home, 'AppData', 'Local')
    return path.win32.join(base, 'neovarch') + suffix
  }
  return path.posix.join(home, '.neovarch') + suffix
}

export function resolveDesktopUserData(defaultPath, env = process.env) {
  return env.NEOVARCH_DESKTOP_USER_DATA_DIR
    ? path.resolve(env.NEOVARCH_DESKTOP_USER_DATA_DIR)
    : defaultPath + (env.NEOVARCH_DATA_DIR_SUFFIX || '')
}

export function resolveDesktopHermesHome({ home, env = process.env, platform = process.platform, directoryExists = () => false, readWindowsHome = () => null }) {
  void directoryExists
  const paths = platform === 'win32' ? path.win32 : path.posix
  if (env.NEOVARCH_HOME) {
    return normalizeHermesHomeRoot(env.NEOVARCH_HOME, paths)
  }
  // Fresh-install rehearsals must not touch the real Neovarch home.
  if (env.NEOVARCH_DESKTOP_USER_DATA_DIR) {
    return paths.join(paths.resolve(env.NEOVARCH_DESKTOP_USER_DATA_DIR), 'neovarch-home')
  }
  if (platform === 'win32' && env.NEOVARCH_HOME === undefined) {
    // Explorer can miss setx changes. An explicit empty value opts out of that fallback.
    const registryHome = readWindowsHome()
    if (registryHome) {
      return normalizeHermesHomeRoot(registryHome, paths)
    }
  }
  return platformDefaultHermesHome(home, env, platform)
}

import assert from 'node:assert/strict'
import os from 'node:os'
import path from 'node:path'

import { afterEach, test, vi } from 'vitest'

import { platformDefaultHermesHome, resolveDesktopHermesHome, resolveDesktopUserData } from './data-paths'
import { controlSocketPath } from './ssh-connection'

afterEach((): void => {
  vi.unstubAllEnvs()
})

test.skipIf(process.platform === 'win32')('local SSH sockets use the suffixed default root', (): void => {
  vi.stubEnv('NEOVARCH_DATA_DIR_SUFFIX', 'magic-test')
  const socket: string = controlSocketPath('user', 'host', 22)

  assert.equal(path.dirname(socket), path.join(platformDefaultHermesHome(os.homedir()), 'desktop-ssh'))
})

test('default data roots append the suffix literally on each platform', (): void => {
  for (const platform of ['linux', 'darwin', 'win32'] as const) {
    const paths: typeof path = platform === 'win32' ? path.win32 : path.posix
    const home: string = platform === 'win32' ? 'C:\\Users\\test' : '/home/test'
    const local: string = paths.join(home, 'AppData', 'Local')
    const userData: string = paths.join(home, 'app-data', 'Neovarch Agent')
    const base: string = platform === 'win32' ? paths.join(local, 'neovarch') : paths.join(home, '.neovarch')

    for (const suffix of ['', '-asdfasdf', 'magic-test', ' spaced ']) {
      const env: NodeJS.ProcessEnv = { LOCALAPPDATA: local, NEOVARCH_DATA_DIR_SUFFIX: suffix }

      assert.equal(platformDefaultHermesHome(home, env, platform), base + suffix)
      assert.equal(resolveDesktopUserData(userData, env), userData + suffix)
      assert.equal(
        resolveDesktopHermesHome({ home, env, platform, directoryExists: (): boolean => false }),
        base + suffix
      )
    }
  }
})

test('explicit homes and userData retain precedence, and suffixed Windows homes never use legacy state', (): void => {
  const home: string = '/home/test'

  const env: NodeJS.ProcessEnv = {
    NEOVARCH_DATA_DIR_SUFFIX: 'magic-test',
    NEOVARCH_HOME: '/explicit/home',
    NEOVARCH_DESKTOP_USER_DATA_DIR: '/explicit/electron'
  }

  assert.equal(resolveDesktopUserData('/default/electron', env), path.resolve(env.NEOVARCH_DESKTOP_USER_DATA_DIR!))
  assert.equal(resolveDesktopHermesHome({ home, env, platform: 'linux' }), env.NEOVARCH_HOME)
  delete env.NEOVARCH_HOME
  assert.equal(resolveDesktopHermesHome({ home, env, platform: 'linux' }), '/explicit/electron/neovarch-home')

  const windowsHome: string = 'C:\\Users\\test'
  const windowsEnv: NodeJS.ProcessEnv = { NEOVARCH_DATA_DIR_SUFFIX: 'magic-test' }
  const expected: string = path.win32.join(windowsHome, 'AppData', 'Local', 'neovarchmagic-test')

  assert.equal(
    resolveDesktopHermesHome({
      home: windowsHome,
      env: windowsEnv,
      platform: 'win32',
      directoryExists: (): boolean => true
    }),
    expected
  )
  assert.equal(
    resolveDesktopHermesHome({
      home: windowsHome,
      env: windowsEnv,
      platform: 'win32',
      readWindowsHome: (): string => 'C:\\custom'
    }),
    'C:\\custom'
  )
})

test('a co-installed Hermes is never the Neovarch home: HERMES_* is ignored and ~/.hermes is never chosen', (): void => {
  const hermesEnv: NodeJS.ProcessEnv = {
    HERMES_HOME: '/home/test/.hermes',
    HERMES_DATA_DIR_SUFFIX: '-x',
    HERMES_DESKTOP_USER_DATA_DIR: '/home/test/.config/Hermes'
  }

  for (const platform of ['linux', 'darwin'] as const) {
    assert.equal(
      resolveDesktopHermesHome({ home: '/home/test', env: hermesEnv, platform, directoryExists: (): boolean => true }),
      '/home/test/.neovarch'
    )
  }

  assert.equal(
    resolveDesktopHermesHome({
      home: 'C:\\Users\\test',
      env: { ...hermesEnv, LOCALAPPDATA: 'C:\\Users\\test\\AppData\\Local' },
      platform: 'win32',
      directoryExists: (): boolean => true,
      readWindowsHome: (): null => null
    }),
    path.win32.join('C:\\Users\\test\\AppData\\Local', 'neovarch')
  )
  assert.equal(resolveDesktopUserData('/cfg/Neovarch Agent', hermesEnv), '/cfg/Neovarch Agent')
})

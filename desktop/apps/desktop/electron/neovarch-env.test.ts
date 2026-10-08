import assert from 'node:assert/strict'

import { test } from 'vitest'

import { FOREIGN_HERMES_ENV, isInsideNeovarchHome, pinNeovarchEnvironment } from './neovarch-env'

test('drops inherited Hermes variables and pins HERMES_HOME to the Neovarch home', (): void => {
  const env: NodeJS.ProcessEnv = {
    HERMES_HOME: '/home/u/.hermes',
    HERMES_DATA_DIR_SUFFIX: '-dev',
    HERMES_DESKTOP_USER_DATA_DIR: '/home/u/.config/Hermes',
    HERMES_DESKTOP_HERMES: '/home/u/.local/bin/hermes',
    HERMES_DESKTOP_HERMES_ROOT: '/home/u/.hermes/hermes-agent',
    PATH: '/usr/bin'
  }

  const home = pinNeovarchEnvironment({ env, home: '/home/u', platform: 'linux' })

  assert.equal(home, '/home/u/.neovarch')
  assert.equal(env.NEOVARCH_HOME, '/home/u/.neovarch')
  assert.equal(env.HERMES_HOME, '/home/u/.neovarch')
  assert.equal(env.NEOVARCH_CORE, '1')

  for (const key of FOREIGN_HERMES_ENV.filter(k => k !== 'HERMES_HOME')) {
    assert.equal(env[key], undefined, key)
  }

  assert.equal(env.PATH, '/usr/bin')
})

test('NEOVARCH_HOME and Neovarch-named overrides win', (): void => {
  const env: NodeJS.ProcessEnv = {
    NEOVARCH_HOME: '/data/nv',
    NEOVARCH_DESKTOP_CORE_ROOT: '/src/neovarch/core',
    NEOVARCH_DESKTOP_USER_DATA_DIR: '/tmp/ud',
    HERMES_HOME: '/home/u/.hermes'
  }

  assert.equal(pinNeovarchEnvironment({ env, home: '/home/u', platform: 'linux' }), '/data/nv')
  assert.equal(env.HERMES_HOME, '/data/nv')
  assert.equal(env.HERMES_DESKTOP_HERMES_ROOT, '/src/neovarch/core')
  assert.equal(env.HERMES_DESKTOP_USER_DATA_DIR, '/tmp/ud')
})

test('Windows default is %LOCALAPPDATA%\\neovarch, never %LOCALAPPDATA%\\hermes', (): void => {
  const env: NodeJS.ProcessEnv = { LOCALAPPDATA: 'C:\\Users\\u\\AppData\\Local', HERMES_HOME: 'C:\\Users\\u\\AppData\\Local\\hermes' }

  assert.equal(
    pinNeovarchEnvironment({ env, home: 'C:\\Users\\u', platform: 'win32', readWindowsHome: () => null }),
    'C:\\Users\\u\\AppData\\Local\\neovarch'
  )
})

test('isInsideNeovarchHome', (): void => {
  assert.equal(isInsideNeovarchHome('/home/u/.neovarch/profiles/a', '/home/u/.neovarch', 'linux'), true)
  assert.equal(isInsideNeovarchHome('/home/u/.hermes', '/home/u/.neovarch', 'linux'), false)
  assert.equal(isInsideNeovarchHome('/home/u/.neovarch-old', '/home/u/.neovarch', 'linux'), false)
})

import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { test } from 'vitest'

import {
  executableName,
  isForeignSingletonLockOwner,
  isStaleSingletonLockOwner,
  parseProcStateField,
  parseSingletonLockPid,
  removeStaleSingletonLock
} from './singleton-lock'

test('parseSingletonLockPid reads the owning PID only for this hostname', () => {
  assert.equal(parseSingletonLockPid('myhost-4711', 'myhost'), 4711)
  // A shared home directory can carry another machine's lock; never judge it.
  assert.equal(parseSingletonLockPid('otherhost-4711', 'myhost'), null)
  assert.equal(parseSingletonLockPid('myhost-4711-extra', 'myhost'), null)
  assert.equal(parseSingletonLockPid('myhost-0', 'myhost'), null)
  assert.equal(parseSingletonLockPid('myhost-notapid', 'myhost'), null)
  assert.equal(parseSingletonLockPid('', 'myhost'), null)
  assert.equal(parseSingletonLockPid(undefined, 'myhost'), null)
})

test('parseProcStateField survives a comm containing spaces and parentheses', () => {
  const stat = '4711 (Hermes Desktop (zygote)) Z 1 1 0 0 -1 4194560'
  assert.equal(parseProcStateField(stat), 'Z')
  assert.equal(parseProcStateField('4711 (node) S 1 1 0 0 -1'), 'S')
  assert.equal(parseProcStateField('no parentheses at all'), null)
})

test('a zombie or missing owner is stale; kill(pid,0) alone would say alive', () => {
  // #78101: a defunct process still answers kill(pid, 0) until reaped, so the
  // state field — not a signal probe — is the boundary.
  assert.equal(isStaleSingletonLockOwner('Z'), true)
  assert.equal(isStaleSingletonLockOwner(null), true)
  assert.equal(isStaleSingletonLockOwner(undefined), true)
  assert.equal(isStaleSingletonLockOwner('S'), false)
  assert.equal(isStaleSingletonLockOwner('R'), false)
  assert.equal(isStaleSingletonLockOwner(''), false)
})

test('removeStaleSingletonLock unlinks only a provably-dead owner', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hermes-singleton-lock-'))

  try {
    const lockPath = path.join(root, 'SingletonLock')

    // Live owner (state S): lock stays, nothing reported.
    fs.symlinkSync('myhost-4711', lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, {
        platform: 'linux',
        hostname: 'myhost',
        readProcState: () => 'S',
        readProcExe: () => '/tmp/.mount_NeovaX/neovarch-agent',
        selfExe: '/tmp/.mount_NeovaY/neovarch-agent'
      }),
      null
    )
    assert.equal(fs.readlinkSync(lockPath), 'myhost-4711')

    // Zombie owner (#78101): lock removed, PID reported.
    assert.equal(
      removeStaleSingletonLock(root, { platform: 'linux', hostname: 'myhost', readProcState: () => 'Z' }),
      4711
    )
    assert.equal(fs.existsSync(lockPath), false)

    // Dead owner (no /proc entry): lock removed too.
    fs.symlinkSync('myhost-4711', lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, { platform: 'linux', hostname: 'myhost', readProcState: () => null }),
      4711
    )

    // Another machine's lock on a shared home: never touched.
    fs.symlinkSync('otherhost-4711', lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, { platform: 'linux', hostname: 'myhost', readProcState: () => 'Z' }),
      null
    )
    assert.equal(fs.readlinkSync(lockPath), 'otherhost-4711')

    // No lock at all: nothing happens.
    fs.unlinkSync(lockPath)
    assert.equal(
      removeStaleSingletonLock(root, { platform: 'linux', hostname: 'myhost', readProcState: () => null }),
      null
    )
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('executableName ignores the kernel (deleted) suffix of an unmounted AppImage', () => {
  assert.equal(executableName('/tmp/.mount_NeovaX/neovarch-agent (deleted)'), 'neovarch-agent')
  assert.equal(executableName('/opt/Neovarch/neovarch-agent'), 'neovarch-agent')
  assert.equal(executableName(''), null)
  assert.equal(executableName(null), null)
})

test('a live owner running another program (reused PID) is foreign; unknown is never judged', () => {
  assert.equal(isForeignSingletonLockOwner('/usr/bin/bash', '/tmp/.mount_A/neovarch-agent'), true)
  assert.equal(isForeignSingletonLockOwner('/tmp/.mount_B/neovarch-agent (deleted)', '/tmp/.mount_A/neovarch-agent'), false)
  assert.equal(isForeignSingletonLockOwner(null, '/tmp/.mount_A/neovarch-agent'), false)
  assert.equal(isForeignSingletonLockOwner('/usr/bin/bash', null), false)
})

test('stale lock recovery: a reused PID is cleared, our own live app and our own PID are kept', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'neovarch-singleton-lock-'))
  const lockPath = path.join(root, 'SingletonLock')

  try {
    // After a reboot PID 4711 belongs to a shell: every launch would exit silently.
    fs.symlinkSync('myhost-4711', lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, {
        platform: 'linux',
        hostname: 'myhost',
        readProcState: () => 'S',
        readProcExe: () => '/usr/bin/bash',
        selfExe: '/opt/Neovarch/neovarch-agent'
      }),
      4711
    )
    assert.equal(fs.existsSync(lockPath), false)

    // A really running Neovarch keeps its lock: the second launch must focus it.
    fs.symlinkSync('myhost-4711', lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, {
        platform: 'linux',
        hostname: 'myhost',
        readProcState: () => 'S',
        readProcExe: () => '/opt/Neovarch/neovarch-agent',
        selfExe: '/opt/Neovarch/neovarch-agent'
      }),
      null
    )
    assert.equal(fs.readlinkSync(lockPath), 'myhost-4711')
    fs.unlinkSync(lockPath)

    // Our own PID is never treated as stale.
    fs.symlinkSync(`myhost-${process.pid}`, lockPath, 'file')
    assert.equal(
      removeStaleSingletonLock(root, {
        platform: 'linux',
        hostname: 'myhost',
        readProcState: () => 'S',
        readProcExe: () => '/usr/bin/bash',
        selfExe: '/opt/Neovarch/neovarch-agent'
      }),
      null
    )

    // Non-Linux platforms rely on Chromium's own lock.
    assert.equal(removeStaleSingletonLock(root, { platform: 'darwin', hostname: 'myhost' }), null)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

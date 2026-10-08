import assert from 'node:assert/strict'
import { type ChildProcess, execFileSync, spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { test, vi } from 'vitest'
import WebSocket from 'ws'

import { serveBackendArgs } from './backend-command'
import { waitForDashboardPort } from './backend-ready'
import { createSourcePythonBackend, resolveSourceInstallationBackend, type SourceBackend } from './source-backend'

async function stop(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) {
    return
  }

  await new Promise<void>((resolve: () => void): void => {
    const timer: NodeJS.Timeout = setTimeout((): void => {
      child.kill('SIGKILL')
    }, 5_000)

    child.once('exit', (): void => {
      clearTimeout(timer)
      resolve()
    })
    child.kill()
  })
}

async function ping(port: number, token: string): Promise<unknown> {
  const socket: WebSocket = new WebSocket(`ws://127.0.0.1:${port}/api/ws?token=${token}`)

  try {
    return await new Promise<unknown>((resolve: (value: unknown) => void, reject: (error: Error) => void): void => {
      const timer: NodeJS.Timeout = setTimeout((): void => {
        reject(new Error('RPC timed out'))
      }, 15_000)

      socket.once('error', (error: Error): void => {
        clearTimeout(timer)
        reject(error)
      })
      socket.once('open', (): void => {
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping', params: {} }))
      })
      socket.on('message', (data: WebSocket.RawData): void => {
        const response: { id?: number; result?: unknown; error?: unknown } = JSON.parse(data.toString())

        if (response.id === 1) {
          clearTimeout(timer)
          resolve(response)
        }
      })
    })
  } finally {
    socket.terminate()
  }
}

test.skipIf(process.platform === 'win32')(
  'an installed Neovarch core reaches real health and RPC, and a Hermes checkout is never adopted (POSIX)',
  async (): Promise<void> => {
    const temp: string = fs.mkdtempSync(path.join(os.tmpdir(), 'desktop-neovarch-start-'))
    const home: string = path.join(temp, 'home with spaces')
    const root: string = path.join(home, '.neovarch', 'neovarch-agent')
    const python: string = process.env.NEOVARCH_PYTHON || 'python3'
    const token: string = 'desktop-neovarch-contract'

    const env: NodeJS.ProcessEnv = Object.fromEntries(
      Object.entries(process.env).filter(
        ([key]: [string, string | undefined]): boolean => !/^(HERMES_|NEOVARCH_|PYTHON|VIRTUAL_ENV|XDG_)/.test(key)
      )
    )

    Object.assign(env, {
      HOME: home,
      USERPROFILE: home,
      NEOVARCH_HOME: path.join(home, '.neovarch'),
      HERMES_DASHBOARD_SESSION_TOKEN: token,
      PYTHONDONTWRITEBYTECODE: '1'
    })
    vi.stubEnv('HOME', home)

    try {
      // Same layout the installers write: core at ~/.neovarch/neovarch-agent,
      // its launcher in the install's venv.
      fs.cpSync(path.resolve(import.meta.dirname, '..', '..', '..', '..', 'core', 'neovarch'), path.join(root, 'neovarch'), {
        recursive: true,
        filter: (source: string): boolean => !source.includes('__pycache__')
      })
      const launcher: string = path.join(root, 'venv', 'bin', 'neovarch')
      fs.mkdirSync(path.dirname(launcher), { recursive: true })
      fs.writeFileSync(launcher, `#!/bin/sh\nPYTHONPATH='${root}' exec '${python}' -m neovarch "$@"\n`, { mode: 0o755 })

      // A Hermes-shaped tree is not a Neovarch install.
      const hermesRoot: string = path.join(temp, 'hermes-agent')
      fs.mkdirSync(path.join(hermesRoot, 'hermes_cli'), { recursive: true })
      fs.writeFileSync(path.join(hermesRoot, 'hermes_cli', 'main.py'), '')
      assert.equal(await resolveSourceInstallationBackend(hermesRoot, serveBackendArgs(), { env }), null)

      const backend: SourceBackend | null = await resolveSourceInstallationBackend(root, serveBackendArgs('work'), {
        hermesHome: env.NEOVARCH_HOME,
        env
      })

      assert.ok(backend, 'an installed, runnable Neovarch core must be accepted')
      assert.equal(backend.command, launcher)
      assert.deepEqual(backend.args, ['--profile', 'work', 'serve', '--host', '127.0.0.1', '--port', '0'])

      const child: ChildProcess = spawn(backend.command, backend.args, {
        cwd: temp,
        env: { ...env, ...backend.env },
        shell: backend.shell,
        stdio: ['ignore', 'pipe', 'pipe']
      })

      let output: string = ''
      child.stdout?.on('data', (data: Buffer): void => {
        output += data.toString()
      })
      child.stderr?.on('data', (data: Buffer): void => {
        output += data.toString()
      })

      try {
        const port: number = (await waitForDashboardPort(child, 45_000)) as number

        const response: Response = await fetch(`http://127.0.0.1:${port}/api/health`, {
          headers: { 'X-Hermes-Session-Token': token }
        })

        assert.equal(response.status, 200, output)
        assert.deepEqual(await ping(port, token), { jsonrpc: '2.0', id: 1, result: { pong: true } })
        assert.ok(fs.existsSync(path.join(home, '.neovarch', 'profiles', 'work')), 'the profile lives under ~/.neovarch')
        assert.equal(fs.existsSync(path.join(home, '.hermes')), false, 'the core must never create ~/.hermes')
      } catch (error: unknown) {
        throw new Error(`${String(error)}\n${output}`)
      } finally {
        await stop(child)
      }

      const source: SourceBackend | null = createSourcePythonBackend(root, python, ['--version'], { env })
      assert.ok(source)
      assert.deepEqual(source.args, ['-m', 'neovarch', '--version'])
      assert.match(
        execFileSync(source.command, source.args, {
          cwd: temp,
          env: { ...env, ...source.env },
          encoding: 'utf8',
          timeout: 15_000
        }),
        /Neovarch/
      )

      fs.unlinkSync(launcher)
      assert.equal(
        await resolveSourceInstallationBackend(root, serveBackendArgs(), { hermesHome: env.NEOVARCH_HOME, env }),
        null,
        'a missing launcher must not fall back to anything else'
      )
    } finally {
      fs.rmSync(temp, { recursive: true, force: true })
      vi.unstubAllEnvs()
    }
  },
  90_000
)

test('Windows console selection uses only the selected interpreter directory', (): void => {
  const temp: string = fs.mkdtempSync(path.join(os.tmpdir(), 'desktop-console-policy-'))
  const root: string = path.join(temp, 'repo')
  const selected: string = path.join(temp, 'external', 'pythonw.exe')
  const consolePython: string = path.join(path.dirname(selected), 'python.exe')

  try {
    fs.mkdirSync(path.join(root, 'venv', 'Scripts'), { recursive: true })
    fs.writeFileSync(path.join(root, 'venv', 'Scripts', 'python.exe'), 'stale')
    fs.mkdirSync(path.dirname(selected), { recursive: true })
    fs.writeFileSync(selected, '')
    assert.equal(createSourcePythonBackend(root, selected, [], { isWindows: true })?.command, selected)
    fs.writeFileSync(consolePython, '')
    const backend: SourceBackend | null = createSourcePythonBackend(root, selected, ['serve'], { isWindows: true })
    assert.equal(backend?.command, consolePython)
    assert.equal(backend?.env.PYTHONPATH, root)
    assert.equal(backend?.env.PYTHONHOME, '')
    assert.equal(createSourcePythonBackend(root, selected, [], { isWindows: false })?.command, selected)
    assert.equal(createSourcePythonBackend(root, null, []), null)
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
})

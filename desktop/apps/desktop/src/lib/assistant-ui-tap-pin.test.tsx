// Regression guard for the Neovarch 1.2.0 renderer crash ("Maximum update
// depth exceeded. The result of getSnapshot should be cached to avoid an
// infinite loop", then the workspace pane crashing after the first send).
//
// Root cause: the lockfile had been regenerated, which floated
// @assistant-ui/tap from the upstream-pinned 0.9.8 to 0.9.21. tap >= 0.9.1x
// adds a post-commit consistency check to its resource-level
// useSyncExternalStore that re-renders until `getSnapshot()` is
// referentially stable. @assistant-ui/core 0.2.23's ThreadListRuntimeImpl
// subscribes callers to its core directly, so its LazyMemoizeSubject never
// "connects" and `getState()` builds a fresh object on every call. With the
// newer tap that is an endless re-render of the thread-list client resource.
//
// The workspace pins tap to 0.9.8 (root package.json `overrides` + lockfile,
// matching upstream Hermes Desktop). These tests fail if the pin drifts.
import fs from 'node:fs'
import path from 'node:path'

import { AssistantRuntimeProvider, type ThreadMessageLike, useAuiState, useExternalStoreRuntime } from '@assistant-ui/react'
import { act, cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

function findPackageJson(name: string): string {
  let dir = __dirname

  for (;;) {
    const candidate = path.join(dir, 'node_modules', name, 'package.json')

    if (fs.existsSync(candidate)) {
      return candidate
    }

    const parent = path.dirname(dir)

    if (parent === dir) {
      throw new Error(`${name} is not installed`)
    }

    dir = parent
  }
}

function text(id: string, role: 'user' | 'assistant', value: string): ThreadMessageLike {
  return { id, role, content: value, createdAt: new Date(0) }
}

function ThreadProbe() {
  const mainThreadId = useAuiState(s => s.threads.mainThreadId)
  const count = useAuiState(s => s.thread.messages.length)

  return <div data-testid="probe">{`${mainThreadId}:${count}`}</div>
}

function Harness({ messages }: { messages: ThreadMessageLike[] }) {
  const runtime = useExternalStoreRuntime<ThreadMessageLike>({
    messages,
    convertMessage: m => m,
    onNew: async () => {}
  })

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <ThreadProbe />
    </AssistantRuntimeProvider>
  )
}

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})

describe('@assistant-ui/tap pin', () => {
  it('stays on the upstream-tested 0.9.8', () => {
    const pkg = JSON.parse(fs.readFileSync(findPackageJson('@assistant-ui/tap'), 'utf8')) as { version: string }

    expect(pkg.version).toBe('0.9.8')
  })

  it('mounts the assistant runtime and survives new messages without an update loop', async () => {
    const errors: string[] = []

    vi.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
      errors.push(args.map(String).join(' '))
    })

    const view = render(<Harness messages={[]} />)

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 20))
    })

    view.rerender(<Harness messages={[text('u1', 'user', 'hi')]} />)
    view.rerender(<Harness messages={[text('u1', 'user', 'hi'), text('a1', 'assistant', 'hello')]} />)

    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 20))
    })

    expect(screen.getByTestId('probe').textContent).toMatch(/:2$/)
    expect(errors.filter(e => /Maximum update depth|getSnapshot should be cached/.test(e))).toEqual([])
  })
})

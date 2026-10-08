import { useStore } from '@nanostores/react'
import { useMemo } from 'react'
import { useLocation } from 'react-router'

import { appViewForPath } from '@/app/routes'
import type { ChatMessage } from '@/lib/chat-messages/types'
import { ChevronDown, Cpu, FileText, Wrench } from '@/lib/icons'
import { $reviewFiles } from '@/store/review'
import { $currentModel, $currentProvider, $messages, setModelPickerOpen } from '@/store/session'

import { shortModelName } from './command-bar'

const PATH_KEYS = ['path', 'file_path', 'filepath', 'filename', 'file', 'target_file']

interface ToolUse {
  count: number
  name: string
}

/** Tool calls in the open conversation, most used first. */
export function toolsUsed(messages: readonly ChatMessage[]): ToolUse[] {
  const counts = new Map<string, number>()

  for (const message of messages) {
    for (const part of message.parts) {
      const candidate = part as { toolName?: unknown; type?: unknown }

      if (candidate.type === 'tool-call' && typeof candidate.toolName === 'string' && candidate.toolName) {
        counts.set(candidate.toolName, (counts.get(candidate.toolName) ?? 0) + 1)
      }
    }
  }

  return [...counts.entries()].map(([name, count]) => ({ count, name })).sort((a, b) => b.count - a.count)
}

/** File paths the conversation's tool calls pointed at, in first-seen order. */
export function filesTouched(messages: readonly ChatMessage[]): string[] {
  const seen = new Set<string>()

  for (const message of messages) {
    for (const part of message.parts) {
      const candidate = part as { args?: unknown; type?: unknown }

      if (candidate.type !== 'tool-call' || !candidate.args || typeof candidate.args !== 'object') {
        continue
      }

      const args = candidate.args as Record<string, unknown>

      for (const key of PATH_KEYS) {
        const value = args[key]

        if (typeof value === 'string' && value.trim()) {
          seen.add(value.trim())
        }
      }
    }
  }

  return [...seen]
}

function baseName(path: string): string {
  const parts = path.split(/[\\/]/)

  return parts[parts.length - 1] || path
}

/**
 * The right context rail beside the conversation: the model in use, the tools
 * this chat has called and the files it touched (plus uncommitted changes when
 * the review store has them). Only shown on chat routes.
 */
export function NeovarchContextRail() {
  const { pathname } = useLocation()
  const model = useStore($currentModel)
  const provider = useStore($currentProvider)
  const messages = useStore($messages)
  const reviewFiles = useStore($reviewFiles)

  const tools = useMemo(() => toolsUsed(messages), [messages])
  const touched = useMemo(() => filesTouched(messages), [messages])

  if (appViewForPath(pathname) !== 'chat') {
    return null
  }

  const turns = messages.filter(message => message.role === 'user' && !message.hidden).length

  return (
    <aside aria-label="Konteks" className="nv-context" data-slot="nv-context-rail">
      <section className="nv-context-card">
        <h3 className="nv-context-label">
          <Cpu className="size-3.5" /> Model
        </h3>
        <button className="nv-context-model" onClick={() => setModelPickerOpen(true)} title={model || undefined} type="button">
          <span className="nv-context-model-name">{shortModelName(model)}</span>
          <ChevronDown className="size-3 shrink-0 opacity-70" />
        </button>
        <dl className="nv-context-facts">
          <div>
            <dt>Penyedia</dt>
            <dd>{provider || '—'}</dd>
          </div>
          <div>
            <dt>Pesan Anda</dt>
            <dd>{turns}</dd>
          </div>
        </dl>
      </section>

      <section className="nv-context-card">
        <h3 className="nv-context-label">
          <Wrench className="size-3.5" /> Tool dipakai
        </h3>
        {tools.length === 0 ? (
          <p className="nv-context-empty">Belum ada tool yang dipanggil di obrolan ini.</p>
        ) : (
          <ul className="nv-context-list">
            {tools.slice(0, 8).map(tool => (
              <li key={tool.name}>
                <span className="nv-context-mono">{tool.name}</span>
                <span className="nv-context-count">{tool.count}×</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="nv-context-card">
        <h3 className="nv-context-label">
          <FileText className="size-3.5" /> File
        </h3>
        {touched.length === 0 && reviewFiles.length === 0 ? (
          <p className="nv-context-empty">Belum ada file yang dibuka atau diubah.</p>
        ) : (
          <ul className="nv-context-list">
            {touched.slice(0, 8).map(path => (
              <li key={`t:${path}`} title={path}>
                <span className="nv-context-mono">{baseName(path)}</span>
              </li>
            ))}
            {reviewFiles.slice(0, 8).map(file => (
              <li key={`r:${file.path}`} title={file.path}>
                <span className="nv-context-mono">{baseName(file.path)}</span>
                <span className="nv-context-count">
                  +{file.added} −{file.removed}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </aside>
  )
}

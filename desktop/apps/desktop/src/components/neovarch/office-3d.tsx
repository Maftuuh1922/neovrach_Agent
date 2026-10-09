import { useEffect, useMemo, useRef, useState } from 'react'

import { X } from '@/lib/icons'

import { AgentAvatar } from './agent-identity'
import { OFFICE3D_STATUS, type SceneAgent, sceneAgentsFromSnapshot } from './office3d-model'
import type { OfficeScene } from './office3d-scene'
import { OfficeModelSelect } from './office-model-select'
import { assignOfficeTask, type OfficeAgent, type OfficeSnapshot } from './office-store'

/** True when this renderer can create a WebGL context (false in jsdom, with
 *  GPU acceleration blocked, or on drivers Chromium refuses). */
export function hasWebGL(): boolean {
  try {
    const canvas = document.createElement('canvas')
    const gl = canvas.getContext('webgl2') ?? canvas.getContext('webgl')

    return Boolean(gl)
  } catch {
    return false
  }
}

// three.js only loads with the first 3D office, never at startup.
export const loadOfficeScene = () => import('./office3d-scene')

interface Office3DProps {
  /** Rendered instead of the scene when WebGL or the scene can't start. */
  fallback: React.ReactNode
  office: null | OfficeSnapshot
  onOpenSession: (sessionId: string) => void
}

type Phase = 'failed' | 'loading' | 'ready'

/** The Office as a live 3D room. Everything comes from the same live office
 *  snapshot as the list; this only re-maps it onto the scene. */
export function Office3D({ fallback, office, onOpenSession }: Office3DProps) {
  const supported = useMemo(() => hasWebGL(), [])
  const stageRef = useRef<HTMLDivElement>(null)
  const labelsRef = useRef<HTMLDivElement>(null)
  const [scene, setScene] = useState<null | OfficeScene>(null)
  const [failed, setFailed] = useState(false)
  const [selectedId, setSelectedId] = useState<null | string>(null)
  const sceneAgents = useMemo(() => sceneAgentsFromSnapshot(office), [office])

  useEffect(() => {
    if (!supported || !stageRef.current) {
      return
    }

    let cancelled = false
    let created: null | OfficeScene = null
    const container = stageRef.current

    loadOfficeScene()
      .then(({ createOfficeScene }) => {
        if (cancelled) {
          return
        }

        created = createOfficeScene({
          container,
          labelLayer: labelsRef.current,
          onSelect: id => setSelectedId(id),
          reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
        })
        setScene(created)
      })
      .catch(() => {
        if (!cancelled) {
          setFailed(true)
        }
      })

    return () => {
      cancelled = true
      created?.dispose()
      setScene(null)
    }
  }, [supported])

  // Live: every office.update re-maps the snapshot and the scene diffs it.
  useEffect(() => {
    scene?.setAgents(sceneAgents)
  }, [scene, sceneAgents])

  useEffect(() => {
    scene?.setSelected(selectedId)
  }, [scene, selectedId])

  const phase: Phase = !supported || failed ? 'failed' : scene ? 'ready' : 'loading'

  if (phase === 'failed') {
    return (
      <div className="nv-office3d-fallback" data-slot="nv-office3d-fallback">
        <p className="nv-office3d-note" role="status">
          Tampilan 3D tidak tersedia di perangkat ini (WebGL mati), jadi kantor ditampilkan sebagai daftar.
        </p>
        {fallback}
      </div>
    )
  }

  const selected = office?.agents.find(agent => agent.id === selectedId) ?? null
  const selectedScene = sceneAgents.find(agent => agent.id === selectedId) ?? null

  return (
    <section aria-label="Kantor 3D" className="nv-office3d" data-phase={phase} data-slot="nv-office3d">
      <div className="nv-office3d-stage" ref={stageRef} />
      <div
        aria-hidden={phase !== 'ready'}
        className="nv-office3d-labels"
        data-slot="nv-office3d-labels"
        ref={labelsRef}
      >
        {sceneAgents.map(agent => (
          <AgentLabel
            agent={agent}
            key={agent.id}
            onClick={() => setSelectedId(agent.id)}
            selected={agent.id === selectedId}
          />
        ))}
      </div>
      {phase === 'loading' && <p className="nv-office3d-loading">Menyiapkan kantor 3D…</p>}
      {office && office.agents.length === 0 && phase === 'ready' && (
        <p className="nv-office3d-empty">Belum ada pegawai. Mulai obrolan atau beri tugas di Kanban.</p>
      )}
      {phase === 'ready' && (
        <div className="nv-office3d-legend" data-slot="nv-office3d-legend">
          {(['working', 'waiting', 'error', 'idle'] as const).map(status => (
            <span key={status}>
              <i style={{ background: OFFICE3D_STATUS[status].color }} />
              {OFFICE3D_STATUS[status].text}
            </span>
          ))}
          <button className="nv-office3d-reset" onClick={() => scene?.resetCamera()} type="button">
            Atur ulang kamera
          </button>
        </div>
      )}
      {selected && selectedScene && (
        <AgentPopover
          agent={selected}
          key={selected.id}
          onClose={() => setSelectedId(null)}
          onOpenSession={onOpenSession}
          scene={selectedScene}
        />
      )}
    </section>
  )
}

function AgentLabel({ agent, onClick, selected }: { agent: SceneAgent; onClick: () => void; selected: boolean }) {
  return (
    <button
      className="nv-office3d-label"
      data-agent-label={agent.id}
      data-selected={selected || undefined}
      data-status={agent.status}
      onClick={onClick}
      style={{ visibility: 'hidden' }}
      tabIndex={-1}
      type="button"
    >
      <span className="nv-office3d-label-name">
        <i style={{ background: OFFICE3D_STATUS[agent.status].color }} />
        {agent.name}
      </span>
      <span className="nv-office3d-label-task">{agent.label}</span>
    </button>
  )
}

export function AgentPopover({
  agent,
  onClose,
  onOpenSession,
  scene
}: {
  agent: OfficeAgent
  onClose: () => void
  onOpenSession: (sessionId: string) => void
  scene: SceneAgent
}) {
  const [title, setTitle] = useState('')

  const [state, setState] = useState<{
    kind: 'error' | 'idle' | 'sending' | 'sent'
    message?: string
  }>({
    kind: 'idle'
  })

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    const trimmed = title.trim()

    if (!trimmed || state.kind === 'sending') {
      return
    }

    setState({ kind: 'sending' })

    try {
      await assignOfficeTask(agent, trimmed)
      setTitle('')
      setState({ kind: 'sent', message: `Tugas dikirim ke ${agent.name}.` })
    } catch (error) {
      setState({
        kind: 'error',
        message: error instanceof Error ? error.message : String(error)
      })
    }
  }

  return (
    <div
      aria-label={`Agen ${agent.name}`}
      className="nv-office3d-popover"
      data-slot="nv-office3d-popover"
      role="dialog"
    >
      <header>
        <AgentAvatar id={agent.id} name={agent.name} size={44} status={scene.status} />
        <div className="min-w-0">
          <p className="nv-office3d-popover-kicker">{agent.role}</p>
          <h3>{agent.name}</h3>
          <span className="nv-office-status" data-status={agent.status}>
            <i style={{ background: OFFICE3D_STATUS[scene.status].color }} /> {scene.statusText}
          </span>
        </div>
        <button aria-label="Tutup" className="nv-office3d-close" onClick={onClose} type="button">
          <X className="size-3.5" />
        </button>
      </header>
      <p className="nv-office3d-popover-task" title={scene.label}>
        {agent.current_task || 'Belum ada tugas'}
      </p>
      {agent.pending_approval?.command && (
        <p className="nv-office-mono nv-office3d-popover-approval">Minta izin: {agent.pending_approval.command}</p>
      )}
      <OfficeModelSelect agent={agent} />
      {agent.session_id && (
        <button className="nv-office-open" onClick={() => onOpenSession(agent.session_id!)} type="button">
          Buka sesi
        </button>
      )}
      <form className="nv-office3d-assign" data-slot="nv-office3d-assign" onSubmit={submit}>
        <label htmlFor={`nv-assign-${agent.id}`}>Kasih tugas</label>
        <div>
          <input
            id={`nv-assign-${agent.id}`}
            onChange={event => setTitle(event.target.value)}
            placeholder={`Tugas untuk ${agent.name}…`}
            value={title}
          />
          <button disabled={!title.trim() || state.kind === 'sending'} type="submit">
            {state.kind === 'sending' ? 'Mengirim…' : 'Kasih tugas'}
          </button>
        </div>
        {state.message && (
          <p className="nv-office3d-assign-state" data-kind={state.kind} role="status">
            {state.message}
          </p>
        )}
      </form>
    </div>
  )
}

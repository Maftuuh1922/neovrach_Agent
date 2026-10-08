import { useStore } from '@nanostores/react'
import { useMemo } from 'react'
import { useNavigate } from 'react-router'

import { openSessionFromPicker } from '@/app/open-session'
import { CAPABILITIES_ROUTE, navigateToWorkspacePage } from '@/app/routes'
import { pluginActive, setPluginEnabled } from '@/contrib/plugins-store'
import homePoster from '@/assets/neovarch/home-poster.webp'
import { sessionTitle } from '@/lib/chat-runtime'
import { ArrowUpRight, LayoutDashboard, Plus, QrCode, Zap } from '@/lib/icons'
import { requestFreshSession } from '@/store/profile'
import { $sessions } from '@/store/session'

const RECENT_LIMIT = 6

/** Time-of-day greeting in Indonesian (local clock). */
export function neovarchGreeting(date: Date = new Date()): string {
  const hour = date.getHours()

  if (hour < 11) {
    return 'Selamat pagi.'
  }

  if (hour < 15) {
    return 'Selamat siang.'
  }

  if (hour < 19) {
    return 'Selamat sore.'
  }

  return 'Selamat malam.'
}

export function relativeTime(epochSeconds: number): string {
  if (!epochSeconds) {
    return ''
  }

  const ms = epochSeconds > 1e12 ? epochSeconds : epochSeconds * 1000
  const minutes = Math.max(0, Math.round((Date.now() - ms) / 60000))

  if (minutes < 1) {
    return 'baru saja'
  }

  if (minutes < 60) {
    return `${minutes} mnt lalu`
  }

  const hours = Math.round(minutes / 60)

  if (hours < 24) {
    return `${hours} jam lalu`
  }

  return `${Math.round(hours / 24)} hari lalu`
}

/**
 * Open the Tasks board. Kanban is an opt-in plugin (off on a fresh install), so
 * picking "Tugas" is the user's opt-in: enable it first, then navigate.
 */
export async function openNeovarchKanban(navigate: (to: string) => void): Promise<void> {
  if (!pluginActive('kanban', false)) {
    await setPluginEnabled('kanban', true)
  }

  navigateToWorkspacePage(navigate, '/kanban')
}

function focusComposer() {
  window.requestAnimationFrame(() => {
    document.querySelector<HTMLElement>('[data-slot="composer-root"] [contenteditable="true"]')?.focus()
  })
}

/** Poster art beside the greeting — dithered red-on-black, decorative. */
export function NeovarchHomePoster() {
  return (
    <figure aria-hidden="true" className="nv-home-poster" data-slot="nv-home-poster">
      <img alt="" draggable={false} src={homePoster} />
    </figure>
  )
}

/**
 * Quick actions + the recent-session index under the greeting. Needs the
 * router, so the Intro only mounts it inside one.
 */
export function NeovarchHomeActions() {
  const navigate = useNavigate()
  const sessions = useStore($sessions)

  const recent = useMemo(
    () =>
      sessions
        .filter(session => !session.archived)
        .slice()
        .sort((a, b) => (b.last_active || b.started_at || 0) - (a.last_active || a.started_at || 0))
        .slice(0, RECENT_LIMIT),
    [sessions]
  )

  const actions = [
    {
      hint: 'Mulai percakapan',
      icon: <Plus className="size-4" />,
      id: 'new-chat',
      label: 'Obrolan baru',
      onSelect: () => {
        requestFreshSession()
        focusComposer()
      }
    },
    {
      hint: 'Pindai QR dari HP',
      icon: <QrCode className="size-4" />,
      id: 'pair-phone',
      label: 'Pasangkan HP',
      onSelect: () => navigate('/settings?tab=remote')
    },
    {
      hint: 'Papan Kanban',
      icon: <LayoutDashboard className="size-4" />,
      id: 'tasks',
      label: 'Tugas',
      onSelect: () => void openNeovarchKanban(navigate)
    },
    {
      hint: 'Skill dan tool',
      icon: <Zap className="size-4" />,
      id: 'skills',
      label: 'Kemampuan',
      onSelect: () => navigateToWorkspacePage(navigate, CAPABILITIES_ROUTE)
    }
  ]

  return (
    <div className="nv-home-lower">
      <div className="nv-home-actions" data-slot="nv-home-actions" role="group">
        {actions.map(action => (
          <button
            className="nv-home-action"
            data-nv-action={action.id}
            key={action.id}
            onClick={action.onSelect}
            type="button"
          >
            <span className="nv-home-action-icon">{action.icon}</span>
            <span className="nv-home-action-label">{action.label}</span>
            <span className="nv-home-action-hint">{action.hint}</span>
          </button>
        ))}
      </div>

      <section aria-label="Sesi terakhir" className="nv-home-index" data-slot="nv-home-index">
        <header className="nv-home-index-head">
          <span>Indeks sesi</span>
          <span>{recent.length ? `${recent.length} terakhir` : 'kosong'}</span>
        </header>
        {recent.length === 0 ? (
          <span className="nv-home-index-empty">Belum ada sesi. Tulis tujuan pertama di bawah.</span>
        ) : (
          <ol>
            {recent.map((session, index) => (
              <li key={session.id}>
                <button
                  className="nv-home-index-row"
                  onClick={() => openSessionFromPicker(session.id, navigate)}
                  type="button"
                >
                  <span className="nv-home-index-no">{String(index + 1).padStart(2, '0')}</span>
                  <span className="nv-home-index-title">{sessionTitle(session)}</span>
                  <span className="nv-home-index-time">{relativeTime(session.last_active || session.started_at)}</span>
                  <ArrowUpRight className="nv-home-index-go size-3.5" />
                </button>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  )
}

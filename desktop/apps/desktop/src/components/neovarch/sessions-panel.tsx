import { useStore } from '@nanostores/react'
import { useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router'

import { openSessionFromPicker } from '@/app/open-session'
import { routeSessionId } from '@/app/routes'
import { sessionTitle } from '@/lib/chat-runtime'
import { Plus, X } from '@/lib/icons'
import { cn } from '@/lib/utils'
import { requestFreshSession } from '@/store/profile'
import { $sessions } from '@/store/session'

import { relativeTime } from './home'
import { $nvSessionsOpen, closeNvSessions } from './layout-store'

const DAY_MS = 24 * 60 * 60 * 1000

function sessionMs(epoch: number): number {
  if (!epoch) {
    return 0
  }

  return epoch > 1e12 ? epoch : epoch * 1000
}

/**
 * The session list as a panel beside the rail, opened from the rail's "Sesi"
 * button. Grouped by recency (Hari ini / 7 hari / Lebih lama). Searching stays
 * in the top bar (Ctrl K), so the panel has no search field of its own.
 */
export function NeovarchSessionsPanel() {
  const open = useStore($nvSessionsOpen)
  const sessions = useStore($sessions)
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const activeId = routeSessionId(pathname)

  const groups = useMemo(() => {
    const now = Date.now()

    const rows = sessions
      .filter(session => !session.archived)
      .slice()
      .sort((a, b) => (b.last_active || b.started_at || 0) - (a.last_active || a.started_at || 0))

    const today: typeof rows = []
    const week: typeof rows = []
    const older: typeof rows = []

    for (const session of rows) {
      const age = now - sessionMs(session.last_active || session.started_at)

      if (age < DAY_MS) {
        today.push(session)
      } else if (age < 7 * DAY_MS) {
        week.push(session)
      } else {
        older.push(session)
      }
    }

    return [
      { id: 'today', label: 'Hari ini', rows: today },
      { id: 'week', label: '7 hari terakhir', rows: week },
      { id: 'older', label: 'Lebih lama', rows: older }
    ].filter(group => group.rows.length > 0)
  }, [sessions])

  if (!open) {
    return null
  }

  const total = groups.reduce((sum, group) => sum + group.rows.length, 0)

  return (
    <aside aria-label="Sesi" className="nv-sessions" data-slot="nv-sessions-panel">
      <header className="nv-sessions-head">
        <div className="nv-sessions-title">
          <span>Sesi</span>
          <span className="nv-sessions-count">{total}</span>
        </div>
        <button aria-label="Tutup panel sesi" className="nv-icon-button" onClick={closeNvSessions} type="button">
          <X className="size-3.5" />
        </button>
      </header>

      <button
        className="nv-sessions-new"
        onClick={() => {
          navigate('/')
          requestFreshSession()
        }}
        type="button"
      >
        <Plus className="size-3.5" />
        Obrolan baru
      </button>

      <div className="nv-sessions-list">
        {total === 0 ? (
          <p className="nv-sessions-empty">Belum ada sesi. Mulai obrolan baru di atas.</p>
        ) : (
          groups.map(group => (
            <section className="nv-sessions-group" key={group.id}>
              <h3 className="nv-sessions-group-label">{group.label}</h3>
              <ul>
                {group.rows.map(session => (
                  <li key={session.id}>
                    <button
                      className={cn('nv-sessions-row', activeId === session.id && 'nv-sessions-row-active')}
                      data-nv-session={session.id}
                      onClick={() => openSessionFromPicker(session.id, navigate)}
                      type="button"
                    >
                      <span className="nv-sessions-row-title">{sessionTitle(session)}</span>
                      <span className="nv-sessions-row-time">
                        {relativeTime(session.last_active || session.started_at)}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ))
        )}
      </div>
    </aside>
  )
}

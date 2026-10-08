import { useStore } from '@nanostores/react'
import { type ReactNode, useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router'

import { ARTIFACTS_ROUTE, CAPABILITIES_ROUTE, CRON_ROUTE, MESSAGING_ROUTE, navigateToWorkspacePage } from '@/app/routes'
import { openNeovarchKanban } from '@/components/neovarch/home'
import { Tip } from '@/components/ui/tooltip'
import {
  Clock,
  FileText,
  LayoutDashboard,
  MessageCircle,
  MessageSquareText,
  Moon,
  Plus,
  QrCode,
  Settings,
  Sun,
  Zap
} from '@/lib/icons'
import { cn } from '@/lib/utils'
import { setSidebarOpen } from '@/store/layout'
import { requestFreshSession } from '@/store/profile'
import { useTheme } from '@/themes/context'

import { HaloMark } from './halo-mark'
import { $nvSessionsOpen, toggleNvSessions } from './layout-store'

export const NV_RAIL_WIDTH = 60

export const NV_COPY = {
  home: 'Beranda',
  newChat: 'Obrolan baru',
  sessions: 'Sesi',
  skills: 'Skill & kemampuan',
  kanban: 'Tugas (Kanban)',
  messaging: 'Bot & pesan',
  artifacts: 'Artefak',
  cron: 'Jadwal',
  pairPhone: 'Pasangkan HP',
  settings: 'Pengaturan',
  toDark: 'Tema gelap',
  toLight: 'Tema terang'
}

interface RailItem {
  active?: boolean
  icon: ReactNode
  id: string
  label: string
  onSelect: () => void
}

function RailButton({ item }: { item: RailItem }) {
  return (
    <Tip label={item.label} side="right">
      <button
        aria-label={item.label}
        aria-pressed={item.active ?? undefined}
        className={cn('nv-rail-button', item.active && 'nv-rail-button-active')}
        data-nv-rail={item.id}
        onClick={item.onSelect}
        type="button"
      >
        {item.icon}
      </button>
    </Tip>
  )
}

/**
 * Neovarch's slim icon rail — every primary destination one click away, so the
 * sessions panel beside it can stay a collapsible list instead of Hermes'
 * nav-plus-sessions column.
 */
export function NeovarchRail() {
  const navigate = useNavigate()
  const location = useLocation()
  const sessionsOpen = useStore($nvSessionsOpen)

  // Neovarch has no Hermes-style always-on session sidebar: the list is the
  // rail-opened panel, so the inherited sidebar pane is folded on launch.
  useEffect(() => {
    setSidebarOpen(false)
  }, [])
  const { renderedMode, setMode } = useTheme()
  const path = location.pathname
  const page = (to: string) => () => navigateToWorkspacePage(navigate, to)
  const icon = 'size-[1.05rem]'

  const top: RailItem[] = [
    {
      icon: <Plus className={icon} />,
      id: 'new-chat',
      label: NV_COPY.newChat,
      onSelect: () => {
        navigate('/')
        requestFreshSession()
      }
    },
    {
      active: sessionsOpen,
      icon: <MessageSquareText className={icon} />,
      id: 'sessions',
      label: NV_COPY.sessions,
      onSelect: () => toggleNvSessions()
    }
  ]

  const middle: RailItem[] = [
    {
      active: path.startsWith(CAPABILITIES_ROUTE),
      icon: <Zap className={icon} />,
      id: 'skills',
      label: NV_COPY.skills,
      onSelect: page(CAPABILITIES_ROUTE)
    },
    {
      active: path.startsWith('/kanban'),
      icon: <LayoutDashboard className={icon} />,
      id: 'kanban',
      label: NV_COPY.kanban,
      onSelect: () => void openNeovarchKanban(navigate)
    },
    {
      active: path.startsWith(MESSAGING_ROUTE),
      icon: <MessageCircle className={icon} />,
      id: 'messaging',
      label: NV_COPY.messaging,
      onSelect: page(MESSAGING_ROUTE)
    },
    {
      active: path.startsWith(ARTIFACTS_ROUTE),
      icon: <FileText className={icon} />,
      id: 'artifacts',
      label: NV_COPY.artifacts,
      onSelect: page(ARTIFACTS_ROUTE)
    },
    {
      active: path.startsWith(CRON_ROUTE),
      icon: <Clock className={icon} />,
      id: 'cron',
      label: NV_COPY.cron,
      onSelect: page(CRON_ROUTE)
    }
  ]

  const isDark = renderedMode === 'dark'

  const bottom: RailItem[] = [
    {
      icon: <QrCode className={icon} />,
      id: 'pair-phone',
      label: NV_COPY.pairPhone,
      onSelect: () => navigate('/settings?tab=remote')
    },
    {
      icon: isDark ? <Sun className={icon} /> : <Moon className={icon} />,
      id: 'theme',
      label: isDark ? NV_COPY.toLight : NV_COPY.toDark,
      onSelect: () => setMode(isDark ? 'light' : 'dark')
    },
    {
      active: path.startsWith('/settings'),
      icon: <Settings className={icon} />,
      id: 'settings',
      label: NV_COPY.settings,
      onSelect: () => navigate('/settings')
    }
  ]

  return (
    <nav aria-label="Neovarch" className="nv-rail" data-slot="nv-rail" style={{ width: NV_RAIL_WIDTH }}>
      <Tip label={NV_COPY.home} side="right">
        <button
          aria-label={NV_COPY.home}
          className="nv-rail-logo"
          data-nv-rail="home"
          onClick={() => navigate('/')}
          type="button"
        >
          <HaloMark className="size-5" />
        </button>
      </Tip>
      <div className="nv-rail-group">
        {top.map(item => (
          <RailButton item={item} key={item.id} />
        ))}
      </div>
      <span aria-hidden="true" className="nv-rail-rule" />
      <div className="nv-rail-group">
        {middle.map(item => (
          <RailButton item={item} key={item.id} />
        ))}
      </div>
      <div className="nv-rail-group mt-auto">
        {bottom.map(item => (
          <RailButton item={item} key={item.id} />
        ))}
      </div>
    </nav>
  )
}

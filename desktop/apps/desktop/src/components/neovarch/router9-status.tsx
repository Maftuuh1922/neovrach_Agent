import { useStore } from '@nanostores/react'
import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { DropdownMenuItem, dropdownMenuRow, DropdownMenuSeparator } from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { AlertTriangle, CheckCircle2, Copy, ExternalLink, KeyRound, Loader2, Network, Play, RefreshCw } from '@/lib/icons'
import { cn } from '@/lib/utils'
import {
  $routerBusy,
  $routerError,
  $routerStatus,
  INSTALL_COMMAND,
  openRouterDashboard,
  refreshRouterStatus,
  routerPrimaryAction,
  routerStateLabel,
  type RouterStatus,
  saveRouterApiKey,
  setRouterAutostart,
  startRouter,
  stopRouter
} from '@/store/router9'

import { registerRouter9RowBadge } from './router9-row-badge'

registerRouter9RowBadge()

// 9Router status for Settings ▸ Model (read-only about the model: the ONE model
// selector is the composer picker) and a one-line row on top of that picker
// when 9Router needs a step. Indonesian labels; colours come from the theme
// tokens so light mode keeps its contrast on the glass surfaces.

const CAPTION = 'text-[length:var(--conversation-caption-font-size)] text-(--ui-text-tertiary)'
const MONO = 'font-mono text-[0.6875rem] leading-4 break-all text-(--ui-text-secondary)'

function copyText(text: string): void {
  void navigator.clipboard?.writeText(text).catch(() => undefined)
}

function tone(status: null | RouterStatus): 'bad' | 'ok' | 'warn' {
  if (status?.setup.ready) {
    return 'ok'
  }

  return status?.state === 'error' || status?.state === 'not_installed' ? 'bad' : 'warn'
}

function StateBadge({ status }: { status: null | RouterStatus }) {
  const t = tone(status)

  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[0.6875rem] font-medium',
        t === 'ok' && 'border-(--nv-line) text-(--nv-text-2)',
        t !== 'ok' && 'border-(--nv-red-text)/50 bg-(--nv-red-wash) text-(--nv-red-text)'
      )}
      data-slot="router9-state"
      data-tone={t}
    >
      {status?.state === 'starting' ? (
        <Loader2 className="size-3 animate-spin" />
      ) : t === 'ok' ? (
        <CheckCircle2 className="size-3" />
      ) : (
        <AlertTriangle className="size-3" />
      )}
      {routerStateLabel(status)}
    </span>
  )
}

function PrimaryAction({ status, compact = false }: { compact?: boolean; status: null | RouterStatus }) {
  const busy = useStore($routerBusy)
  const action = routerPrimaryAction(status)

  if (!action) {
    return null
  }

  if (action.kind === 'start') {
    return (
      <Button disabled={busy !== ''} onClick={() => void startRouter()} size={compact ? 'xs' : 'sm'} type="button">
        {busy === 'start' ? <Loader2 className="size-3.5 animate-spin" /> : <Play className="size-3.5" />}
        {busy === 'start' ? 'Menyalakan\u2026' : action.label}
      </Button>
    )
  }

  if (action.kind === 'copy') {
    return (
      <Button onClick={() => copyText(INSTALL_COMMAND)} size={compact ? 'xs' : 'sm'} type="button" variant="outline">
        <Copy className="size-3.5" />
        {action.label}
      </Button>
    )
  }

  return (
    <Button onClick={() => openRouterDashboard(status)} size={compact ? 'xs' : 'sm'} type="button">
      <ExternalLink className="size-3.5" />
      {action.label}
    </Button>
  )
}

/** Settings ▸ Model: the 9Router card. */
export function Router9Card() {
  const status = useStore($routerStatus)
  const busy = useStore($routerBusy)
  const error = useStore($routerError)
  const [key, setKey] = useState('')
  const needsKey = status?.setup.action === 'api_key'

  return (
    <section
      className="nv-glass-tile-panel mb-6 rounded-(--nv-r-panel,16px) border border-(--nv-line) p-4"
      data-slot="router9-card"
    >
      <div className="flex flex-wrap items-center gap-2">
        <Network className="size-4 text-(--ui-text-secondary)" />
        <h3 className="text-sm font-semibold text-foreground">9Router</h3>
        <StateBadge status={status} />
        {status?.version && <span className={CAPTION}>v{status.version}</span>}
        <div className="ml-auto flex items-center gap-1.5">
          <Button
            aria-label="Periksa ulang 9Router"
            onClick={() => void refreshRouterStatus()}
            size="icon-xs"
            title="Periksa ulang"
            type="button"
            variant="ghost"
          >
            <RefreshCw className="size-3.5" />
          </Button>
          {status?.managed && status.running && (
            <Button disabled={busy !== ''} onClick={() => void stopRouter()} size="sm" type="button" variant="outline">
              Hentikan
            </Button>
          )}
          {status?.running && (
            <Button onClick={() => openRouterDashboard(status)} size="sm" type="button" variant="outline">
              <ExternalLink className="size-3.5" />
              Buka dashboard 9Router
            </Button>
          )}
          {!status?.setup.ready && <PrimaryAction status={status} />}
        </div>
      </div>

      <p className={cn('mt-2', CAPTION)}>
        Penyedia model bawaan Neovarch. Model gratis OpenCode Free langsung bisa dipakai tanpa API key. Pilih
        model dari pemilih model di kolom chat; setiap agen bisa memakai modelnya sendiri.
      </p>

      {status && (
        <div className="mt-3 grid gap-1">
          <div className={MONO}>{status.base_url}</div>
          {status.setup.message && !status.setup.ready && (
            <p className="text-xs text-(--nv-text-2)" data-slot="router9-message">
              {status.setup.message}
            </p>
          )}
          {status.setup.action === 'install' && (
            <code className={cn(MONO, 'w-fit rounded-(--nv-r-control,12px) border border-(--nv-line) px-2 py-1')}>
              {INSTALL_COMMAND}
            </code>
          )}
        </div>
      )}

      {needsKey && (
        <form
          className="mt-3 flex flex-wrap items-center gap-2"
          onSubmit={event => {
            event.preventDefault()

            if (key.trim()) {
              void saveRouterApiKey(key).then(() => setKey(''))
            }
          }}
        >
          <KeyRound className="size-4 text-(--ui-text-tertiary)" />
          <Input
            aria-label="API key 9Router"
            autoComplete="off"
            className="h-8 max-w-80 flex-1 font-mono text-xs"
            onChange={event => setKey(event.target.value)}
            placeholder="Tempel API key dari dashboard 9Router"
            type="password"
            value={key}
          />
          <Button disabled={!key.trim() || busy !== ''} size="sm" type="submit">
            Simpan
          </Button>
        </form>
      )}

      {status && (
        <label className={cn('mt-3 flex w-fit cursor-pointer items-center gap-2', CAPTION)}>
          <input
            checked={status.autostart}
            className="accent-(--ui-accent)"
            disabled={busy !== ''}
            onChange={event => void setRouterAutostart(event.target.checked)}
            type="checkbox"
          />
          Nyalakan 9Router otomatis saat Neovarch berjalan
        </label>
      )}

      {error && (
        <p className="mt-2 text-xs text-(--nv-red-text)" role="alert">
          {error}
        </p>
      )}
    </section>
  )
}

/**
 * On top of the composer's model menu (the single model selector), only while
 * 9Router needs a step: the message and its one-tap action.
 */
export function Router9MenuRow() {
  const status = useStore($routerStatus)
  const action = routerPrimaryAction(status)

  if (!status || status.setup.ready || !action) {
    return null
  }

  const onSelect = () => {
    if (action.kind === 'start') {
      void startRouter()
    } else if (action.kind === 'copy') {
      copyText(INSTALL_COMMAND)
    } else {
      openRouterDashboard(status)
    }
  }

  return (
    <>
      <DropdownMenuItem
        className={cn(dropdownMenuRow, 'items-start gap-2 py-1.5')}
        data-slot="model-menu-router9"
        onSelect={onSelect}
      >
        <AlertTriangle className="mt-0.5 size-3.5 shrink-0 text-(--nv-red-text)" />
        <span className="grid min-w-0 gap-0.5">
          <span className="text-xs font-medium text-foreground">
            9Router: {routerStateLabel(status)} {'\u2014'} {action.label}
          </span>
          {status.setup.message && (
            <span className="line-clamp-2 text-[0.6875rem] text-(--ui-text-tertiary)">{status.setup.message}</span>
          )}
        </span>
      </DropdownMenuItem>
      <DropdownMenuSeparator />
    </>
  )
}

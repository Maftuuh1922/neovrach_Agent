import { useEffect, useRef, useState } from 'react'

import { socialT as t } from '@/i18n/neovarch-social'

import { canvasToPng, currentShareTheme, drawShareCard, loadImage, SHARE_SIZES, type ShareFormat } from './share-card'
import type { SocialProfile } from './social-store'

/** Save the PNG through a download (Electron saves it like any download). */
export function downloadPng(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 2000)
}

export async function copyPng(blob: Blob): Promise<void> {
  const Item = (window as unknown as { ClipboardItem?: typeof ClipboardItem }).ClipboardItem

  if (!Item || !navigator.clipboard?.write) {
    throw new Error('Papan klip gambar tidak tersedia')
  }

  await navigator.clipboard.write([new Item({ 'image/png': blob })])
}

/** "Bagikan profil": live preview (moving sheen unless reduced motion) + PNG export. */
export function ShareProfileDialog({
  gistUrl,
  onClose,
  profile
}: {
  gistUrl?: null | string
  onClose: () => void
  profile: SocialProfile
}) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [format, setFormat] = useState<ShareFormat>('story')
  const [avatar, setAvatar] = useState<HTMLImageElement | null>(null)
  const [note, setNote] = useState<null | string>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let alive = true

    if (profile.avatar_url) {
      void loadImage(profile.avatar_url).then(img => alive && setAvatar(img))
    }

    return () => {
      alive = false
    }
  }, [profile.avatar_url])

  useEffect(() => {
    const el = canvas.current

    if (!el) {
      return
    }

    const theme = currentShareTheme()
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    let frame = 0
    const t0 = performance.now()

    const paint = (now: number) => {
      const sheen = reduce ? 0.32 : ((now - t0) / 3600) % 1
      drawShareCard(el, profile, { avatar, format, sheen, theme })

      if (!reduce) {
        frame = window.setTimeout(() => requestAnimationFrame(paint), 66)
      }
    }

    paint(t0)

    return () => window.clearTimeout(frame)
  }, [profile, format, avatar])

  async function exportPng(): Promise<Blob> {
    // a still frame (sheen at rest) on a fresh canvas
    const c = document.createElement('canvas')
    drawShareCard(c, profile, { avatar, format, theme: currentShareTheme() })

    return canvasToPng(c)
  }

  async function run(action: (blob: Blob) => Promise<void> | void, done: string) {
    setBusy(true)
    setNote(null)

    try {
      await action(await exportPng())
      setNote(done)
    } catch (e) {
      setNote(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const size = SHARE_SIZES[format]

  return (
    <div aria-label={t('shareTitle')} aria-modal="true" className="nv-share-backdrop" data-slot="nv-share" role="dialog">
      <div className="nv-share-dialog">
        <header className="nv-social-row nv-share-head">
          <h2 className="nv-social-h2">{t('shareTitle')}</h2>
          <div aria-label={t('shareFormat')} className="nv-share-seg" role="radiogroup">
            {(['story', 'square'] as const).map(f => (
              <button
                aria-checked={format === f}
                className="nv-share-seg-btn"
                data-active={format === f}
                key={f}
                onClick={() => setFormat(f)}
                role="radio"
                type="button"
              >
                {f === 'story' ? t('shareStory') : t('shareSquare')}
              </button>
            ))}
          </div>
        </header>
        <div className="nv-share-preview" data-format={format}>
          <canvas
            aria-label={t('sharePreview')}
            className="nv-share-canvas"
            data-height={size.height}
            data-width={size.width}
            ref={canvas}
          />
        </div>
        <p className="nv-social-muted">{t('shareSize', { h: size.height, w: size.width })}</p>
        <div className="nv-social-row">
          <button
            className="nv-social-btn nv-social-btn-primary"
            disabled={busy}
            onClick={() => void run(b => downloadPng(b, `neovarch-profil-${format}.png`), t('shareSaved'))}
            type="button"
          >
            {t('shareSave')}
          </button>
          <button
            className="nv-social-btn"
            disabled={busy}
            onClick={() => void run(copyPng, t('shareCopied'))}
            type="button"
          >
            {t('shareCopy')}
          </button>
          {gistUrl && (
            <button
              className="nv-social-btn"
              onClick={() => void navigator.clipboard?.writeText(gistUrl).then(() => setNote(t('shareLinkCopied')))}
              type="button"
            >
              {t('shareLink')}
            </button>
          )}
          <button className="nv-social-btn nv-social-btn-ghost" onClick={onClose} type="button">
            {t('cancel')}
          </button>
        </div>
        {note && <p className="nv-social-muted" data-slot="nv-share-note">{note}</p>}
      </div>
    </div>
  )
}

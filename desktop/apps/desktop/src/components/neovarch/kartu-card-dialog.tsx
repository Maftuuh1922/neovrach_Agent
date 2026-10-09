// "Bagikan kartu" on the Kantor page: preview the Kartu Neovarch, pick a
// style and format, then Simpan PNG / Salin gambar / open X, Facebook or
// WhatsApp Web with the landing link.
import { useStore } from '@nanostores/react'
import { useEffect, useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { openExternalLink } from '@/lib/external-link'

import { $nvAppearance, DEFAULT_ACCENT } from './appearance'
import { $office } from './office-store'
import {
  captureOffice3D,
  NEOVARCH_LANDING_URL,
  renderShareCardPng,
  SHARE_CARD_STYLES,
  type ShareCardFormat,
  type ShareCardStyle,
  shareLinks,
  statsFromOffice
} from './kartu-card'

const NAME_KEY = 'nv.shareCard.name'
const HANDLE_KEY = 'nv.shareCard.handle'
const SHARE_TEXT = 'Kantor AI-ku di Neovarch.'

function readPref(key: string): string {
  try {
    return window.localStorage.getItem(key) ?? ''
  } catch {
    return ''
  }
}

function writePref(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value)
  } catch {
    // private mode / storage off: the card still works
  }
}

export function KartuCardButton() {
  const [open, setOpen] = useState(false)
  const [shot, setShot] = useState<null | string>(null)

  const start = async () => {
    setShot(await captureOffice3D())
    setOpen(true)
  }

  return (
    <>
      <button className="nv-office-open" data-slot="nv-kartu-open" onClick={() => void start()} type="button">
        Bagikan kartu
      </button>
      <KartuCardDialog officeShot={shot} onOpenChange={setOpen} open={open} />
    </>
  )
}

export function KartuCardDialog({ officeShot, onOpenChange, open }: { officeShot: null | string; onOpenChange: (open: boolean) => void; open: boolean }) {
  const office = useStore($office)
  const appearance = useStore($nvAppearance)
  const [style, setStyle] = useState<ShareCardStyle>('kaca')
  const [format, setFormat] = useState<ShareCardFormat>('story')
  const [showStats, setShowStats] = useState(true)
  const [name, setName] = useState(() => readPref(NAME_KEY))
  const [handle, setHandle] = useState(() => readPref(HANDLE_KEY))
  const [png, setPng] = useState<Blob | null>(null)
  const [url, setUrl] = useState<null | string>(null)
  const [note, setNote] = useState<null | string>(null)

  const data = useMemo(
    () => ({ handle, link: NEOVARCH_LANDING_URL, name, officeShot, stats: statsFromOffice(office) }),
    [handle, name, officeShot, office]
  )

  useEffect(() => {
    if (!open) {
      return
    }

    let cancelled = false
    renderShareCardPng(data, { accent: appearance?.accent || DEFAULT_ACCENT, format, showOffice: Boolean(officeShot), showStats, style })
      .then(blob => {
        if (!cancelled) {
          setPng(blob)
        }
      })
      .catch(e => !cancelled && setNote(`Kartu gagal dibuat: ${e instanceof Error ? e.message : e}`))

    return () => {
      cancelled = true
    }
  }, [open, data, appearance?.accent, format, showStats, style, officeShot])

  useEffect(() => {
    if (!png) {
      return
    }

    const u = URL.createObjectURL(png)
    setUrl(u)

    return () => URL.revokeObjectURL(u)
  }, [png])

  const save = () => {
    if (!url) {
      return
    }

    const a = document.createElement('a')
    a.href = url
    a.download = `kartu-neovarch-${format}.png`
    a.click()
    setNote('PNG disimpan ke folder Unduhan.')
  }

  const copy = async () => {
    try {
      if (!png || typeof ClipboardItem === 'undefined') {
        throw new Error('papan klip gambar tidak tersedia')
      }

      await navigator.clipboard.write([new ClipboardItem({ 'image/png': png })])
      setNote('Gambar disalin. Tempel di aplikasi mana saja.')
    } catch (e) {
      setNote(`Gagal menyalin: ${e instanceof Error ? e.message : e}`)
    }
  }

  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent className="nv-kartu-dialog" data-slot="nv-kartu-dialog">
        <DialogHeader>
          <DialogTitle>Kartu Neovarch</DialogTitle>
          <DialogDescription>Pamerkan kantor AI-mu. Kartu tidak memuat token, alamat PC, atau path file.</DialogDescription>
        </DialogHeader>

        <div className="nv-kartu-body">
          <div className="nv-kartu-preview" data-format={format}>
            {url ? <img alt="Pratinjau Kartu Neovarch" data-slot="nv-kartu-preview" src={url} /> : <p>Membuat kartu…</p>}
          </div>

          <div className="nv-kartu-controls">
            <div aria-label="Gaya kartu" className="nv-office-view-toggle" role="group">
              {SHARE_CARD_STYLES.map(s => (
                <button aria-pressed={style === s.value} key={s.value} onClick={() => setStyle(s.value)} type="button">
                  {s.label}
                </button>
              ))}
            </div>
            <div aria-label="Format" className="nv-office-view-toggle" role="group">
              <button aria-pressed={format === 'story'} onClick={() => setFormat('story')} type="button">
                Story 9:16
              </button>
              <button aria-pressed={format === 'feed'} onClick={() => setFormat('feed')} type="button">
                Feed 1:1
              </button>
            </div>
            <label className="nv-kartu-field">
              <span>Nama di kartu</span>
              <input
                maxLength={32}
                onChange={e => {
                  setName(e.target.value)
                  writePref(NAME_KEY, e.target.value)
                }}
                placeholder="Kantor AI-ku"
                value={name}
              />
            </label>
            <label className="nv-kartu-field">
              <span>GitHub (opsional)</span>
              <input
                maxLength={40}
                onChange={e => {
                  setHandle(e.target.value)
                  writePref(HANDLE_KEY, e.target.value)
                }}
                placeholder="@username"
                value={handle}
              />
            </label>
            <label className="nv-kartu-check">
              <input checked={showStats} onChange={e => setShowStats(e.target.checked)} type="checkbox" /> Tampilkan statistik
            </label>
            {!officeShot && <p className="nv-kartu-note">Buka tampilan 3D untuk menyertakan cuplikan kantor.</p>}

            <div className="nv-kartu-actions">
              <Button data-slot="nv-kartu-save" disabled={!url} onClick={save} size="sm">
                Simpan PNG
              </Button>
              <Button data-slot="nv-kartu-copy" disabled={!png} onClick={() => void copy()} size="sm" variant="secondary">
                Salin gambar
              </Button>
            </div>
            <div className="nv-kartu-actions">
              {shareLinks(NEOVARCH_LANDING_URL, SHARE_TEXT).map(l => (
                <Button key={l.label} onClick={() => openExternalLink(l.url)} size="sm" variant="outline">
                  {l.label}
                </Button>
              ))}
            </div>
            {note && (
              <p className="nv-kartu-note" role="status">
                {note}
              </p>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

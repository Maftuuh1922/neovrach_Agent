import { useStore } from '@nanostores/react'
import { atom } from 'nanostores'
import { useEffect, useRef, useState } from 'react'

import { X } from '@/lib/icons'

/** Path of the document shown in the preview overlay (null = closed). */
export const $nvDocPreview = atom<null | string>(null)

const PREVIEWABLE = /\.(pdf|docx)$/i

export function isPreviewableDocument(path: string): boolean {
  return PREVIEWABLE.test(path.split('?')[0] ?? '')
}

export function openDocPreview(path: string): void {
  $nvDocPreview.set(path)
}

// Any part of the app (chat links, plugins) can ask for a preview without
// importing this module: window.dispatchEvent(new CustomEvent('neovarch:preview-doc', { detail: { path } })).
if (typeof window !== 'undefined') {
  window.addEventListener('neovarch:preview-doc', event => {
    const path = (event as CustomEvent<{ path?: string }>).detail?.path

    if (path && isPreviewableDocument(path)) {
      openDocPreview(path)
    }
  })
}

function dataUrlToBytes(dataUrl: string): ArrayBuffer {
  const b64 = dataUrl.slice(dataUrl.indexOf(',') + 1)
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)

  for (let i = 0; i < bin.length; i++) {
    out[i] = bin.charCodeAt(i)
  }

  return out.buffer
}

async function readBytes(path: string): Promise<ArrayBuffer> {
  const local = path.replace(/^file:\/\//, '')
  const res = await window.hermesDesktop?.readFileDataUrl?.(decodeURIComponent(local))

  if (typeof res === 'string') {
    return dataUrlToBytes(res)
  }

  throw new Error(res && 'error' in res ? String(res.error) : 'File tidak bisa dibaca')
}

async function renderPdf(bytes: ArrayBuffer, host: HTMLElement): Promise<number> {
  const pdfjs = await import('pdfjs-dist')
  const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
  pdfjs.GlobalWorkerOptions.workerSrc = worker.default
  const doc = await pdfjs.getDocument({ data: new Uint8Array(bytes) }).promise
  const width = Math.min(host.clientWidth - 32, 900)

  for (let n = 1; n <= doc.numPages; n++) {
    const page = await doc.getPage(n)
    const base = page.getViewport({ scale: 1 })
    const viewport = page.getViewport({ scale: (width / base.width) * (window.devicePixelRatio || 1) })
    const canvas = document.createElement('canvas')
    canvas.width = viewport.width
    canvas.height = viewport.height
    canvas.style.width = `${width}px`
    canvas.className = 'nv-doc-page'
    canvas.dataset.nvPdfPage = String(n)
    host.appendChild(canvas)
    await page.render({ canvasContext: canvas.getContext('2d')!, viewport }).promise
  }

  return doc.numPages
}

async function renderDocx(bytes: ArrayBuffer, host: HTMLElement): Promise<number> {
  const { renderAsync } = await import('docx-preview')
  await renderAsync(bytes, host, undefined, {
    className: 'nv-docx',
    inWrapper: true,
    ignoreWidth: false,
    ignoreHeight: false,
    breakPages: true,
    renderHeaders: true,
    renderFooters: true
  })

  return host.querySelectorAll('section.nv-docx').length
}

/** Overlay that shows a PDF (pdf.js) or DOCX (docx-preview) the way it prints. */
export function NeovarchDocPreview() {
  const path = useStore($nvDocPreview)
  const host = useRef<HTMLDivElement>(null)
  const [state, setState] = useState<{ error?: string; loading: boolean; pages?: number }>({ loading: false })

  useEffect(() => {
    const el = host.current

    if (!path || !el) {
      return
    }

    let alive = true
    el.replaceChildren()
    setState({ loading: true })
    void (async () => {
      try {
        const bytes = await readBytes(path)
        const pages = /\.pdf$/i.test(path) ? await renderPdf(bytes, el) : await renderDocx(bytes, el)

        if (alive) {
          setState({ loading: false, pages })
        }
      } catch (e) {
        if (alive) {
          setState({ loading: false, error: e instanceof Error ? e.message : String(e) })
        }
      }
    })()

    return () => {
      alive = false
    }
  }, [path])

  useEffect(() => {
    if (!path) {
      return
    }

    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && $nvDocPreview.set(null)
    window.addEventListener('keydown', onKey)

    return () => window.removeEventListener('keydown', onKey)
  }, [path])

  if (!path) {
    return null
  }

  const name = path.split(/[\\/]/).pop()

  return (
    <div className="nv-doc-preview" data-nv-doc-preview={/\.pdf$/i.test(path) ? 'pdf' : 'docx'} role="dialog">
      <div className="nv-doc-preview-bar">
        <span className="nv-doc-preview-name">{name}</span>
        <span className="nv-doc-preview-meta" data-nv-doc-pages={state.pages ?? ''}>
          {state.loading ? 'Memuat…' : state.error ? 'Gagal' : `${state.pages ?? 0} halaman`}
        </span>
        <button
          className="nv-doc-preview-open"
          onClick={() => void window.hermesDesktop?.openExternal?.(`file://${path.replace(/^file:\/\//, '')}`)}
          type="button"
        >
          Buka di aplikasi
        </button>
        <button aria-label="Tutup" className="nv-doc-preview-close" onClick={() => $nvDocPreview.set(null)} type="button">
          <X className="size-4" />
        </button>
      </div>
      {state.error && <p className="nv-doc-preview-error">{state.error}</p>}
      <div className="nv-doc-preview-body" ref={host} />
    </div>
  )
}

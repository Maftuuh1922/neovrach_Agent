// Kartu Neovarch (desktop): the same shareable brag card as the phone, drawn
// on a 2D canvas. Story 1080×1920 or Feed 1080×1080, styles Kaca / Gelap /
// Warna-warni, stats from the Office snapshot, an optional Kantor 3D
// snapshot, a QR to the landing page and "Dibuat dengan Neovarch".
//
// The layout is a pure list of draw ops (tested without a real canvas);
// paintShareCard() replays it on a CanvasRenderingContext2D. No gradients.
import QRCode from 'qrcode'

import type { OfficeSnapshot } from './office-store'

export const NEOVARCH_LANDING_URL = 'https://maftuuh1922.github.io/neorachAgent_lp/'

export type ShareCardStyle = 'gelap' | 'kaca' | 'warna'
export type ShareCardFormat = 'feed' | 'story'

export const SHARE_CARD_STYLES: { label: string; value: ShareCardStyle }[] = [
  { label: 'Kaca', value: 'kaca' },
  { label: 'Gelap', value: 'gelap' },
  { label: 'Warna-warni', value: 'warna' }
]

export const SHARE_CARD_SIZE: Record<ShareCardFormat, { h: number; w: number }> = {
  feed: { h: 1080, w: 1080 },
  story: { h: 1920, w: 1080 }
}

export interface ShareCardStats {
  agentsActive?: number
  agentsTotal?: number
  messages?: number
  model?: string
  tasksDone?: number
}

export interface ShareCardData {
  /** GitHub handle without "@" (optional). */
  handle?: string
  link: string
  /** Display name typed by the user (optional). */
  name: string
  /** Kantor 3D snapshot (data URL), when one was captured. */
  officeShot?: null | string
  stats: ShareCardStats
}

export interface ShareCardOptions {
  accent: string
  format: ShareCardFormat
  showOffice: boolean
  showStats: boolean
  style: ShareCardStyle
}

// ------------------------------------------------------------- privacy --

const SECRET_RE = /(sk-|ghp_|gho_|github_pat_|xox[abp]-|AKIA|AIza|Bearer\s)/i
const LONG_TOKEN_RE = /[A-Za-z0-9_-]{28,}/
const PATH_RE = /(^~|^\/|[A-Za-z]:\\|\\\\|\/home\/|\/Users\/|\.neovarch)/
const ADDRESS_RE = /(https?:\/\/|wss?:\/\/|\b\d{1,3}(\.\d{1,3}){3}\b|localhost|:\d{2,5}\b)/i

/** A short display label, or '' when it looks like a secret, a path or an address. */
export function safeLabel(raw: null | string | undefined, max = 32): string {
  const s = (raw ?? '').replace(/\s+/g, ' ').trim()

  if (!s || SECRET_RE.test(s) || LONG_TOKEN_RE.test(s) || PATH_RE.test(s) || ADDRESS_RE.test(s)) {
    return ''
  }

  return s.length > max ? `${s.slice(0, max - 1)}…` : s
}

export function safeHandle(raw: null | string | undefined): string {
  const s = (raw ?? '').trim().replace(/^@/, '')

  return /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/.test(s) ? s : ''
}

/** "openrouter/anthropic/claude-sonnet-4.5:free" -> "claude-sonnet-4.5"; paths / endpoints dropped. */
export function safeModelName(raw: null | string | undefined): string {
  const s = (raw ?? '').trim()

  if (!s || PATH_RE.test(s) || ADDRESS_RE.test(s) || SECRET_RE.test(s)) {
    return ''
  }

  const last = (s.split('/').pop() ?? '').split(':')[0].trim()

  if (!last || /[A-Za-z0-9]{32,}/.test(last)) {
    return ''
  }

  return last.length > 26 ? `${last.slice(0, 25)}…` : last
}

/** Card stats from the live Office snapshot (no host, paths or vault info). */
export function statsFromOffice(office: null | OfficeSnapshot | undefined, model?: null | string): ShareCardStats {
  if (!office) {
    return { model: safeModelName(model) || undefined }
  }

  const done = office.kanban?.done ?? office.kanban?.selesai
  const messages = office.agents.reduce((sum, a) => sum + (a.message_count || 0), 0)
  const fromAgents = office.agents.find(a => a.model)?.model

  return {
    agentsActive: office.counts?.working ?? office.agents.filter(a => a.status === 'working').length,
    agentsTotal: office.counts?.total ?? office.agents.length,
    messages: messages || undefined,
    model: safeModelName(model || fromAgents) || undefined,
    tasksDone: typeof done === 'number' ? done : undefined
  }
}

// -------------------------------------------------------------- colours --

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  const full = h.length === 3 ? h.replace(/(.)/g, '$1$1') : h.padEnd(6, '0').slice(0, 6)
  const n = parseInt(full, 16)

  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

function rgbToHex([r, g, b]: [number, number, number]): string {
  return `#${[r, g, b].map(v => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('')}`
}

export function mixHex(a: string, b: string, t: number): string {
  const x = hexToRgb(a)
  const y = hexToRgb(b)

  return rgbToHex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t])
}

function luminance(hex: string): number {
  const [r, g, b] = hexToRgb(hex).map(v => {
    const c = v / 255

    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })

  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

export function contrast(a: string, b: string): number {
  const la = luminance(a) + 0.05
  const lb = luminance(b) + 0.05

  return la > lb ? la / lb : lb / la
}

function alpha(hex: string, a: number): string {
  const [r, g, b] = hexToRgb(hex)

  return `rgba(${r}, ${g}, ${b}, ${a})`
}

export interface CardColors {
  accent: string
  cell: string
  ground: string
  line: string
  muted: string
  panel: string
  text: string
}

export function cardColors(style: ShareCardStyle, accentHex: string): CardColors {
  const accent = /^#?[0-9a-f]{3,6}$/i.test(accentHex) ? (accentHex.startsWith('#') ? accentHex : `#${accentHex}`) : '#EE1C1C'

  if (style === 'gelap' || style === 'kaca') {
    let a = accent

    for (let i = 0; i < 5 && contrast(a, '#141417') < 3.2; i++) {
      a = mixHex(a, '#ffffff', 0.22)
    }

    return style === 'gelap'
      ? { accent: a, cell: '#1c1c21', ground: '#09090b', line: '#2a2a30', muted: '#a8a29e', panel: '#141417', text: '#f4f2ed' }
      : {
          accent: a,
          cell: 'rgba(244, 242, 237, 0.07)',
          ground: mixHex(accent, '#0d0606', 0.86),
          line: 'rgba(244, 242, 237, 0.14)',
          muted: '#c9c1ba',
          panel: alpha(mixHex(accent, '#140808', 0.85), 0.62),
          text: '#f4f2ed'
        }
  }

  const ink = contrast(accent, '#111111') > contrast(accent, '#ffffff') ? '#111111' : '#ffffff'
  let ground = accent

  for (let i = 0; i < 8 && contrast(ground, ink) < 4.6; i++) {
    ground = mixHex(ground, ink === '#111111' ? '#ffffff' : '#000000', 0.08)
  }

  return {
    accent: ink,
    cell: alpha(ink, 0.1),
    ground,
    line: alpha(ink, 0.22),
    muted: alpha(ink, 0.74),
    panel: alpha(ink, ink === '#111111' ? 0.08 : 0.14),
    text: ink
  }
}

// --------------------------------------------------------------- layout --

export type DrawOp =
  | { align?: 'center' | 'left' | 'right'; color: string; font: string; kind: 'text'; maxWidth?: number; text: string; x: number; y: number }
  | { fill: string; h: number; kind: 'rect'; r: number; stroke?: string; w: number; x: number; y: number }
  | { fill: string; kind: 'circle'; r: number; stroke?: string; x: number; y: number }
  | { h: number; kind: 'image'; r: number; src: string; w: number; x: number; y: number }
  | { kind: 'qr'; modules: boolean[][]; size: number; x: number; y: number }

export function qrModules(text: string): boolean[][] {
  const qr = QRCode.create(text, { errorCorrectionLevel: 'M' })
  const n = qr.modules.size
  const out: boolean[][] = []

  for (let r = 0; r < n; r++) {
    const row: boolean[] = []

    for (let c = 0; c < n; c++) {
      row.push(Boolean(qr.modules.get(r, c)))
    }

    out.push(row)
  }

  return out
}

const SANS = 'Inter, "Segoe UI", system-ui, sans-serif'
const MONO = '"JetBrains Mono", ui-monospace, monospace'

function compactNum(n: number): string {
  if (n >= 10_000) {
    return `${Math.round(n / 1000)}rb`
  }

  if (n >= 1000) {
    return `${(n / 1000).toFixed(1).replace('.', ',')}rb`
  }

  return String(n)
}

/** Every op the card draws, in pixel units of the export size. */
export function layoutShareCard(data: ShareCardData, opts: ShareCardOptions): DrawOp[] {
  const { h: H, w: W } = SHARE_CARD_SIZE[opts.format]
  const story = opts.format === 'story'
  const c = cardColors(opts.style, opts.accent)
  const ops: DrawOp[] = []
  const name = safeLabel(data.name) || 'Kantor AI-ku'
  const handle = safeHandle(data.handle)
  const s = data.stats
  const stats: [string, string][] = []

  if (opts.showStats) {
    if (s.agentsActive !== undefined) {
      stats.push([`${s.agentsActive}${s.agentsTotal !== undefined ? `/${s.agentsTotal}` : ''}`, 'agen aktif'])
    }

    if (s.tasksDone !== undefined) {
      stats.push([String(s.tasksDone), 'tugas selesai'])
    }

    if (s.messages !== undefined) {
      stats.push([compactNum(s.messages), 'pesan'])
    }
  }

  ops.push({ fill: c.ground, h: H, kind: 'rect', r: 0, w: W, x: 0, y: 0 })

  if (opts.style === 'kaca') {
    ops.push({ fill: alpha(c.accent, 0.28), kind: 'circle', r: W * 0.45, x: W * 0.15, y: H * 0.15 })
    ops.push({ fill: alpha(c.accent, 0.2), kind: 'circle', r: W * 0.38, x: W * 0.95, y: H * 0.65 })
  }

  if (opts.style === 'gelap') {
    for (let x = 0; x <= W; x += 72) {
      ops.push({ fill: alpha('#2a2a30', 0.5), h: H, kind: 'rect', r: 0, w: 1.5, x, y: 0 })
    }
  }

  if (opts.style === 'warna') {
    let seed = 7

    const rnd = () => {
      seed = (seed * 9301 + 49297) % 233280

      return seed / 233280
    }

    const marks = ['✦', '★', '</>', '⚡', '♥', '◆']

    for (let i = 0; i < (story ? 34 : 20); i++) {
      ops.push({
        color: alpha(c.text, 0.13),
        font: `600 ${Math.round(40 + rnd() * 40)}px ${SANS}`,
        kind: 'text',
        text: marks[i % marks.length],
        x: rnd() * W,
        y: rnd() * H
      })
    }
  }

  const m = story ? 54 : 42
  const top = story ? 120 : 42
  const pw = W - 2 * m
  const ph = H - top * 2
  const pad = story ? 60 : 48

  ops.push({ fill: c.panel, h: ph, kind: 'rect', r: story ? 84 : 72, stroke: c.line, w: pw, x: m, y: top })

  const x0 = m + pad
  const iw = pw - 2 * pad
  let y = top + pad

  // brand
  ops.push({ color: c.text, font: `600 28px ${MONO}`, kind: 'text', text: 'NEOVARCH AGENT', x: x0, y: y + 24 })
  ops.push({ align: 'right', color: c.muted, font: `500 24px ${MONO}`, kind: 'text', text: 'KARTU', x: x0 + iw, y: y + 24 })
  y += story ? 80 : 60

  // avatar (initial) + name
  const av = story ? 78 : 60
  ops.push({ fill: c.cell, kind: 'circle', r: av, stroke: c.accent, x: x0 + av, y: y + av })
  ops.push({
    align: 'center',
    color: c.text,
    font: `700 ${Math.round(av * 0.9)}px ${SANS}`,
    kind: 'text',
    text: name.slice(0, 1).toUpperCase(),
    x: x0 + av,
    y: y + av * 1.32
  })
  ops.push({
    color: c.text,
    font: `700 ${story ? 72 : 58}px ${SANS}`,
    kind: 'text',
    maxWidth: iw - 2 * av - 36,
    text: name,
    x: x0 + 2 * av + 36,
    y: y + av + (handle ? 6 : 24)
  })

  if (handle) {
    ops.push({ color: c.muted, font: `500 ${story ? 32 : 28}px ${MONO}`, kind: 'text', text: `@${handle}`, x: x0 + 2 * av + 36, y: y + av + 52 })
  }

  y += 2 * av + (story ? 48 : 30)

  // Kantor 3D snapshot
  if (opts.showOffice && data.officeShot) {
    const oh = story ? 540 : 250
    ops.push({ h: oh, kind: 'image', r: 54, src: data.officeShot, w: iw, x: x0, y })
    ops.push({ fill: 'rgba(0, 0, 0, 0.55)', h: 52, kind: 'rect', r: 26, w: 420, x: x0 + 24, y: y + oh - 76 })
    const caption = s.agentsTotal !== undefined ? `KANTOR · ${s.agentsActive ?? 0}/${s.agentsTotal} BEKERJA` : 'KANTOR 3D'
    ops.push({ color: '#ffffff', font: `600 24px ${MONO}`, kind: 'text', maxWidth: 380, text: caption, x: x0 + 46, y: y + oh - 41 })
    y += oh + (story ? 36 : 24)
  }

  // stats
  if (stats.length) {
    const gap = 24
    const cw = (iw - gap * (stats.length - 1)) / stats.length
    const ch = story ? 150 : 120

    stats.forEach(([value, label], i) => {
      const cx = x0 + i * (cw + gap)
      ops.push({ fill: c.cell, h: ch, kind: 'rect', r: 36, stroke: c.line, w: cw, x: cx, y })
      ops.push({ color: c.text, font: `700 ${story ? 64 : 52}px ${SANS}`, kind: 'text', maxWidth: cw - 48, text: value, x: cx + 28, y: y + (story ? 80 : 64) })
      ops.push({ color: c.muted, font: `500 ${story ? 26 : 22}px ${MONO}`, kind: 'text', maxWidth: cw - 48, text: label, x: cx + 28, y: y + (story ? 124 : 100) })
    })
    y += ch + 24
  }

  if (opts.showStats && s.model) {
    ops.push({ fill: c.cell, h: 60, kind: 'rect', r: 30, stroke: c.line, w: iw, x: x0, y })
    ops.push({ color: c.text, font: `500 26px ${MONO}`, kind: 'text', maxWidth: iw - 60, text: `model · ${s.model}`, x: x0 + 30, y: y + 40 })
  }

  // QR + call to action, pinned to the bottom of the panel
  const qs = story ? 230 : 190
  const qy = top + ph - pad - qs
  ops.push({ fill: '#ffffff', h: qs, kind: 'rect', r: 36, w: qs, x: x0, y: qy })
  ops.push({ kind: 'qr', modules: qrModules(data.link), size: qs - 32, x: x0 + 16, y: qy + 16 })
  const tx = x0 + qs + 40
  ops.push({ color: c.text, font: `600 ${story ? 46 : 40}px ${SANS}`, kind: 'text', text: 'Coba Neovarch', x: tx, y: qy + (story ? 80 : 66) })
  ops.push({
    color: c.muted,
    font: `400 ${story ? 32 : 28}px ${SANS}`,
    kind: 'text',
    maxWidth: iw - qs - 40,
    text: 'Agen AI di PC-mu, dipantau dari HP.',
    x: tx,
    y: qy + (story ? 130 : 108)
  })
  ops.push({
    color: c.muted,
    font: `500 24px ${MONO}`,
    kind: 'text',
    maxWidth: iw - qs - 40,
    text: data.link.replace(/^https?:\/\//, '').replace(/\/$/, ''),
    x: tx,
    y: qy + (story ? 180 : 150)
  })

  // footer
  ops.push({
    align: 'center',
    color: opts.style === 'warna' ? c.text : alpha('#f4f2ed', 0.8),
    font: `500 ${story ? 30 : 24}px ${MONO}`,
    kind: 'text',
    text: 'Dibuat dengan Neovarch',
    x: W / 2,
    y: story ? H - 50 : H - 12
  })

  return ops
}

// ---------------------------------------------------------------- paint --

export type ImageLoader = (src: string) => Promise<CanvasImageSource | null>

const defaultLoader: ImageLoader = src =>
  new Promise(resolve => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  const rr = Math.max(0, Math.min(r, w / 2, h / 2))
  ctx.beginPath()
  ctx.moveTo(x + rr, y)
  ctx.arcTo(x + w, y, x + w, y + h, rr)
  ctx.arcTo(x + w, y + h, x, y + h, rr)
  ctx.arcTo(x, y + h, x, y, rr)
  ctx.arcTo(x, y, x + w, y, rr)
  ctx.closePath()
}

export async function paintShareCard(ctx: CanvasRenderingContext2D, ops: DrawOp[], load: ImageLoader = defaultLoader): Promise<void> {
  for (const op of ops) {
    switch (op.kind) {
      case 'rect':
        roundRect(ctx, op.x, op.y, op.w, op.h, op.r)
        ctx.fillStyle = op.fill
        ctx.fill()

        if (op.stroke) {
          ctx.strokeStyle = op.stroke
          ctx.lineWidth = 3
          ctx.stroke()
        }

        break

      case 'circle':
        ctx.beginPath()
        ctx.arc(op.x, op.y, op.r, 0, Math.PI * 2)
        ctx.fillStyle = op.fill
        ctx.fill()

        if (op.stroke) {
          ctx.strokeStyle = op.stroke
          ctx.lineWidth = 5
          ctx.stroke()
        }

        break

      case 'text':
        ctx.font = op.font
        ctx.fillStyle = op.color
        ctx.textAlign = op.align ?? 'left'
        ctx.textBaseline = 'alphabetic'
        ctx.fillText(op.text, op.x, op.y, op.maxWidth)

        break

      case 'qr': {
        const n = op.modules.length
        const cell = op.size / n
        ctx.fillStyle = '#111111'

        op.modules.forEach((row, r) =>
          row.forEach((dark, c) => {
            if (dark) {
              ctx.fillRect(op.x + c * cell, op.y + r * cell, cell + 0.5, cell + 0.5)
            }
          })
        )

        break
      }

      case 'image': {
        const img = await load(op.src)

        if (img) {
          ctx.save()
          roundRect(ctx, op.x, op.y, op.w, op.h, op.r)
          ctx.clip()
          // cover-fit, biased upwards (the scene's floor labels sit low)
          const iw = (img as HTMLImageElement).naturalWidth || (img as HTMLCanvasElement).width || op.w
          const ih = (img as HTMLImageElement).naturalHeight || (img as HTMLCanvasElement).height || op.h
          const scale = Math.max(op.w / iw, op.h / ih)
          const dw = iw * scale
          const dh = ih * scale
          ctx.drawImage(img, op.x + (op.w - dw) / 2, op.y + (op.h - dh) * 0.3, dw, dh)
          ctx.restore()
        }

        break
      }
    }
  }
}

/** Render the card to a PNG blob (DOM canvas). */
export async function renderShareCardPng(data: ShareCardData, opts: ShareCardOptions, doc: Document = document): Promise<Blob> {
  const { h, w } = SHARE_CARD_SIZE[opts.format]
  const canvas = doc.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')

  if (!ctx) {
    throw new Error('canvas 2D tidak tersedia')
  }

  await paintShareCard(ctx, layoutShareCard(data, opts))

  return new Promise((resolve, reject) => canvas.toBlob(b => (b ? resolve(b) : reject(new Error('PNG gagal dibuat'))), 'image/png'))
}

/**
 * The live Kantor 3D canvas as a JPEG data URL. Read inside an animation frame
 * (after the scene's own render in that frame) so the WebGL buffer is still
 * there; a blank / tiny result counts as "no snapshot".
 */
export function captureOffice3D(doc: Document = document): Promise<null | string> {
  const canvas = doc.querySelector<HTMLCanvasElement>('[data-slot="nv-office3d-canvas"]')

  if (!canvas || !canvas.width || !canvas.height) {
    return Promise.resolve(null)
  }

  return new Promise(resolve => {
    const read = () => {
      try {
        const url = canvas.toDataURL('image/jpeg', 0.86)
        resolve(url.length > 2000 ? url : null)
      } catch {
        resolve(null)
      }
    }

    if (typeof requestAnimationFrame === 'function') {
      requestAnimationFrame(read)
    } else {
      read()
    }
  })
}

export function shareLinks(link: string, text: string): { label: string; url: string }[] {
  const u = encodeURIComponent(link)
  const t = encodeURIComponent(text)

  return [
    { label: 'X', url: `https://twitter.com/intent/tweet?text=${t}&url=${u}` },
    { label: 'Facebook', url: `https://www.facebook.com/sharer/sharer.php?u=${u}` },
    { label: 'WhatsApp', url: `https://wa.me/?text=${encodeURIComponent(`${text} ${link}`)}` }
  ]
}

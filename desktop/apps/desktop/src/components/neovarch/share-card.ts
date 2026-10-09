/**
 * "Bagikan profil" on the desktop: draws the liquid-glass profile card on a
 * <canvas> at its export size (story 1080×1920 or square 1080×1080):
 * accent glow (or a background image) behind frosted glass with a specular
 * rim and a sheen band, avatar, name/@login, bio, 365-day heatmap, technology
 * logo chips, the "lagi ngoding" status and a small Neovarch mark.
 */
import type { SocialProfile } from './social-store'
import { techIconFor } from './tech-logo'

export type ShareFormat = 'square' | 'story'

export const SHARE_SIZES: Record<ShareFormat, { height: number; width: number }> = {
  square: { height: 1080, width: 1080 },
  story: { height: 1920, width: 1080 }
}

export interface ShareTheme {
  accent: string
  dark: boolean
}

export interface ShareCardOptions {
  avatar?: CanvasImageSource | null
  background?: CanvasImageSource | null
  format: ShareFormat
  /** 0..1 position of the sheen band. */
  sheen?: number
  theme: ShareTheme
}

/** The live accent / brightness of the app (CSS variables set by appearance.tsx). */
export function currentShareTheme(): ShareTheme {
  const root = document.documentElement
  const accent = getComputedStyle(root).getPropertyValue('--nv-red').trim() || '#EE1C1C'

  return { accent, dark: root.dataset.hermesMode !== 'light' }
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  const v = h.length === 3 ? h.replace(/(.)/g, '$1$1') : h.padEnd(6, '0').slice(0, 6)

  return [parseInt(v.slice(0, 2), 16), parseInt(v.slice(2, 4), 16), parseInt(v.slice(4, 6), 16)]
}

export function rgba(hex: string, a: number): string {
  const [r, g, b] = hexToRgb(hex)

  return `rgba(${r}, ${g}, ${b}, ${a})`
}

export function mix(a: string, b: string, t: number): string {
  const x = hexToRgb(a)
  const y = hexToRgb(b)
  const c = x.map((v, i) => Math.round(v + (y[i]! - v) * t))

  return `#${c.map(v => v.toString(16).padStart(2, '0')).join('')}`
}

/** Greedy word wrap with a measure function (testable without a canvas). */
export function wrapLines(text: string, maxWidth: number, measure: (s: string) => number, maxLines = 3): string[] {
  const words = text.split(/\s+/).filter(Boolean)
  const lines: string[] = []
  let cur = ''

  for (const w of words) {
    const next = cur ? `${cur} ${w}` : w

    if (measure(next) <= maxWidth || !cur) {
      cur = next
    } else {
      lines.push(cur)
      cur = w
    }
  }

  if (cur) {
    lines.push(cur)
  }

  if (lines.length > maxLines) {
    const kept = lines.slice(0, maxLines)
    kept[maxLines - 1] = `${kept[maxLines - 1]!.replace(/\s+\S*$/, '')}…`

    return kept
  }

  return lines
}

function rrect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function level(count: number, max: number): number {
  if (count <= 0 || max <= 0) {
    return 0
  }

  const r = count / max

  return r > 0.75 ? 4 : r > 0.5 ? 3 : r > 0.25 ? 2 : 1
}

function relative(iso?: null | string): string {
  if (!iso) {
    return ''
  }

  const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000)

  return s < 60 ? 'baru saja' : s < 3600 ? `${Math.round(s / 60)} mnt lalu` : s < 86400 ? `${Math.round(s / 3600)} jam lalu` : `${Math.round(s / 86400)} hari lalu`
}

const SANS = "Inter, 'Segoe UI', system-ui, sans-serif"
const MONO = "'JetBrains Mono', ui-monospace, Menlo, monospace"
const DISPLAY = "'Inter Display', Inter, 'Segoe UI', system-ui, sans-serif"

/** Paint the card. The canvas is resized to the export size of `opts.format`. */
export function drawShareCard(canvas: HTMLCanvasElement, profile: SocialProfile, opts: ShareCardOptions): void {
  const { height: H, width: W } = SHARE_SIZES[opts.format]
  canvas.width = W
  canvas.height = H
  const ctx = canvas.getContext('2d')

  if (!ctx) {
    return
  }

  const story = opts.format === 'story'
  const { accent, dark } = opts.theme
  const bg = dark ? '#0d0606' : '#f4f2ed'
  const text = dark ? '#f4f2ed' : '#120d0d'
  const muted = dark ? '#b9b2ac' : '#4a4240'
  const raised = dark ? '#1c1010' : '#e1ddd4'

  const paintBackdrop = () => {
    ctx.fillStyle = bg
    ctx.fillRect(0, 0, W, H)

    if (opts.background) {
      ctx.drawImage(opts.background, 0, 0, W, H)
      ctx.fillStyle = rgba(accent, 0.16)
      ctx.fillRect(0, 0, W, H)
    }

    for (const [x, y, r, a] of [
      [0.15, 0.18, 0.75, dark ? 0.55 : 0.35],
      [0.95, 0.62, 0.7, dark ? 0.38 : 0.25],
      [0.3, 0.98, 0.55, dark ? 0.3 : 0.2]
    ] as const) {
      const g = ctx.createRadialGradient(x * W, y * H, 0, x * W, y * H, r * W)
      g.addColorStop(0, rgba(accent, a))
      g.addColorStop(1, rgba(accent, 0))
      ctx.fillStyle = g
      ctx.fillRect(0, 0, W, H)
    }
  }

  paintBackdrop()

  // ---- glass panel: blurred copy of the backdrop, tint, rim, sheen
  const pad = story ? 66 : 48
  const top = story ? 222 : 48
  const cw = W - pad * 2
  const ch = H - top * 2
  const radius = story ? 90 : 78
  ctx.save()
  rrect(ctx, pad, top, cw, ch, radius)
  ctx.clip()
  ctx.filter = 'blur(60px) saturate(160%)'
  ctx.drawImage(canvas, 0, 0)
  ctx.filter = 'none'
  ctx.fillStyle = rgba(mix(dark ? '#120909' : '#ebe8e1', accent, dark ? 0.1 : 0.05), dark ? 0.42 : 0.55)
  ctx.fillRect(pad, top, cw, ch)
  // sheen band
  const t = opts.sheen ?? 0.32
  const sx = pad - ch + (cw + ch) * t
  const sheen = ctx.createLinearGradient(sx - ch * 0.5, 0, sx - ch * 0.5 + cw * 0.35, 0)
  sheen.addColorStop(0, 'rgba(255,255,255,0)')
  sheen.addColorStop(0.5, `rgba(255,255,255,${dark ? 0.14 : 0.3})`)
  sheen.addColorStop(1, 'rgba(255,255,255,0)')
  ctx.fillStyle = sheen
  ctx.beginPath()
  ctx.moveTo(sx, top)
  ctx.lineTo(sx + cw * 0.35, top)
  ctx.lineTo(sx + cw * 0.35 - ch, top + ch)
  ctx.lineTo(sx - ch, top + ch)
  ctx.closePath()
  ctx.fill()
  ctx.restore()
  // specular rim: bright top-left, faint sides, back up bottom-right
  const rim = ctx.createLinearGradient(pad, top, pad + cw, top + ch)
  const rimA = dark ? 0.32 : 0.85
  rim.addColorStop(0, `rgba(255,255,255,${rimA})`)
  rim.addColorStop(0.32, `rgba(255,255,255,${rimA * 0.28})`)
  rim.addColorStop(0.68, `rgba(255,255,255,${rimA * 0.08})`)
  rim.addColorStop(1, `rgba(255,255,255,${rimA * 0.55})`)
  ctx.lineWidth = 3
  ctx.strokeStyle = rim
  rrect(ctx, pad + 1.5, top + 1.5, cw - 3, ch - 3, radius)
  ctx.stroke()

  // ---- content
  const ix = pad + (story ? 66 : 54)
  const iw = cw - (story ? 132 : 108)
  let y = top + (story ? 78 : 54)
  const av = story ? 192 : 138
  ctx.save()
  ctx.beginPath()
  ctx.arc(ix + av / 2, y + av / 2, av / 2, 0, Math.PI * 2)
  ctx.clip()

  if (opts.avatar) {
    ctx.drawImage(opts.avatar, ix, y, av, av)
  } else {
    ctx.fillStyle = accent
    ctx.fillRect(ix, y, av, av)
    ctx.fillStyle = '#ffffff'
    ctx.font = `600 ${av * 0.42}px ${SANS}`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText((profile.name || profile.login || '?')[0]!.toUpperCase(), ix + av / 2, y + av / 2 + 4)
    ctx.textAlign = 'left'
  }

  ctx.restore()
  ctx.strokeStyle = `rgba(255,255,255,${rimA})`
  ctx.lineWidth = 3
  ctx.beginPath()
  ctx.arc(ix + av / 2, y + av / 2, av / 2 + 6, 0, Math.PI * 2)
  ctx.stroke()
  ctx.textBaseline = 'alphabetic'
  ctx.fillStyle = text
  ctx.font = `700 ${story ? 84 : 66}px ${DISPLAY}`
  const nx = ix + av + 36
  ctx.fillText(profile.name || profile.login || '', nx, y + av / 2 + (story ? 6 : 4), iw - av - 36)

  if (profile.login) {
    ctx.fillStyle = muted
    ctx.font = `500 ${story ? 36 : 32}px ${MONO}`
    ctx.fillText(`@${profile.login}`, nx, y + av / 2 + (story ? 60 : 48))
  }

  y += av + (story ? 54 : 38)

  if (story && profile.bio) {
    ctx.fillStyle = text
    ctx.font = `400 42px ${SANS}`
    for (const line of wrapLines(profile.bio, iw, s => ctx.measureText(s).width, 3)) {
      ctx.fillText(line, ix, y + 36)
      y += 62
    }
    y += 24
  }

  // status pill
  const coding = Boolean(profile.status?.coding)
  const label = coding
    ? profile.status?.project
      ? `Lagi ngoding · ${profile.status.project}`
      : 'Lagi ngoding'
    : profile.status?.last_active_at
      ? `Aktif ${relative(profile.status.last_active_at)}`
      : 'Neovarch Agent'
  ctx.font = `500 ${story ? 34 : 32}px ${SANS}`
  const pw = ctx.measureText(label).width + 96
  const ph = story ? 72 : 64
  rrect(ctx, ix, y, pw, ph, ph / 2)
  ctx.fillStyle = coding ? rgba(accent, 0.18) : rgba(text, 0.06)
  ctx.fill()
  ctx.lineWidth = 3
  ctx.strokeStyle = coding ? accent : rgba(text, 0.12)
  ctx.stroke()
  ctx.fillStyle = coding ? accent : muted
  ctx.beginPath()
  ctx.arc(ix + 38, y + ph / 2, 10, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = text
  ctx.fillText(label, ix + 64, y + ph / 2 + 12)
  y += ph + (story ? 70 : 44)

  // heatmap
  const hm = profile.heatmap

  if (hm) {
    ctx.fillStyle = muted
    ctx.font = `600 ${story ? 26 : 24}px ${MONO}`
    ctx.fillText('AKTIVITAS 365 HARI', ix, y)
    y += story ? 26 : 22
    const start = new Date(`${hm.start}T00:00:00`)
    const lead = start.getDay()
    const weeks = Math.ceil((hm.counts.length + lead) / 7)
    const gap = story ? 4 : 3.4
    const cell = (iw - gap * (weeks - 1)) / weeks
    const max = hm.max || Math.max(...hm.counts, 1)
    const colours = [mix(raised, text, 0.07), mix(raised, accent, 0.3), mix(raised, accent, 0.55), mix(raised, accent, 0.78), accent]
    hm.counts.forEach((c, i) => {
      const k = i + lead
      ctx.fillStyle = colours[level(c, max)]!
      rrect(ctx, ix + Math.floor(k / 7) * (cell + gap), y + (k % 7) * (cell + gap), cell, cell, cell * 0.28)
      ctx.fill()
    })
    y += 7 * (cell + gap) + (story ? 40 : 34)
    ctx.fillStyle = muted
    ctx.font = `500 ${story ? 28 : 26}px ${SANS}`
    ctx.fillText(`${hm.total} aktivitas · ${hm.active_days} hari aktif · streak ${hm.streak} hari`, ix, y)
    y += story ? 76 : 56
  }

  // stack chips with logos
  const langs = (profile.stack?.languages ?? []).slice(0, story ? 6 : 5)

  if (langs.length) {
    if (story) {
      ctx.fillStyle = muted
      ctx.font = `600 26px ${MONO}`
      ctx.fillText('STACK YANG SERING DIPAKAI', ix, y)
      y += 30
    }

    const chipH = story ? 84 : 78
    let x = ix
    ctx.font = `500 ${story ? 32 : 30}px ${SANS}`
    for (const l of langs) {
      const icon = techIconFor(l.name)
      const caption = story ? `${icon?.title ?? l.name}  ${Math.round(l.share * 100)}%` : ''
      const w = (story ? 96 : 78) + (caption ? ctx.measureText(caption).width : 0)

      if (x + w > ix + iw) {
        x = ix
        y += chipH + 18
      }

      rrect(ctx, x, y, w, chipH, chipH / 2)
      ctx.fillStyle = rgba(mix(dark ? '#120909' : '#ebe8e1', accent, 0.1), dark ? 0.55 : 0.62)
      ctx.fill()
      ctx.lineWidth = 2.4
      ctx.strokeStyle = rgba(text, dark ? 0.1 : 0.12)
      ctx.stroke()
      const s = story ? 44 : 42
      ctx.save()
      ctx.translate(x + (story ? 26 : 18), y + (chipH - s) / 2)
      ctx.scale(s / 24, s / 24)
      ctx.fillStyle = accent

      if (icon && typeof Path2D !== 'undefined') {
        ctx.fill(new Path2D(icon.path))
      } else {
        ctx.font = `700 18px ${MONO}`
        ctx.fillText('</>', 0, 18)
      }

      ctx.restore()

      if (caption) {
        ctx.fillStyle = text
        ctx.font = `500 32px ${SANS}`
        ctx.fillText(caption, x + 84, y + chipH / 2 + 11)
      }

      x += w + 18
    }
  }

  // Neovarch mark, small, bottom-right of the glass
  ctx.fillStyle = rgba(text, 0.75)
  ctx.font = `600 ${story ? 26 : 24}px ${MONO}`
  ctx.textAlign = 'right'
  ctx.fillText('✦ Neovarch Agent', pad + cw - (story ? 60 : 48), top + ch - (story ? 54 : 40))

  if (story) {
    ctx.textAlign = 'center'
    ctx.fillStyle = rgba(text, 0.55)
    ctx.font = `500 26px ${MONO}`
    ctx.fillText('neovarch agent · profil', W / 2, H - 96)
  }

  ctx.textAlign = 'left'
}

export function loadImage(url: string): Promise<HTMLImageElement | null> {
  return new Promise(resolve => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = url
  })
}

export function canvasToPng(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('PNG gagal dibuat'))), 'image/png')
  )
}

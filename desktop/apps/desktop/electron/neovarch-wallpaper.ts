// Neovarch custom wallpaper ("Latar belakang", Settings ▸ Tampilan).
//
// A picked or dropped image is COPIED into <userData>/wallpapers so the
// wallpaper survives the original being moved or deleted. Only one copy is
// kept: importing a new image (or clearing) removes the previous one. The
// renderer never gets a filesystem path back, only the stored file's bare name,
// and reads it through `read(name)`, which refuses anything outside the
// wallpapers directory.

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

/** Largest image accepted (bytes). Wallpapers are read whole as a data URL. */
export const WALLPAPER_MAX_BYTES = 25 * 1024 * 1024

export type WallpaperKind = 'gif' | 'jpg' | 'png' | 'webp'

const MIME: Record<WallpaperKind, string> = {
  gif: 'image/gif',
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp'
}

export const WALLPAPER_EXTENSIONS = ['png', 'jpg', 'jpeg', 'webp', 'gif']

/** Sniff the image type from its first bytes; the extension is not trusted. */
export function sniffWallpaperKind(bytes: Uint8Array): null | WallpaperKind {
  const b = bytes
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    return 'png'
  }

  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    return 'jpg'
  }

  if (
    b.length >= 12 &&
    b[0] === 0x52 &&
    b[1] === 0x49 &&
    b[2] === 0x46 &&
    b[3] === 0x46 &&
    b[8] === 0x57 &&
    b[9] === 0x45 &&
    b[10] === 0x42 &&
    b[11] === 0x50
  ) {
    return 'webp'
  }

  if (b.length >= 6 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
    return 'gif'
  }

  return null
}

export interface WallpaperImportResult {
  ok: boolean
  /** Bare file name inside the wallpapers directory (ok only). */
  name?: string
  /** Indonesian, user-facing (not ok only). */
  error?: string
}

export interface WallpaperReadResult {
  dataUrl: string
  mime: string
}

const NAME_RE = /^wallpaper-[0-9a-f]{16}\.(png|jpg|webp|gif)$/

export function createWallpaperStore({ dir }: { dir: string }) {
  const ensureDir = () => fs.mkdirSync(dir, { recursive: true })

  const removeAllExcept = (keep: null | string) => {
    let entries: string[] = []

    try {
      entries = fs.readdirSync(dir)
    } catch {
      return
    }

    for (const entry of entries) {
      if (entry !== keep && NAME_RE.test(entry)) {
        try {
          fs.unlinkSync(path.join(dir, entry))
        } catch {
          // best effort; a stale copy is harmless
        }
      }
    }
  }

  const importBytes = (input: Uint8Array): WallpaperImportResult => {
    const bytes = Buffer.from(input)

    if (bytes.length === 0) {
      return { ok: false, error: 'File gambar kosong.' }
    }

    if (bytes.length > WALLPAPER_MAX_BYTES) {
      return { ok: false, error: 'Gambar terlalu besar (maks. 25 MB).' }
    }

    const kind = sniffWallpaperKind(bytes)

    if (!kind) {
      return { ok: false, error: 'Format tidak didukung. Pakai PNG, JPG, WebP, atau GIF.' }
    }

    ensureDir()
    const hash = crypto.createHash('sha256').update(bytes).digest('hex').slice(0, 16)
    const name = `wallpaper-${hash}.${kind}`
    fs.writeFileSync(path.join(dir, name), bytes)
    removeAllExcept(name)

    return { ok: true, name }
  }

  const importFile = (filePath: string): WallpaperImportResult => {
    if (typeof filePath !== 'string' || !filePath) {
      return { ok: false, error: 'Tidak ada file.' }
    }

    let stat: fs.Stats

    try {
      stat = fs.statSync(filePath)
    } catch {
      return { ok: false, error: 'File tidak ditemukan.' }
    }

    if (!stat.isFile()) {
      return { ok: false, error: 'Itu bukan file gambar.' }
    }

    if (stat.size > WALLPAPER_MAX_BYTES) {
      return { ok: false, error: 'Gambar terlalu besar (maks. 25 MB).' }
    }

    return importBytes(fs.readFileSync(filePath))
  }

  const read = (name: string): null | WallpaperReadResult => {
    if (typeof name !== 'string' || !NAME_RE.test(name)) {
      return null
    }

    try {
      const bytes = fs.readFileSync(path.join(dir, name))
      const kind = sniffWallpaperKind(bytes)

      if (!kind) {
        return null
      }

      return { dataUrl: `data:${MIME[kind]};base64,${bytes.toString('base64')}`, mime: MIME[kind] }
    } catch {
      return null
    }
  }

  const clear = () => removeAllExcept(null)

  return { clear, importBytes, importFile, read }
}

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createWallpaperStore, sniffWallpaperKind, WALLPAPER_MAX_BYTES } from './neovarch-wallpaper'

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4])
const JPG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10])
const WEBP = Buffer.from('RIFF\u0000\u0000\u0000\u0000WEBPVP8 ', 'latin1')
const GIF = Buffer.from('GIF89a\u0001\u0000', 'latin1')

let tmp: string
let dir: string

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'nv-wall-'))
  dir = path.join(tmp, 'userData', 'wallpapers')
})

afterEach(() => fs.rmSync(tmp, { recursive: true, force: true }))

describe('neovarch wallpaper store', () => {
  it('sniffs png/jpg/webp/gif by content, not extension', () => {
    expect(sniffWallpaperKind(PNG)).toBe('png')
    expect(sniffWallpaperKind(JPG)).toBe('jpg')
    expect(sniffWallpaperKind(WEBP)).toBe('webp')
    expect(sniffWallpaperKind(GIF)).toBe('gif')
    expect(sniffWallpaperKind(Buffer.from('<svg/>'))).toBeNull()
  })

  it('copies the picked file into userData so it survives the original being deleted', () => {
    const store = createWallpaperStore({ dir })
    const original = path.join(tmp, 'holiday.jpeg')
    fs.writeFileSync(original, JPG)

    const result = store.importFile(original)
    expect(result.ok).toBe(true)
    expect(result.name).toMatch(/^wallpaper-[0-9a-f]{16}\.jpg$/)

    fs.unlinkSync(original)
    const read = store.read(result.name!)
    expect(read?.mime).toBe('image/jpeg')
    expect(read?.dataUrl).toBe(`data:image/jpeg;base64,${JPG.toString('base64')}`)
  })

  it('keeps only the newest copy and clear() removes it', () => {
    const store = createWallpaperStore({ dir })
    const first = store.importBytes(PNG)
    const second = store.importBytes(WEBP)

    expect(fs.readdirSync(dir)).toEqual([second.name])
    expect(store.read(first.name!)).toBeNull()

    store.clear()
    expect(fs.readdirSync(dir)).toEqual([])
  })

  it('rejects unsupported, empty and oversized images with an Indonesian message', () => {
    const store = createWallpaperStore({ dir })

    expect(store.importBytes(Buffer.from('not an image'))).toMatchObject({ ok: false, error: expect.stringContaining('Format') })
    expect(store.importBytes(new Uint8Array())).toMatchObject({ ok: false })
    expect(store.importBytes(new Uint8Array(WALLPAPER_MAX_BYTES + 1))).toMatchObject({ ok: false, error: expect.stringContaining('25 MB') })
    expect(store.importFile(path.join(tmp, 'missing.png'))).toMatchObject({ ok: false })
  })

  it('never reads outside the wallpapers directory', () => {
    const store = createWallpaperStore({ dir })
    fs.writeFileSync(path.join(tmp, 'secret.png'), PNG)

    expect(store.read('../secret.png')).toBeNull()
    expect(store.read('/etc/passwd')).toBeNull()
  })
})

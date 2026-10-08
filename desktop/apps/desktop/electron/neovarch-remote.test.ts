import { describe, expect, it } from 'vitest'

import {
  buildPairingUri,
  decodeSecret,
  FALLBACK_DEVICE_NAME,
  lanAddresses,
  mintAccessToken,
  resolveDeviceName,
  verifyAccessToken
} from './neovarch-remote'

// Vector produced by the Hermes core's own signer (plugins/dashboard_auth/basic `_sign`):
// urlsafe_b64encode(json.dumps(payload, separators=(",", ":")) + hmac_sha256(secret, json)).
const SECRET = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='
const PY_TOKEN =
  'eyJzdWIiOiJuZW92YXJjaC1yZW1vdGUiLCJraW5kIjoiYWNjZXNzIiwiZXhwIjoxOTE3NjgwMDAwfV4rLKqa3Agh4LhUO4M7pCZO1lOGjoLnckp9jymhQhUh'

describe('neovarch remote token', () => {
  it('matches the core basic-auth signer byte for byte', () => {
    expect(mintAccessToken(decodeSecret(SECRET), 1760000000)).toBe(PY_TOKEN)
  })

  it('verifies its own tokens and rejects a rotated secret', () => {
    const token = mintAccessToken(decodeSecret(SECRET), 1760000000)
    expect(verifyAccessToken(token, decodeSecret(SECRET), 1760000001)).toBe(true)
    expect(verifyAccessToken(token, Buffer.alloc(32, 7), 1760000001)).toBe(false)
  })

  it('builds the phone pairing URI', () => {
    const uri = buildPairingUri({ url: 'http://192.168.1.5:9119', token: 'abc=', name: 'PC Kantor', profile: 'default' })
    const q = new URL(uri.replace('neovarch://', 'http://x/')).searchParams
    expect(uri.startsWith('neovarch://pair?v=1&')).toBe(true)
    expect(q.get('url')).toBe('http://192.168.1.5:9119')
    expect(q.get('token')).toBe('abc=')
    expect(q.get('name')).toBe('PC Kantor')
    expect(q.get('profile')).toBe('default')
  })

  it('prefers real LAN interfaces over virtual ones', () => {
    const list = lanAddresses({
      docker0: [{ address: '172.17.0.1', family: 'IPv4', internal: false } as never],
      lo: [{ address: '127.0.0.1', family: 'IPv4', internal: true } as never],
      wlan0: [{ address: '192.168.1.5', family: 'IPv4', internal: false } as never]
    })
    expect(list.map(a => a.address)).toEqual(['192.168.1.5', '172.17.0.1'])
  })

  it('falls back to a readable PC name when the hostname is empty or "(none)"', () => {
    expect(resolveDeviceName('')).toBe(FALLBACK_DEVICE_NAME)
    expect(resolveDeviceName('  ')).toBe(FALLBACK_DEVICE_NAME)
    expect(resolveDeviceName('(none)')).toBe(FALLBACK_DEVICE_NAME)
    expect(resolveDeviceName(' workstation ')).toBe('workstation')
    expect(FALLBACK_DEVICE_NAME).toBe('PC Neovarch')
  })
})

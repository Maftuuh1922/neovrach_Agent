// Optional: copy to hermes-phone-main/src/middleware.ts when serving the
// Flutter *web* build from a different origin than the Next.js server.
// The Android app does not need this (no CORS on native HTTP).
import { NextRequest, NextResponse } from 'next/server'

const ALLOW = process.env.HERMES_CORS_ORIGIN || '*'

export function middleware(req: NextRequest) {
  const headers = {
    'Access-Control-Allow-Origin': ALLOW,
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  }
  if (req.method === 'OPTIONS') return new NextResponse(null, { status: 204, headers })
  const res = NextResponse.next()
  for (const [k, v] of Object.entries(headers)) res.headers.set(k, v)
  return res
}

export const config = { matcher: '/api/hermes/:path*' }

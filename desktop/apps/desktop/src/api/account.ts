import { hermesApi } from './client'

/** Settings → Akun: the one account Neovarch signs in to (GitHub, by token). */
export interface GithubAccount {
  provider: 'github'
  connected: boolean
  valid?: boolean
  login?: string
  name?: string
  avatar_url?: string
  html_url?: string
  scopes?: string[]
  error?: string
}

export interface GithubConnectResult extends Partial<GithubAccount> {
  ok: boolean
  error?: string
}

export function getGithubAccount(): Promise<GithubAccount> {
  return hermesApi<GithubAccount>({ path: '/api/account/github', timeoutMs: 15_000 })
}

export function connectGithubAccount(token: string): Promise<GithubConnectResult> {
  return hermesApi<GithubConnectResult>({ path: '/api/account/github', method: 'POST', body: { token } })
}

export function disconnectGithubAccount(): Promise<GithubAccount> {
  return hermesApi<GithubAccount>({ path: '/api/account/github', method: 'DELETE' })
}

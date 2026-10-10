import { useCallback, useEffect, useState } from 'react'

import { connectGithubAccount, disconnectGithubAccount, getGithubAccount, type GithubAccount } from '@/api/account'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Check, Loader2, LogIn } from '@/lib/icons'
import { notify, notifyError } from '@/store/notifications'

import { SectionHeading, SettingsContent, SettingsLoadError, SettingsSkeleton } from './primitives'

const TOKEN_URL = 'https://github.com/settings/tokens/new?scopes=repo,read:org&description=Neovarch%20Agent'

/**
 * Settings → Akun. Neovarch has exactly one account: GitHub, signed in with a
 * personal access token the core checks against the GitHub API and hands to
 * the agent's shell (GITHUB_TOKEN / GH_TOKEN) for git and gh. Model providers
 * are not accounts here; they use API keys or custom endpoints.
 */
export function GithubAccountSettings() {
  const [account, setAccount] = useState<GithubAccount | null>(null)
  const [loadError, setLoadError] = useState<unknown>(null)
  const [token, setToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState('')

  const load = useCallback(async () => {
    setLoadError(null)

    try {
      setAccount(await getGithubAccount())
    } catch (err) {
      setLoadError(err)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  if (loadError) {
    return <SettingsLoadError error={loadError} onRetry={() => void load()} title="Akun GitHub belum bisa dimuat" />
  }

  if (!account) {
    return <SettingsSkeleton sections={[{ rows: 2 }]} />
  }

  async function connect() {
    setBusy(true)
    setFormError('')

    try {
      const res = await connectGithubAccount(token)

      if (!res.ok) {
        setFormError(res.error || 'Login GitHub gagal.')

        return
      }

      setToken('')
      notify({ kind: 'success', message: `Masuk sebagai ${res.login}` })
      await load()
    } catch (err) {
      notifyError(err, 'Login GitHub gagal')
    } finally {
      setBusy(false)
    }
  }

  async function disconnect() {
    setBusy(true)

    try {
      setAccount(await disconnectGithubAccount())
    } catch (err) {
      notifyError(err, 'Gagal keluar dari GitHub')
    } finally {
      setBusy(false)
    }
  }

  return (
    <SettingsContent>
      <SectionHeading icon={LogIn} title="Akun GitHub" />
      {account.connected ? (
        <div className="grid gap-3" data-testid="github-account-connected">
          <div className="flex items-center gap-3">
            {account.avatar_url ? (
              <img alt="" className="size-10 rounded-full" src={account.avatar_url} />
            ) : null}
            <div className="min-w-0">
              <p className="font-medium">{account.name || account.login || 'GitHub'}</p>
              {account.login && (
                <p className="text-[length:var(--conversation-caption-font-size)] text-muted-foreground">
                  @{account.login}
                  {account.scopes?.length ? ` · ${account.scopes.join(', ')}` : ''}
                </p>
              )}
            </div>
            {account.valid !== false && <Check className="ml-auto size-4 text-(--ui-text-secondary)" />}
          </div>
          {account.valid === false && (
            <p className="text-[length:var(--conversation-caption-font-size)] text-destructive" role="alert">
              {account.error || 'Token tersimpan tidak lagi diterima GitHub.'}
            </p>
          )}
          <p className="text-[length:var(--conversation-caption-font-size)] text-muted-foreground">
            Agen memakai akun ini untuk git dan gh (GITHUB_TOKEN).
          </p>
          <div className="flex gap-2">
            {account.valid === false && (
              <Button onClick={() => void load()} size="sm" variant="outline">
                Coba lagi
              </Button>
            )}
            <Button disabled={busy} onClick={() => void disconnect()} size="sm" variant="outline">
              Keluar
            </Button>
          </div>
        </div>
      ) : (
        <form
          className="grid max-w-lg gap-3"
          data-testid="github-account-form"
          onSubmit={event => {
            event.preventDefault()
            void connect()
          }}
        >
          <p className="text-[length:var(--conversation-caption-font-size)] text-muted-foreground">
            Masuk dengan token GitHub.{' '}
            <a className="underline" href={TOKEN_URL} rel="noreferrer" target="_blank">
              Buat token
            </a>{' '}
            (scope repo, read:org), lalu tempel di sini.
          </p>
          <Input
            aria-label="Token GitHub"
            autoComplete="off"
            onChange={event => setToken(event.target.value)}
            placeholder="ghp_… atau github_pat_…"
            type="password"
            value={token}
          />
          {formError && (
            <p className="text-[length:var(--conversation-caption-font-size)] text-destructive" role="alert">
              {formError}
            </p>
          )}
          <div>
            <Button disabled={busy || !token.trim()} size="sm" type="submit">
              {busy ? <Loader2 className="size-4 animate-spin" /> : null}
              Masuk dengan GitHub
            </Button>
          </div>
        </form>
      )}
    </SettingsContent>
  )
}

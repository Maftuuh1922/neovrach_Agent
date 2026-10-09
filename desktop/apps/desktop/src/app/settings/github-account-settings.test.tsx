// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const getGithubAccount = vi.fn()
const connectGithubAccount = vi.fn()
const disconnectGithubAccount = vi.fn()

vi.mock('@/api/account', () => ({
  connectGithubAccount: (token: string) => connectGithubAccount(token),
  disconnectGithubAccount: () => disconnectGithubAccount(),
  getGithubAccount: () => getGithubAccount()
}))

vi.mock('@/store/notifications', () => ({ notify: vi.fn(), notifyError: vi.fn() }))

import { GithubAccountSettings } from './github-account-settings'

beforeEach(() => {
  getGithubAccount.mockReset()
  connectGithubAccount.mockReset()
  disconnectGithubAccount.mockReset()
})

afterEach(() => cleanup())

describe('Akun GitHub', () => {
  it('signs in with a token and shows the account', async () => {
    getGithubAccount.mockResolvedValueOnce({ connected: false, provider: 'github' })
    connectGithubAccount.mockResolvedValue({ connected: true, login: 'octo', ok: true })
    getGithubAccount.mockResolvedValueOnce({ connected: true, login: 'octo', name: 'Octo', provider: 'github', valid: true })

    await act(async () => void render(<GithubAccountSettings />))
    fireEvent.change(await screen.findByLabelText('Token GitHub'), { target: { value: 'ghp_x' } })
    fireEvent.click(screen.getByRole('button', { name: 'Masuk dengan GitHub' }))

    await waitFor(() => expect(connectGithubAccount).toHaveBeenCalledWith('ghp_x'))
    expect(await screen.findByText('@octo')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Keluar' })).toBeTruthy()
  })

  it('shows a rejected token inline', async () => {
    getGithubAccount.mockResolvedValue({ connected: false, provider: 'github' })
    connectGithubAccount.mockResolvedValue({ error: 'Token GitHub ditolak (HTTP 401).', ok: false })

    await act(async () => void render(<GithubAccountSettings />))
    fireEvent.change(await screen.findByLabelText('Token GitHub'), { target: { value: 'bad' } })
    fireEvent.click(screen.getByRole('button', { name: 'Masuk dengan GitHub' }))

    expect((await screen.findByRole('alert')).textContent).toContain('ditolak')
  })

  it('a failed load shows the Indonesian error with Coba lagi', async () => {
    getGithubAccount.mockRejectedValueOnce(new Error('backend offline'))
    getGithubAccount.mockResolvedValueOnce({ connected: false, provider: 'github' })

    await act(async () => void render(<GithubAccountSettings />))
    expect(await screen.findByText('Akun GitHub belum bisa dimuat')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Coba lagi' }))
    expect(await screen.findByLabelText('Token GitHub')).toBeTruthy()
  })
})

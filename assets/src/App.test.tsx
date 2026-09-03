import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import App from './App'
import { ApiRequestError } from './api/client'
import type { ApiClient, OrgChartResponse } from './api/types'

describe('App session flow', () => {
  it('shows a loading state while the session bootstrap is pending', () => {
    const sessionRequest = deferred<{
      authenticated: boolean
      csrf_token: string
    }>()
    render(
      <App
        client={stubClient({ session: vi.fn(() => sessionRequest.promise) })}
      />,
    )

    expect(screen.getByRole('status')).toHaveTextContent('Checking session…')
  })

  it('shows the login form after an unauthenticated bootstrap', async () => {
    render(<App client={stubClient()} />)

    expect(
      await screen.findByRole('heading', { name: 'Remote org chart' }),
    ).toBeInTheDocument()
    expect(screen.getByLabelText('Username')).toBeInTheDocument()
  })

  it('loads the organization after a successful login', async () => {
    const user = userEvent.setup()
    const login = vi.fn().mockResolvedValue({
      authenticated: true,
      csrf_token: 'renewed-csrf',
    })
    const orgChart = vi.fn().mockResolvedValue(chart('Acme Sandbox Corp'))
    render(<App client={stubClient({ login, orgChart })} />)

    await user.type(await screen.findByLabelText('Username'), 'reviewer')
    await user.type(screen.getByLabelText('Password'), 'secret')
    await user.click(screen.getByRole('button', { name: 'View org chart' }))

    expect(
      await screen.findByRole('heading', { name: 'Acme Sandbox Corp' }),
    ).toBeInTheDocument()
    expect(login).toHaveBeenCalledWith('reviewer', 'secret', 'initial-csrf')
    expect(orgChart).toHaveBeenCalledOnce()
  })

  it('returns to login when a later request reports a missing session', async () => {
    const session = vi.fn().mockResolvedValue({
      authenticated: true,
      csrf_token: 'authenticated-csrf',
    })
    const orgChart = vi
      .fn()
      .mockRejectedValue(
        new ApiRequestError(401, { code: 'authentication_required' }),
      )
    render(<App client={stubClient({ session, orgChart })} />)

    expect(await screen.findByLabelText('Username')).toBeInTheDocument()
    expect(
      screen.queryByText('Request failed with authentication_required'),
    ).not.toBeInTheDocument()
  })

  it('returns to login immediately when logout is still pending', async () => {
    const user = userEvent.setup()
    const logoutRequest = deferred<void>()
    const session = vi.fn().mockResolvedValue({
      authenticated: true,
      csrf_token: 'authenticated-csrf',
    })
    render(
      <App
        client={stubClient({
          session,
          logout: vi.fn(() => logoutRequest.promise),
        })}
      />,
    )

    await user.click(await screen.findByRole('button', { name: 'Sign out' }))

    expect(screen.getByLabelText('Username')).toBeInTheDocument()
  })
})

function stubClient(overrides: Partial<ApiClient> = {}): ApiClient {
  return {
    session: vi.fn().mockResolvedValue({
      authenticated: false,
      csrf_token: 'initial-csrf',
    }),
    login: vi.fn(),
    logout: vi.fn().mockResolvedValue(undefined),
    orgChart: vi.fn().mockResolvedValue(chart('Acme')),
    refresh: vi.fn(),
    ...overrides,
  }
}

function chart(companyName: string): OrgChartResponse {
  return {
    company: { id: 'company', name: companyName },
    roots: [],
    warnings: [],
    meta: {
      employee_count: 0,
      root_count: 0,
      fetched_at: '2026-09-03T12:00:00Z',
      stale: false,
    },
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  let reject!: (reason?: unknown) => void
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise
    reject = rejectPromise
  })

  return { promise, resolve, reject }
}

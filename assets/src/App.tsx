import { useEffect, useState } from 'react'

import { ApiRequestError, createApiClient } from './api/client'
import type { ApiClient, OrgChartResponse } from './api/types'
import LoginForm from './components/LoginForm'

const defaultClient = createApiClient()

type AppState =
  | { kind: 'booting' }
  | { kind: 'unauthenticated' }
  | { kind: 'authenticated-loading' }
  | { kind: 'authenticated-ready'; chart: OrgChartResponse }
  | { kind: 'authenticated-error'; error: unknown }

interface AppProps {
  client?: ApiClient
}

function App({ client = defaultClient }: AppProps) {
  const [state, setState] = useState<AppState>({ kind: 'booting' })
  const [csrfToken, setCsrfToken] = useState('')

  useEffect(() => {
    let active = true

    async function bootstrap() {
      try {
        const session = await client.session()
        if (!active) return

        setCsrfToken(session.csrf_token)

        if (!session.authenticated) {
          setState({ kind: 'unauthenticated' })
          return
        }

        setState({ kind: 'authenticated-loading' })
        const chart = await client.orgChart()
        if (active) setState({ kind: 'authenticated-ready', chart })
      } catch (error) {
        if (!active) return

        setState(
          isAuthenticationRequired(error)
            ? { kind: 'unauthenticated' }
            : { kind: 'authenticated-error', error },
        )
      }
    }

    void bootstrap()
    return () => {
      active = false
    }
  }, [client])

  async function login(username: string, password: string) {
    const session = await client.login(username, password, csrfToken)
    setCsrfToken(session.csrf_token)
    setState({ kind: 'authenticated-loading' })

    try {
      const chart = await client.orgChart()
      setState({ kind: 'authenticated-ready', chart })
    } catch (error) {
      setState(
        isAuthenticationRequired(error)
          ? { kind: 'unauthenticated' }
          : { kind: 'authenticated-error', error },
      )
    }
  }

  async function logout() {
    const token = csrfToken
    setState({ kind: 'unauthenticated' })

    try {
      await client.logout(token)
    } catch {
      // The local authenticated view stays cleared even if the request fails.
    }
  }

  if (state.kind === 'booting') {
    return <LoadingState message="Checking session…" />
  }

  if (state.kind === 'unauthenticated') {
    return <LoginForm onLogin={login} />
  }

  if (state.kind === 'authenticated-loading') {
    return <LoadingState message="Loading organization…" />
  }

  if (state.kind === 'authenticated-error') {
    const code =
      state.error instanceof ApiRequestError
        ? state.error.code
        : 'internal_error'

    return (
      <main className="app-shell">
        <h1>Remote org chart</h1>
        <p role="alert">Unable to load the organization ({code}).</p>
        <button type="button" onClick={() => window.location.reload()}>
          Retry
        </button>
        <button type="button" className="button-secondary" onClick={logout}>
          Sign out
        </button>
      </main>
    )
  }

  return (
    <main className="app-shell">
      <header className="app-header">
        <h1>{state.chart.company.name}</h1>
        <button type="button" className="button-secondary" onClick={logout}>
          Sign out
        </button>
      </header>
      <section aria-label="Organization chart">
        <p>Organization chart ready.</p>
      </section>
    </main>
  )
}

function LoadingState({ message }: { message: string }) {
  return (
    <main className="loading-page">
      <p role="status">{message}</p>
    </main>
  )
}

function isAuthenticationRequired(error: unknown) {
  return (
    error instanceof ApiRequestError && error.code === 'authentication_required'
  )
}

export default App

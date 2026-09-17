import { useEffect, useRef, useState } from 'react'

import { ApiRequestError, createApiClient } from './api/client'
import type { ApiClient, OrgChartResponse } from './api/types'
import LoginForm from './components/LoginForm'
import OrgChart from './components/OrgChart'

const defaultClient = createApiClient()

type AppState =
  | { kind: 'booting' }
  | { kind: 'bootstrap-error' }
  | { kind: 'logging-out' }
  | { kind: 'logout-error' }
  | { kind: 'unauthenticated' }
  | { kind: 'authenticated-loading' }
  | {
      kind: 'authenticated-ready'
      chart: OrgChartResponse
      refreshing: boolean
      refreshError?: unknown
    }
  | { kind: 'authenticated-error'; error: unknown }

interface AppProps {
  client?: ApiClient
}

function App({ client = defaultClient }: AppProps) {
  const [state, setState] = useState<AppState>({ kind: 'booting' })
  const [csrfToken, setCsrfToken] = useState('')
  const operation = useRef(0)
  const [bootstrapAttempt, setBootstrapAttempt] = useState(0)

  useEffect(() => {
    const currentOperation = ++operation.current

    async function bootstrap() {
      let sessionLoaded = false
      try {
        const session = await client.session()
        if (operation.current !== currentOperation) return

        setCsrfToken(session.csrf_token)
        sessionLoaded = true

        if (!session.authenticated) {
          setState({ kind: 'unauthenticated' })
          return
        }

        setState({ kind: 'authenticated-loading' })
        const chart = await client.orgChart()

        if (operation.current === currentOperation) {
          setState({
            kind: 'authenticated-ready',
            chart,
            refreshing: false,
          })
        }
      } catch (error) {
        if (operation.current !== currentOperation) return
        if (sessionLoaded) handleLoadFailure(error)
        else setState({ kind: 'bootstrap-error' })
      }
    }

    void bootstrap()
    return () => {
      if (operation.current === currentOperation) operation.current += 1
    }
  }, [client, bootstrapAttempt])

  function restartSession() {
    setCsrfToken('')
    setState({ kind: 'booting' })
    setBootstrapAttempt((attempt) => attempt + 1)
  }

  function handleLoadFailure(error: unknown) {
    setState(
      isAuthenticationRequired(error)
        ? { kind: 'unauthenticated' }
        : { kind: 'authenticated-error', error },
    )
  }

  async function login(username: string, password: string) {
    const currentOperation = ++operation.current
    const session = await client.login(username, password, csrfToken)
    if (operation.current !== currentOperation) return

    setCsrfToken(session.csrf_token)
    setState({ kind: 'authenticated-loading' })

    try {
      const chart = await client.orgChart()
      if (operation.current === currentOperation) {
        setState({
          kind: 'authenticated-ready',
          chart,
          refreshing: false,
        })
      }
    } catch (error) {
      if (operation.current === currentOperation) handleLoadFailure(error)
    }
  }

  async function loadChart() {
    const currentOperation = ++operation.current
    setState({ kind: 'authenticated-loading' })

    try {
      const chart = await client.orgChart()
      if (operation.current === currentOperation) {
        setState({
          kind: 'authenticated-ready',
          chart,
          refreshing: false,
        })
      }
    } catch (error) {
      if (operation.current === currentOperation) handleLoadFailure(error)
    }
  }

  async function refreshChart() {
    if (state.kind !== 'authenticated-ready') return

    const currentChart = state.chart
    const currentOperation = ++operation.current
    setState({
      kind: 'authenticated-ready',
      chart: currentChart,
      refreshing: true,
    })

    try {
      const chart = await client.refresh(csrfToken)
      if (operation.current === currentOperation) {
        setState({
          kind: 'authenticated-ready',
          chart,
          refreshing: false,
        })
      }
    } catch (error) {
      if (operation.current !== currentOperation) return

      if (isAuthenticationRequired(error)) {
        setState({ kind: 'unauthenticated' })
      } else {
        setState({
          kind: 'authenticated-ready',
          chart: currentChart,
          refreshing: false,
          refreshError: error,
        })
      }
    }
  }

  async function logout() {
    const currentOperation = ++operation.current
    let token = csrfToken
    const retryingLogout = state.kind === 'logout-error'
    setState({ kind: 'logging-out' })

    try {
      if (retryingLogout) {
        const session = await client.session()
        if (operation.current !== currentOperation) return
        token = session.csrf_token
        setCsrfToken(token)
        if (!session.authenticated) {
          setState({ kind: 'unauthenticated' })
          return
        }
      }
      await client.logout(token)
      if (operation.current === currentOperation) restartSession()
    } catch {
      if (operation.current === currentOperation) setState({ kind: 'logout-error' })
    }
  }

  if (state.kind === 'logging-out') {
    return <LoadingState message="Signing out…" />
  }

  if (state.kind === 'logout-error' || state.kind === 'bootstrap-error') {
    const logoutFailed = state.kind === 'logout-error'
    return (
      <main className="error-page">
        <section className="error-panel">
          <h1>Remote org chart</h1>
          <p role="alert">{logoutFailed
            ? 'Sign-out could not be confirmed. Your session may still be active.'
            : 'Your session could not be checked. Please try again.'}</p>
          <button type="button" onClick={logoutFailed ? () => void logout() : restartSession}>
            {logoutFailed ? 'Retry sign out' : 'Retry'}
          </button>
        </section>
      </main>
    )
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
    return (
      <ErrorState
        error={state.error}
        onRetry={() => void loadChart()}
        onLogout={() => void logout()}
      />
    )
  }

  return (
    <OrgChart
      chart={state.chart}
      refreshing={state.refreshing}
      refreshError={
        state.refreshError ? errorPresentation(state.refreshError) : undefined
      }
      onRefresh={() => void refreshChart()}
      onLogout={() => void logout()}
    />
  )
}

function LoadingState({ message }: { message: string }) {
  return (
    <main className="loading-page">
      <p role="status">{message}</p>
    </main>
  )
}

function ErrorState({
  error,
  onRetry,
  onLogout,
}: {
  error: unknown
  onRetry(): void
  onLogout(): void
}) {
  const presentation = errorPresentation(error)

  return (
    <main className="error-page">
      <section className="error-panel">
        <h1>Remote org chart</h1>
        <div role="alert">
          <p>{presentation.message}</p>
          {presentation.requestId && (
            <p className="request-id">Request ID: {presentation.requestId}</p>
          )}
        </div>
        <div className="error-actions">
          <button type="button" onClick={onRetry}>
            Retry
          </button>
          <button type="button" className="button-secondary" onClick={onLogout}>
            Sign out
          </button>
        </div>
      </section>
    </main>
  )
}

function errorPresentation(error: unknown) {
  const code = error instanceof ApiRequestError ? error.code : 'internal_error'
  const requestId =
    error instanceof ApiRequestError ? error.requestId : undefined

  const messages: Record<string, string> = {
    remote_temporarily_unavailable:
      'Remote is temporarily unavailable. Try again.',
    invalid_remote_response:
      'Remote returned data this app could not understand.',
    remote_authentication_failed:
      'Remote API authentication failed. Check the server configuration.',
    internal_error: 'Something went wrong while loading the organization.',
  }

  return {
    message:
      messages[code] ?? 'Something went wrong while loading the organization.',
    requestId,
  }
}

function isAuthenticationRequired(error: unknown) {
  return (
    error instanceof ApiRequestError && error.code === 'authentication_required'
  )
}

export default App

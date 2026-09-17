import { ApiRequestError } from '../api/client'
import { useState, type FormEvent } from 'react'

interface LoginFormProps {
  onLogin(username: string, password: string): Promise<void>
}

function LoginForm({ onLogin }: LoginFormProps) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPending(true)
    setError(null)

    try {
      await onLogin(username.trim(), password)
    } catch (error) {
      setPassword('')
      setError(error instanceof ApiRequestError && error.status === 429
        ? 'Too many sign-in attempts. Please wait a minute and try again.'
        : error instanceof ApiRequestError && error.code === 'invalid_credentials'
          ? 'The username or password is incorrect.'
          : 'Unable to sign in. Please try again.')
    } finally {
      setPending(false)
    }
  }

  return (
    <main className="login-page">
      <section className="login-card" aria-labelledby="login-title">
        <div className="product-mark" aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
        <h1 id="login-title">Remote org chart</h1>
        <p>Sign in to view the company reporting structure.</p>

        <form onSubmit={submit}>
          <label htmlFor="username">Username</label>
          <input
            id="username"
            name="username"
            type="text"
            autoComplete="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            disabled={pending}
            required
            autoFocus
          />

          <label htmlFor="password">Password</label>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            disabled={pending}
            required
          />

          <div className="form-error" aria-live="polite">
            {error}
          </div>

          <button type="submit" disabled={pending}>
            {pending ? 'Signing in…' : 'View org chart'}
          </button>
        </form>
      </section>
    </main>
  )
}

export default LoginForm

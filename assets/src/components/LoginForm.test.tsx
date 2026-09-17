import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import LoginForm from './LoginForm'
import { ApiRequestError } from '../api/client'

describe('LoginForm', () => {
  it('renders labeled username and password fields', () => {
    render(<LoginForm onLogin={vi.fn()} />)

    expect(screen.getByLabelText('Username')).toHaveAttribute(
      'autocomplete',
      'username',
    )
    expect(screen.getByLabelText('Password')).toHaveAttribute(
      'autocomplete',
      'current-password',
    )
  })

  it('trims the username but leaves the password unchanged', async () => {
    const user = userEvent.setup()
    const onLogin = vi.fn().mockResolvedValue(undefined)
    render(<LoginForm onLogin={onLogin} />)

    await user.type(screen.getByLabelText('Username'), '  reviewer  ')
    await user.type(screen.getByLabelText('Password'), '  secret  ')
    await user.click(screen.getByRole('button', { name: 'View org chart' }))

    expect(onLogin).toHaveBeenCalledWith('reviewer', '  secret  ')
  })

  it('disables submission while login is pending', async () => {
    const user = userEvent.setup()
    let finishLogin: (() => void) | undefined
    const onLogin = vi.fn(
      () =>
        new Promise<void>((resolve) => {
          finishLogin = resolve
        }),
    )
    render(<LoginForm onLogin={onLogin} />)

    await user.type(screen.getByLabelText('Username'), 'reviewer')
    await user.type(screen.getByLabelText('Password'), 'secret')
    await user.click(screen.getByRole('button', { name: 'View org chart' }))

    expect(screen.getByRole('button', { name: 'Signing in…' })).toBeDisabled()
    await act(async () => finishLogin?.())
  })

  it('shows one generic error and clears the password after rejection', async () => {
    const user = userEvent.setup()
    const onLogin = vi.fn().mockRejectedValue(new Error('private detail'))
    render(<LoginForm onLogin={onLogin} />)

    await user.type(screen.getByLabelText('Username'), 'reviewer')
    await user.type(screen.getByLabelText('Password'), 'bad password')
    await user.click(screen.getByRole('button', { name: 'View org chart' }))

    expect(
      await screen.findByText('The username or password is incorrect.'),
    ).toBeInTheDocument()
    expect(screen.queryByText('private detail')).not.toBeInTheDocument()
    await waitFor(() => expect(screen.getByLabelText('Password')).toHaveValue(''))
  })
  it('explains throttling without calling it an incorrect password', async () => {
    const user = userEvent.setup()
    render(<LoginForm onLogin={vi.fn().mockRejectedValue(new ApiRequestError(429, { code: 'login_rate_limited' }))} />)
    await user.type(screen.getByLabelText('Username'), 'reviewer')
    await user.type(screen.getByLabelText('Password'), 'secret')
    await user.click(screen.getByRole('button', { name: 'View org chart' }))
    expect(await screen.findByText('Too many sign-in attempts. Please wait a minute and try again.')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toHaveValue('')
  })

})

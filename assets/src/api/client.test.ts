import { describe, expect, it, vi } from 'vitest'

import { ApiRequestError, createApiClient } from './client'

const session = { authenticated: false, csrf_token: 'csrf-token' }

describe('createApiClient', () => {
  it('uses same-origin credentials for every request', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json(session))
      .mockResolvedValueOnce(Response.json({ ...session, authenticated: true }))
      .mockResolvedValueOnce(Response.json(emptyChart()))
      .mockResolvedValueOnce(Response.json(emptyChart()))
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
    const client = createApiClient(fetchMock as typeof fetch)

    await client.session()
    await client.login('reviewer', 'secret', 'csrf-token')
    await client.orgChart()
    await client.refresh('csrf-token')
    await client.logout('csrf-token')

    for (const [, options] of fetchMock.mock.calls) {
      expect(options).toEqual(
        expect.objectContaining({ credentials: 'same-origin' }),
      )
    }
  })

  it('sends JSON and CSRF headers for state-changing requests', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json({ ...session, authenticated: true }))
      .mockResolvedValueOnce(Response.json(emptyChart()))
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
    const client = createApiClient(fetchMock as typeof fetch)

    await client.login('reviewer', 'unchanged password', 'login-csrf')
    await client.refresh('refresh-csrf')
    await client.logout('logout-csrf')

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      '/api/session',
      expect.objectContaining({
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-csrf-token': 'login-csrf',
        },
        body: JSON.stringify({
          username: 'reviewer',
          password: 'unchanged password',
        }),
      }),
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      '/api/org-chart/refresh',
      expect.objectContaining({
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-csrf-token': 'refresh-csrf',
        },
      }),
    )
    expect(fetchMock).toHaveBeenNthCalledWith(
      3,
      '/api/session',
      expect.objectContaining({
        method: 'DELETE',
        headers: { 'x-csrf-token': 'logout-csrf' },
      }),
    )
  })

  it('throws a typed API error for non-success JSON responses', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      Response.json(
        { error: { code: 'invalid_credentials', request_id: 'request-123' } },
        { status: 401 },
      ),
    )
    const client = createApiClient(fetchMock as typeof fetch)

    await expect(client.session()).rejects.toMatchObject({
      name: 'ApiRequestError',
      status: 401,
      code: 'invalid_credentials',
      requestId: 'request-123',
    } satisfies Partial<ApiRequestError>)
  })

  it('classifies a non-JSON server failure without exposing its body', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response('private proxy failure', { status: 502 }),
      )
    const client = createApiClient(fetchMock as typeof fetch)

    try {
      await client.orgChart()
      throw new Error('expected request to fail')
    } catch (error) {
      expect(error).toBeInstanceOf(ApiRequestError)
      expect(error).toMatchObject({ status: 502, code: 'internal_error' })
      expect(String(error)).not.toContain('private proxy failure')
    }
  })
})

function emptyChart() {
  return {
    company: { id: 'company', name: 'Acme' },
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

import type {
  ApiClient,
  ApiError,
  OrgChartResponse,
  Session,
} from './types'

export class ApiRequestError extends Error {
  readonly status: number
  readonly code: string
  readonly requestId?: string

  constructor(status: number, error: ApiError) {
    super(error.message ?? `Request failed with ${error.code}`)
    this.name = 'ApiRequestError'
    this.status = status
    this.code = error.code
    this.requestId = error.request_id
  }
}

export function createApiClient(
  fetchImpl: typeof fetch = window.fetch.bind(window),
): ApiClient {
  return {
    session: () => requestJson<Session>('/api/session'),
    login: (username, password, csrfToken) =>
      requestJson<Session>('/api/session', {
        method: 'POST',
        headers: jsonCsrfHeaders(csrfToken),
        body: JSON.stringify({ username, password }),
      }),
    logout: async (csrfToken) => {
      await request('/api/session', {
        method: 'DELETE',
        headers: { 'x-csrf-token': csrfToken },
      })
    },
    orgChart: () => requestJson<OrgChartResponse>('/api/org-chart'),
    refresh: (csrfToken) =>
      requestJson<OrgChartResponse>('/api/org-chart/refresh', {
        method: 'POST',
        headers: jsonCsrfHeaders(csrfToken),
      }),
  }

  async function requestJson<T>(url: string, options?: RequestInit): Promise<T> {
    const response = await request(url, options)

    try {
      return (await response.json()) as T
    } catch {
      throw new ApiRequestError(response.status, { code: 'internal_error' })
    }
  }

  async function request(url: string, options: RequestInit = {}) {
    const response = await fetchImpl(url, {
      ...options,
      credentials: 'same-origin',
    })

    if (!response.ok) {
      throw await responseError(response)
    }

    return response
  }
}

function jsonCsrfHeaders(csrfToken: string) {
  return {
    'content-type': 'application/json',
    'x-csrf-token': csrfToken,
  }
}

async function responseError(response: Response): Promise<ApiRequestError> {
  try {
    const body = (await response.json()) as { error?: Partial<ApiError> }

    if (typeof body.error?.code === 'string') {
      return new ApiRequestError(response.status, {
        code: body.error.code,
        message:
          typeof body.error.message === 'string'
            ? body.error.message
            : undefined,
        request_id:
          typeof body.error.request_id === 'string'
            ? body.error.request_id
            : undefined,
      })
    }
  } catch {
    // The response body is deliberately not retained in the browser error.
  }

  return new ApiRequestError(response.status, { code: 'internal_error' })
}

export interface Session {
  authenticated: boolean
  csrf_token: string
}

export interface ApiError {
  code: string
  message?: string
  request_id?: string
}

export interface PersonNode {
  id: string
  name: string
  title: string | null
  department: { id: string | null; name: string | null } | null
  manager: { id: string | null; name: string | null } | null
  manager_archived?: boolean
  status: string | null
  employment_type: string | null
  employment_model: string | null
  reports: PersonNode[]
}

export interface OrgChartResponse {
  company: { id: string; name: string }
  roots: PersonNode[]
  warnings: Array<Record<string, unknown> & { code: string }>
  meta: {
    employee_count: number
    root_count: number
    fetched_at: string
    stale: boolean
  }
}

export interface ApiClient {
  session(): Promise<Session>
  login(
    username: string,
    password: string,
    csrfToken: string,
  ): Promise<Session>
  logout(csrfToken: string): Promise<void>
  orgChart(): Promise<OrgChartResponse>
  refresh(csrfToken: string): Promise<OrgChartResponse>
}

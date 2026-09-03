import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import type { OrgChartResponse, PersonNode as Person } from '../api/types'
import OrgChart from './OrgChart'

describe('OrgChart', () => {
  it('renders every person in a recursive, accessible three-level outline', () => {
    const engineer = person('engineer', 'Sam Engineer')
    const manager = person('manager', 'Morgan Manager', [engineer], {
      title: 'Engineering manager',
      department: { id: 'engineering', name: 'Engineering' },
      manager: { id: 'ceo', name: 'Casey Chief' },
      status: 'active',
      employment_type: 'employee',
      employment_model: 'eor',
    })
    const ceo = person('ceo', 'Casey Chief', [manager], {
      title: 'Chief executive officer',
    })

    render(<OrgChart chart={chart([ceo])} {...actions()} />)

    const tree = screen.getByRole('list', { name: 'Organization hierarchy' })
    expect(within(tree).getAllByText('Casey Chief')).toHaveLength(1)
    expect(within(tree).getAllByText('Morgan Manager')).toHaveLength(1)
    expect(within(tree).getAllByText('Sam Engineer')).toHaveLength(1)
    expect(
      within(tree).getByRole('list', { name: 'Direct reports to Casey Chief' }),
    ).toBeInTheDocument()
    expect(
      within(tree).getByRole('list', {
        name: 'Direct reports to Morgan Manager',
      }),
    ).toBeInTheDocument()
    expect(screen.getByText('Engineering manager')).toBeInTheDocument()
    expect(screen.getByText('Engineering')).toBeInTheDocument()
    expect(screen.getByText('Reports to Casey Chief')).toBeInTheDocument()
    expect(screen.getByText('active')).toBeInTheDocument()
    expect(screen.getByText('employee')).toBeInTheDocument()
    expect(screen.getByText('eor')).toBeInTheDocument()
  })

  it('handles missing title and department without empty markup', () => {
    render(<OrgChart chart={chart([person('one', 'One Person')])} {...actions()} />)

    expect(screen.getByText('Title unavailable')).toBeInTheDocument()
    expect(screen.getByText('Department unavailable')).toBeInTheDocument()
    expect(screen.getByText('0 direct reports')).toBeInTheDocument()
  })

  it('shows stale data and readable structural warnings', () => {
    render(
      <OrgChart
        chart={{
          ...chart([person('one', 'One Person')]),
          warnings: [
            { code: 'cycle_detected', employment_ids: ['one', 'two'] },
            { code: 'external_manager' },
            { code: 'future_warning' },
          ],
          meta: { ...chart([]).meta, stale: true },
        }}
        {...actions()}
      />,
    )

    expect(screen.getByRole('status')).toHaveTextContent(
      'Cached data is shown because Remote is temporarily unavailable.',
    )
    expect(screen.getByText(/circular reporting line/i)).toBeInTheDocument()
    expect(screen.getByText(/manager outside this company/i)).toBeInTheDocument()
    expect(screen.getByText(/future_warning/i)).toBeInTheDocument()
  })

  it('shows an explicit empty state', () => {
    render(<OrgChart chart={chart([])} {...actions()} />)

    expect(screen.getByText('No employees were returned.')).toBeInTheDocument()
  })

  it('exposes company metadata and keeps refresh isolated', async () => {
    const user = userEvent.setup()
    const onRefresh = vi.fn()
    const onLogout = vi.fn()
    render(
      <OrgChart
        chart={chart([person('one', 'One Person')])}
        onRefresh={onRefresh}
        onLogout={onLogout}
        refreshing
      />,
    )

    expect(
      screen.getByRole('heading', { name: 'Acme Sandbox Corp' }),
    ).toBeInTheDocument()
    expect(screen.getByText('1 employee')).toBeInTheDocument()
    expect(screen.getByText('1 reporting root')).toBeInTheDocument()
    expect(screen.getByText(/Updated/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Refreshing…' })).toBeDisabled()

    await user.click(screen.getByRole('button', { name: 'Sign out' }))
    expect(onLogout).toHaveBeenCalledOnce()
  })
})

function actions() {
  return { onRefresh: vi.fn(), onLogout: vi.fn(), refreshing: false }
}

function chart(roots: Person[]): OrgChartResponse {
  return {
    company: { id: 'company', name: 'Acme Sandbox Corp' },
    roots,
    warnings: [],
    meta: {
      employee_count: count(roots),
      root_count: roots.length,
      fetched_at: '2026-09-03T12:00:00Z',
      stale: false,
    },
  }
}

function person(
  id: string,
  name: string,
  reports: Person[] = [],
  overrides: Partial<Person> = {},
): Person {
  return {
    id,
    name,
    title: null,
    department: null,
    manager: null,
    status: null,
    employment_type: null,
    employment_model: null,
    reports,
    ...overrides,
  }
}

function count(people: Person[]): number {
  return people.reduce((total, person) => total + 1 + count(person.reports), 0)
}

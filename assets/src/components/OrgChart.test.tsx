import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'

import type { OrgChartResponse, PersonNode as Person } from '../api/types'
import OrgChart from './OrgChart'

describe('OrgChart', () => {
  it('starts both organization groups collapsed and expands them independently', async () => {
    const user = userEvent.setup()
    const report = person('report', 'Riley Report')
    const leader = person('leader', 'Lee Leader', [report])
    const unassigned = person('unassigned', 'Uma Unassigned')

    render(<OrgChart chart={chart([leader, unassigned])} {...actions()} />)

    const reportingGroup = screen
      .getByText('Reporting structure')
      .closest('details')
    const unassignedGroup = screen
      .getByText('No reporting line')
      .closest('details')

    expect(reportingGroup).not.toHaveAttribute('open')
    expect(unassignedGroup).not.toHaveAttribute('open')
    expect(
      within(reportingGroup!.querySelector('summary')!).getByText('2 employees'),
    ).toBeInTheDocument()
    expect(
      within(unassignedGroup!.querySelector('summary')!).getByText('1 employee'),
    ).toBeInTheDocument()

    await user.click(
      within(reportingGroup!).getByText('Reporting structure'),
    )
    await user.click(within(unassignedGroup!).getByText('No reporting line'))

    expect(reportingGroup).toHaveAttribute('open')
    expect(unassignedGroup).toHaveAttribute('open')

    await user.click(
      within(reportingGroup!).getByText('Reporting structure'),
    )

    expect(reportingGroup).not.toHaveAttribute('open')
    expect(unassignedGroup).toHaveAttribute('open')
  })

  it('collapses every parent and reveals one hierarchy level at a time', async () => {
    const user = userEvent.setup()
    const engineer = person('engineer', 'Sam Engineer')
    const manager = person('manager', 'Morgan Manager', [engineer])
    const leader = person('leader', 'Lee Leader', [manager])

    render(<OrgChart chart={chart([leader])} {...actions()} />)

    const reportingGroup = screen
      .getByText('Reporting structure')
      .closest('details')!

    await user.click(within(reportingGroup).getByText('Reporting structure'))

    const leaderCard = screen
      .getByRole('heading', { name: 'Lee Leader' })
      .closest('summary')!
    const managerCard = screen
      .getByRole('heading', { name: 'Morgan Manager' })
      .closest('summary')!
    const leaderDisclosure = leaderCard.closest('details')
    const managerDisclosure = managerCard.closest('details')

    expect(leaderDisclosure).not.toHaveAttribute('open')
    expect(managerDisclosure).not.toHaveAttribute('open')

    await user.click(leaderCard)

    expect(leaderDisclosure).toHaveAttribute('open')
    expect(managerDisclosure).not.toHaveAttribute('open')

    await user.click(managerCard)

    expect(leaderDisclosure).toHaveAttribute('open')
    expect(managerDisclosure).toHaveAttribute('open')
  })

  it('uses the entire parent card as its disclosure summary', async () => {
    const user = userEvent.setup()
    const report = person('report', 'Riley Report')
    const leader = person('leader', 'Lee Leader', [report])

    render(<OrgChart chart={chart([leader])} {...actions()} />)

    await user.click(screen.getByText('Reporting structure'))

    const parentCard = screen
      .getByRole('heading', { name: 'Lee Leader' })
      .closest('summary')!
    const parentDisclosure = parentCard.closest('details')

    expect(parentCard.tagName).toBe('SUMMARY')
    expect(parentDisclosure).not.toHaveAttribute('open')
    expect(within(parentCard).getByText('LL')).toHaveAttribute(
      'aria-hidden',
      'true',
    )
    expect(parentCard).toHaveAccessibleName(
      /Lee Leader.*Title unavailable.*Department unavailable.*1 direct report/,
    )
    expect(within(parentCard).getByText('1 direct report')).toBeInTheDocument()
    expect(within(parentCard).queryByRole('button')).not.toBeInTheDocument()
    expect(screen.getByText('Riley Report')).not.toBeVisible()

    await user.click(parentCard)

    expect(parentDisclosure).toHaveAttribute('open')
    expect(screen.getByText('Riley Report')).toBeVisible()
  })

  it('distinguishes direct reports from all nested reports', async () => {
    const user = userEvent.setup()
    const engineeringManager = person('engineering-manager', 'Evan Manager', [
      person('engineer-one', 'Riley Engineer'),
      person('engineer-two', 'Sam Engineer'),
    ])
    const financeManager = person('finance-manager', 'Finley Manager', [
      person('accountant', 'Alex Accountant'),
    ])
    const leader = person('leader', 'Lee Leader', [
      engineeringManager,
      financeManager,
    ])

    render(<OrgChart chart={chart([leader])} {...actions()} />)

    await user.click(screen.getByText('Reporting structure'))

    const leaderCard = screen
      .getByRole('heading', { name: 'Lee Leader' })
      .closest('summary')!
    const engineeringManagerCard = screen
      .getByRole('heading', { name: 'Evan Manager' })
      .closest('summary')!
    const financeManagerCard = screen
      .getByRole('heading', { name: 'Finley Manager' })
      .closest('summary')!

    expect(
      within(leaderCard).getByText('2 direct · 5 total reports'),
    ).toBeInTheDocument()
    expect(
      within(engineeringManagerCard).getByText('2 direct reports'),
    ).toBeInTheDocument()
    expect(
      within(financeManagerCard).getByText('1 direct report'),
    ).toBeInTheDocument()
  })

  it('marks only roots without a manager or reports as having no reporting line', () => {
    const external = person('external', 'Erin External', [], {
      manager: { id: 'outside-company', name: 'Outside Manager' },
    })
    const unassigned = person('unassigned', 'Uma Unassigned')

    render(<OrgChart chart={chart([external, unassigned])} {...actions()} />)

    const reportingGroup = screen
      .getByText('Reporting structure')
      .closest('details')
    const unassignedGroup = screen
      .getByText('No reporting line')
      .closest('details')

    expect(within(reportingGroup!).getByText('Erin External')).toBeInTheDocument()
    expect(within(unassignedGroup!).getByText('Uma Unassigned')).toBeInTheDocument()
    expect(
      within(unassignedGroup!).getByText('No manager assigned'),
    ).toBeInTheDocument()
    expect(
      within(reportingGroup!).queryByText('No manager assigned'),
    ).not.toBeInTheDocument()
  })

  it('hides archived employees by default and reveals them on request', async () => {
    const user = userEvent.setup()
    const activeReport = person('active-report', 'Avery Active', [], {
      manager: { id: 'archived-manager', name: 'Morgan Archived' },
      manager_archived: true,
      status: 'active',
    })
    const archivedManager = person(
      'archived-manager',
      'Morgan Archived',
      [],
      {
        manager: { id: 'leader', name: 'Lee Leader' },
        status: 'ARCHIVED',
      },
    )
    const leader = person('leader', 'Lee Leader', [archivedManager], {
      status: 'active',
    })

    render(<OrgChart chart={chart([leader, activeReport])} {...actions()} />)

    const archivedToggle = screen.getByRole('checkbox', {
      name: 'Show archived employees',
    })
    const summary = screen.getByLabelText('Organization summary')

    expect(archivedToggle).not.toBeChecked()
    const unassignedGroup = screen.getByText('No reporting line').closest('details')!
    expect(within(unassignedGroup).getByText('Avery Active')).toBeInTheDocument()
    expect(screen.queryByText('Morgan Archived')).not.toBeInTheDocument()
    expect(screen.getByText('Avery Active')).toBeInTheDocument()
    expect(within(summary).getByText('2 employees')).toBeInTheDocument()
    expect(within(summary).getByText('2 reporting roots')).toBeInTheDocument()

    await user.click(archivedToggle)

    expect(archivedToggle).toBeChecked()
    expect(within(unassignedGroup).getByText('Avery Active')).toBeInTheDocument()
    expect(screen.getByText('Morgan Archived')).toBeInTheDocument()
    expect(within(summary).getByText('3 employees')).toBeInTheDocument()
    expect(within(summary).getByText('2 reporting roots')).toBeInTheDocument()
  })

  it('keeps the team together when its manager reports to an archived employee', () => {
    const report = person('report', 'Riley Report', [], {
      manager: { id: 'active-manager', name: 'Avery Active' },
    })
    const activeManager = person('active-manager', 'Avery Active', [report], {
      manager: { id: 'archived', name: 'Morgan Archived' },
      manager_archived: true,
    })
    const archived = person('archived', 'Morgan Archived', [], { status: 'archived' })
    render(<OrgChart chart={chart([archived, activeManager])} {...actions()} />)
    const group = screen.getByText('No reporting line').closest('details')!
    expect(within(group).getByText('Avery Active')).toBeInTheDocument()
    expect(within(group).getByText('Riley Report')).toBeInTheDocument()
    expect(within(group).getByText('2 employees')).toBeInTheDocument()
    expect(within(group).getByText('Manager archived')).toBeInTheDocument()
    const team = within(group).getByText('Avery Active').closest('details')!
    expect(within(team).getByText('Riley Report')).toBeInTheDocument()
  })

  it('renders every person in a recursive, accessible three-level outline', async () => {
    const user = userEvent.setup()
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

    await user.click(screen.getByText('Reporting structure'))
    await user.click(
      screen.getByRole('heading', { name: 'Casey Chief' }).closest('summary')!,
    )
    await user.click(
      screen
        .getByRole('heading', { name: 'Morgan Manager' })
        .closest('summary')!,
    )

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
    const summary = screen.getByLabelText('Organization summary')
    expect(within(summary).getByText('1 employee')).toBeInTheDocument()
    expect(within(summary).getByText('1 reporting root')).toBeInTheDocument()
    expect(within(summary).getByText(/Updated/)).toBeInTheDocument()
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

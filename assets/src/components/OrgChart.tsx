import { useMemo } from 'react'

import type { OrgChartResponse, PersonNode as Person } from '../api/types'
import PersonNode from './PersonNode'
import WarningList from './WarningList'

interface OrgChartProps {
  chart: OrgChartResponse
  refreshing: boolean
  refreshError?: { message: string; requestId?: string }
  onRefresh(): void
  onLogout(): void
}

function OrgChart({
  chart,
  refreshing,
  refreshError,
  onRefresh,
  onLogout,
}: OrgChartProps) {
  const { reportingRoots, unassignedRoots } = partitionRoots(chart.roots)
  const reportTotals = useMemo(
    () => calculateReportTotals(chart.roots),
    [chart.roots],
  )

  return (
    <main className="app-shell">
      <header className="chart-header">
        <div>
          <h1>{chart.company.name}</h1>
          <div className="chart-meta" aria-label="Organization summary">
            <span>{pluralize(chart.meta.employee_count, 'employee')}</span>
            <span>{pluralize(chart.meta.root_count, 'reporting root')}</span>
            <span>Updated {formatTimestamp(chart.meta.fetched_at)}</span>
          </div>
        </div>
        <div className="chart-actions">
          <button type="button" onClick={onRefresh} disabled={refreshing}>
            {refreshing ? 'Refreshing…' : 'Refresh data'}
          </button>
          <button
            type="button"
            className="button-secondary"
            onClick={onLogout}
          >
            Sign out
          </button>
        </div>
      </header>

      {chart.meta.stale && (
        <p className="stale-notice" role="status">
          Cached data is shown because Remote is temporarily unavailable.
        </p>
      )}

      {refreshError && (
        <div className="inline-error" role="alert">
          <p>{refreshError.message}</p>
          {refreshError.requestId && (
            <p className="request-id">Request ID: {refreshError.requestId}</p>
          )}
        </div>
      )}

      <WarningList warnings={chart.warnings} />

      <section className="chart-region" aria-labelledby="chart-heading">
        <h2 id="chart-heading">Organization groups</h2>
        {chart.roots.length === 0 ? (
          <div className="empty-state">
            <p>No employees were returned.</p>
            <p>Refresh the data or confirm the configured company has employments.</p>
          </div>
        ) : (
          <div className="organization-groups">
            <details className="chart-group chart-group--reporting">
              <summary>
                <span className="chart-group__title">Reporting structure</span>
                <span className="chart-group__count">
                  {pluralize(countPeople(reportingRoots), 'employee')}
                </span>
              </summary>
              <div className="chart-group__body">
                <ul className="org-tree" aria-label="Organization hierarchy">
                  {reportingRoots.map((root) => (
                    <PersonNode
                      key={root.id}
                      person={root}
                      reportTotals={reportTotals}
                    />
                  ))}
                </ul>
              </div>
            </details>

            <details className="chart-group chart-group--unassigned">
              <summary>
                <span className="chart-group__title">No reporting line</span>
                <span className="chart-group__count">
                  {pluralize(unassignedRoots.length, 'employee')}
                </span>
              </summary>
              <div className="chart-group__body">
                <ul
                  className="org-tree"
                  aria-label="Employees without a reporting line"
                >
                  {unassignedRoots.map((root) => (
                    <PersonNode
                      key={root.id}
                      person={root}
                      reportTotals={reportTotals}
                      unassigned
                    />
                  ))}
                </ul>
              </div>
            </details>
          </div>
        )}
      </section>
    </main>
  )
}

function partitionRoots(roots: Person[]) {
  return roots.reduce(
    (groups, root) => {
      if (root.manager === null && root.reports.length === 0) {
        groups.unassignedRoots.push(root)
      } else {
        groups.reportingRoots.push(root)
      }

      return groups
    },
    { reportingRoots: [] as Person[], unassignedRoots: [] as Person[] },
  )
}

function countPeople(people: Person[]): number {
  return people.reduce(
    (total, person) => total + 1 + countPeople(person.reports),
    0,
  )
}

function calculateReportTotals(roots: Person[]): ReadonlyMap<Person, number> {
  const totals = new Map<Person, number>()

  function visit(person: Person): number {
    const total = person.reports.reduce(
      (count, report) => count + 1 + visit(report),
      0,
    )
    totals.set(person, total)
    return total
  }

  roots.forEach(visit)
  return totals
}

function pluralize(count: number, singular: string) {
  return `${count} ${singular}${count === 1 ? '' : 's'}`
}

function formatTimestamp(timestamp: string) {
  const date = new Date(timestamp)

  if (Number.isNaN(date.getTime())) return 'at an unknown time'

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

export default OrgChart

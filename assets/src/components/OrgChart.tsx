import type { OrgChartResponse } from '../api/types'
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
        <h2 id="chart-heading">Reporting structure</h2>
        {chart.roots.length === 0 ? (
          <div className="empty-state">
            <p>No employees were returned.</p>
            <p>Refresh the data or confirm the configured company has employments.</p>
          </div>
        ) : (
          <ul className="org-tree" aria-label="Organization hierarchy">
            {chart.roots.map((root) => (
              <PersonNode key={root.id} person={root} />
            ))}
          </ul>
        )}
      </section>
    </main>
  )
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

import { useId } from 'react'

import type { PersonNode as Person } from '../api/types'

interface PersonNodeProps {
  person: Person
  reportTotals: ReadonlyMap<Person, number>
  unassigned?: boolean
}

function PersonNode({
  person,
  reportTotals,
  unassigned = false,
}: PersonNodeProps) {
  const reportCount = person.reports.length
  const totalReportCount = reportTotals.get(person) ?? reportCount
  const reportListId = useId()

  return (
    <li className="person-branch">
      {reportCount > 0 ? (
        <details className="person-disclosure">
          <summary
            className="person-card person-card--parent"
            aria-controls={reportListId}
          >
            <PersonCardContents
              person={person}
              reportCount={reportCount}
              totalReportCount={totalReportCount}
              unassigned={unassigned}
            />
          </summary>
          <ul
            id={reportListId}
            className="report-list"
            aria-label={`Direct reports to ${person.name}`}
          >
            {person.reports.map((report) => (
              <PersonNode
                key={report.id}
                person={report}
                reportTotals={reportTotals}
              />
            ))}
          </ul>
        </details>
      ) : (
        <article
          className={`person-card${unassigned ? ' person-card--unassigned' : ''}`}
          aria-label={`Employee: ${person.name}`}
        >
          <PersonCardContents
            person={person}
            reportCount={reportCount}
            totalReportCount={totalReportCount}
            unassigned={unassigned}
          />
        </article>
      )}
    </li>
  )
}

function PersonCardContents({
  person,
  reportCount,
  totalReportCount,
  unassigned,
}: {
  person: Person
  reportCount: number
  totalReportCount: number
  unassigned: boolean
}) {
  const reportNoun = reportCount === 1 ? 'report' : 'reports'
  const reportLabel =
    totalReportCount > reportCount
      ? `${reportCount} direct · ${totalReportCount} total reports`
      : `${reportCount} direct ${reportNoun}`

  return (
    <>
      <span className="person-card__identity">
        <span className="person-name" role="heading" aria-level={3}>
          {person.name}
        </span>
        <span className="person-title">
          {person.title ?? 'Title unavailable'}
        </span>
        <span className="person-department">
          {person.department?.name ?? 'Department unavailable'}
        </span>
        {person.manager?.name && (
          <span className="manager-line">Reports to {person.manager.name}</span>
        )}
      </span>

      <span className="person-card__footer">
        <span className="badges" aria-label="Employment details">
          {unassigned && (
            <span className="assignment-state">No manager assigned</span>
          )}
          {person.status && <span>{person.status}</span>}
          {person.employment_type && <span>{person.employment_type}</span>}
          {person.employment_model && <span>{person.employment_model}</span>}
        </span>
        <span className="report-count">{reportLabel}</span>
      </span>
    </>
  )
}

export default PersonNode

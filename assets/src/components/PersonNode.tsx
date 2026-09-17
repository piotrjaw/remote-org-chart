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
  const archivedClass = person.status?.trim().toLocaleLowerCase() === 'archived'
    ? ' person-card--archived'
    : ''

  return (
    <li className="person-branch">
      {reportCount > 0 ? (
        <details className="person-disclosure">
          <summary
            className={`person-card person-card--parent${archivedClass}`}
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
          className={`person-card${unassigned ? ' person-card--unassigned' : ''}${archivedClass}`}
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
      <span className="person-avatar" aria-hidden="true">
        {personInitials(person.name)}
      </span>

      <span className="person-card__content">
        <span className="person-name" role="heading" aria-level={3}>
          {person.name}
        </span>
        <span className="person-role">
          <span className="person-title">
            {person.title ?? 'Title unavailable'}
          </span>
          <span className="person-department">
            {person.department?.name ?? 'Department unavailable'}
          </span>
        </span>
        {unassigned ? (
          <span className="manager-line">
            {person.manager_archived
              ? `No reporting line: ${person.manager?.name ? `manager ${person.manager.name} is archived` : 'the assigned manager is archived'}.`
              : 'No reporting line: no manager is assigned in Remote.'}
          </span>
        ) : (
          <span className="manager-line">
            {person.manager
              ? person.manager.name
                ? `${person.manager_archived ? 'Archived manager: ' : 'Reports to '}${person.manager.name}`
                : 'Reports to an assigned manager (name unavailable)'
              : 'No manager assigned'}
          </span>
        )}
        <span className="badges" aria-label="Employment details">
          {unassigned && (
            <span className="assignment-state">
              {person.manager_archived ? 'Manager archived' : 'No manager assigned'}
            </span>
          )}
          {person.status && <span className="employment-status">{chipLabel(person.status)}</span>}
          {person.employment_type && <span>{chipLabel(person.employment_type)}</span>}
          {person.employment_model && <span>{chipLabel(person.employment_model)}</span>}
        </span>
        <span className="report-count">{reportLabel}</span>
      </span>
    </>
  )
}

function chipLabel(value: string): string {
  return value.trim().toLowerCase().split(/[_\s-]+/).map((word, index) => {
    if (['eor', 'peo', 'cor'].includes(word)) return word.toUpperCase()
    return index === 0 ? word.charAt(0).toUpperCase() + word.slice(1) : word
  }).join(' ')
}

function personInitials(name: string): string {
  const nameParts = name.trim().split(/\s+/).filter(Boolean)
  const firstInitial = nameParts[0]?.[0] ?? '?'
  const lastInitial = nameParts.length > 1 ? nameParts.at(-1)?.[0] : ''

  return `${firstInitial}${lastInitial}`.toLocaleUpperCase()
}

export default PersonNode

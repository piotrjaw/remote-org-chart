import type { PersonNode as Person } from '../api/types'

interface PersonNodeProps {
  person: Person
}

function PersonNode({ person }: PersonNodeProps) {
  const reportCount = person.reports.length

  return (
    <li className="person-branch">
      <article className="person-card" aria-label={`Employee: ${person.name}`}>
        <div className="person-card__identity">
          <h2>{person.name}</h2>
          <p className="person-title">{person.title ?? 'Title unavailable'}</p>
          <p className="person-department">
            {person.department?.name ?? 'Department unavailable'}
          </p>
          {person.manager?.name && (
            <p className="manager-line">Reports to {person.manager.name}</p>
          )}
        </div>

        <div className="person-card__footer">
          <div className="badges" aria-label="Employment details">
            {person.status && <span>{person.status}</span>}
            {person.employment_type && <span>{person.employment_type}</span>}
            {person.employment_model && <span>{person.employment_model}</span>}
          </div>
          <p className="report-count">
            {reportCount} direct {reportCount === 1 ? 'report' : 'reports'}
          </p>
        </div>
      </article>

      {reportCount > 0 && (
        <ul
          className="report-list"
          aria-label={`Direct reports to ${person.name}`}
        >
          {person.reports.map((report) => (
            <PersonNode key={report.id} person={report} />
          ))}
        </ul>
      )}
    </li>
  )
}

export default PersonNode

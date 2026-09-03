interface WarningListProps {
  warnings: Array<Record<string, unknown> & { code: string }>
}

const messages: Record<string, string> = {
  missing_id: 'An employee record without an ID could not be displayed.',
  missing_name: 'An employee is displayed with a placeholder name.',
  duplicate_id: 'A duplicate employee record was ignored.',
  self_manager: 'A self-referencing reporting line was moved to the top level.',
  external_manager: 'A reporting line points to a manager outside this company.',
  unresolved_manager: 'A manager could not be matched to an employee record.',
  cycle_detected: 'A circular reporting line was safely moved to the top level.',
}

function WarningList({ warnings }: WarningListProps) {
  if (warnings.length === 0) return null

  return (
    <section className="warning-panel" aria-labelledby="warning-heading">
      <h2 id="warning-heading">Data notes</h2>
      <ul>
        {warnings.map((warning, index) => (
          <li key={`${warning.code}-${index}`}>
            {messages[warning.code] ?? (
              <>
                An organization data issue was detected: <code>{warning.code}</code>.
              </>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}

export default WarningList

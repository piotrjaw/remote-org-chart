# Remote API fixtures

These fixtures model the documented responses from:

- `GET /v1/identity/current`
- `GET /v1/employments/bulk?limit=100`

They are synthetic. Names, emails, IDs, and cursor values do not identify real
people or Remote accounts. Email addresses use the reserved `.test` domain.

The employment records intentionally contain only the fields needed by the org
chart plus `files: null`, which the bulk endpoint documents as its fixed value.
The real endpoint returns additional full-employment fields. Application code
must ignore and must not expose those fields.

## Complex scenario

`employments_bulk_complex_page_1.json` through
`employments_bulk_complex_page_3.json` form one cursor-paginated response with
30 employments. Follow `next_cursor` until it is `null`.

Expected characteristics:

- 30 unique employment IDs.
- 26 resolvable manager-to-report edges.
- Four rendered roots after graceful recovery:
  - Ada North: the organizational root.
  - Kenji Sato: references an employment ID absent from the dataset.
  - Aisha Bello: has a named external manager but no Remote employment ID.
  - Rowan Lee: has no manager.
- Maximum resolved depth is five nodes: Ada North -> Marta Zielińska -> Linh
  Nguyễn -> Kwame Mensah -> Łukasz Nowak.
- Ada North has six direct reports, exercising a wide branch.
- Mei Tan appears on page 2 while her manager, Anika Rao, appears on page 3.
- Two distinct department IDs share the name `Platform`.
- Gabriel Silva has a department ID without a department name.
- Kenji Sato has a department name without a department ID.
- Tom Becker has no job title; Rowan Lee has no work email.
- A mix of employee, contractor, direct-employee, and global-payroll records.
- A mix of active, invited, pending, offboarding, and archived statuses.
- Names include diacritics and non-ASCII characters.

Manager IDs are authoritative when present. Human-readable manager names may
be stale: Mei Tan's manager is named `Anika R.` but resolves by ID to Anika Rao.

## Pathological scenario

`employments_bulk_pathological.json` is a single terminal page. It contains:

- one self-reference;
- one three-node cycle;
- two records with the same employment ID;
- one record without an ID;
- one record with a blank name.

This scenario is not meant for the demo UI. It exists to verify that hierarchy
construction terminates, reports warnings, and keeps valid records visible.

# Remote Org Chart Design

Date: 2026-09-03

## Purpose

Build a small, publicly deployed take-home application that reads company and
employment data from Remote's sandbox API and renders manager-to-report
relationships. The project should demonstrate clear Elixir boundaries and
defensive data handling without adding a database or production-scale
infrastructure.

The deployed application is protected by a custom username/password screen.
Those application credentials and the Remote API token are runtime environment
variables. The browser never receives the Remote token.

## Success criteria

- A reviewer can sign in, view the complete organization, refresh it, and sign
  out.
- Every Remote employment remains visible even if optional fields or reporting
  relationships are incomplete.
- Manager relationships are built from `manager_employment_id` and malformed
  graphs cannot hang or crash the application.
- Remote pagination, failures, and rate limits are handled explicitly.
- Repeated page loads normally use a short-lived in-memory cache.
- The repository runs locally against synthetic fixtures before API access is
  available and can switch explicitly to the live sandbox API later.
- One Dockerized Phoenix release serves the API and compiled React SPA on
  Render without a database.

## Scope

The first version includes:

- environment-backed application authentication;
- a Remote API client and fixture-backed substitute;
- normalization and hierarchy construction;
- an in-memory snapshot cache;
- a small JSON API;
- a React/TypeScript login screen and readable hierarchical view;
- automated backend and frontend tests;
- Docker and Render deployment documentation.

The following are intentionally out of scope:

- account registration, password reset, roles, or credential persistence;
- Remote OAuth, Remote MCP at runtime, or multi-company selection;
- a database, Redis, background synchronization, or webhooks;
- distributed caching or more than one Render instance;
- editing Remote data;
- elaborate chart interactions or extensive visual polish.

## Repository and runtime architecture

The repository root is a Phoenix application generated without Ecto, LiveView,
or a mailer. A Vite React/TypeScript application lives under `assets/`.

During development, Phoenix runs on port 4000 and Vite runs on port 5173. Vite
proxies `/api` to Phoenix. In production, Vite builds into Phoenix's static
asset directory and Phoenix serves both the SPA and JSON API from one origin.
This removes CORS configuration and keeps cookie behavior straightforward.

The production artifact is a multi-stage Docker image: Node builds the SPA,
Elixir builds an OTP release, and a minimal runtime image starts that release.
Render runs one Docker web service and checks an unauthenticated `/api/health`
endpoint. The health response contains no company or configuration data.

## Configuration

Runtime configuration is centralized in `config/runtime.exs`.

Required in production:

- `SECRET_KEY_BASE`
- `PHX_HOST`
- `APP_USERNAME`
- `APP_PASSWORD`
- `REMOTE_API_TOKEN`
- `REMOTE_DATA_SOURCE=api`

Optional:

- `PORT`, supplied by Render
- `REMOTE_API_BASE_URL`, defaulting to
  `https://gateway.remote-sandbox.com`
- `REMOTE_CACHE_TTL_SECONDS`, defaulting to `300`

Development sets `REMOTE_DATA_SOURCE` explicitly to either `api` or `fixture`.
It does not silently fall back to fixtures when an API token is bad or missing.
Tests always inject controlled clients and configuration.

An `.env.example` documents names and safe placeholder values. Real secrets are
ignored by Git and are never printed by setup scripts.

## Authentication and session flow

`RemoteOrgChart.Auth` is the public authentication boundary. Its initial
credential provider reads the configured username and password from runtime
application configuration. Both submitted values and configured values are
hashed to fixed-length digests before constant-time comparison. Invalid
credentials always return the same generic response.

Authentication uses Phoenix's encrypted and signed cookie session store. The
cookie is HTTP-only, secure in production, same-site, and renewed after a
successful login to prevent session fixation. There is no server-side session
table.

Routes:

- `GET /api/session` returns authentication state and a CSRF token. This is
  public and initializes the browser session.
- `POST /api/session` validates credentials and renews the session.
- `DELETE /api/session` clears the authenticated session.
- `GET /api/org-chart` returns the cached or newly fetched chart.
- `POST /api/org-chart/refresh` forces a new Remote snapshot.
- `GET /api/health` is public and returns only service health.

State-changing requests include the CSRF token obtained from
`GET /api/session`. Protected routes pass through one authentication plug and
return JSON `401` responses rather than redirects.

Login rate limiting is not included in this bounded take-home. The README will
call this out as a production hardening step.

## Remote integration

`RemoteOrgChart.Remote` is the public data-source boundary. It invokes the
configured provider and passes that provider's Remote-shaped result through
`RemoteOrgChart.Remote.Mapper`, a pure projection into the normalized company
and person structs.

`RemoteOrgChart.Remote.Client` is the HTTP provider. It uses `Req` with a
bearer token, finite timeouts, and JSON decoding.

The HTTP implementation performs:

1. `GET /v1/identity/current` for `data.company.id` and
   `data.company.name`.
2. `GET /v1/employments/bulk?company_id=...&limit=100`.
3. Additional bulk calls using the opaque `next_cursor` until it is `null`.

The client tracks seen cursor values. A repeated cursor is treated as an
invalid upstream response rather than creating an infinite loop. Any failed
page fails the new snapshot atomically.

The bulk endpoint returns full employment records even though the application
needs only a small subset. The client immediately retains only:

- `id`
- `company_id`
- `full_name`
- `job_title`
- `department` and `department_id`
- `manager` and `manager_employment_id`
- `status`, `type`, and `employment_model`

Manager and work emails are discarded because the application does not need to
display them. Raw responses, tokens, names, and email addresses are not logged.
Operational logs may include request duration, page count, record count,
response class, cache status, and warning count.

`RemoteOrgChart.Remote.FixtureClient` implements the same operation by reading
the committed cursor-page fixtures. Fixture and HTTP results therefore exercise
the same mapper. The fixture provider is for explicit local development and
tests only.

## Normalized model and hierarchy

The normalization layer converts permissive upstream maps into internal
company and person structs. Optional strings are trimmed. Blank names become
`Unknown employee`; missing IDs cause a record to be skipped with a warning.
Unknown extra Remote fields are ignored.

Each normalized person carries a manager summary containing the employment ID
and name when available. The hierarchy uses the manager employment ID as the
authoritative relationship. A manager name may still be shown when no Remote
employment ID exists.

`RemoteOrgChart.Hierarchy.build/1` constructs a deterministic forest:

1. Normalize all pages before resolving any relationships, allowing a report's
   manager to appear on a later page.
2. Deduplicate by employment ID. The first record wins and a warning records
   every duplicate.
3. Convert self-references into roots with a warning.
4. Convert missing manager IDs into roots. If a manager name exists, classify
   the relationship as external; if an ID exists but is absent, classify it as
   unresolved.
5. Detect cycles in the manager-pointer graph. Break the edge belonging to the
   lexicographically smallest employment ID in each cycle and emit one warning
   listing that cycle's IDs.
6. Build nested reports and sort every root/report list by case-insensitive
   display name, then ID.

All statuses returned by Remote remain visible. Non-active status and
employment type are preserved so the UI can distinguish them instead of
silently dropping people.

Warnings use stable codes such as `missing_id`, `missing_name`, `duplicate_id`,
`self_manager`, `external_manager`, `unresolved_manager`, and
`cycle_detected`. They contain IDs and structural context but do not expose
personal email addresses.

## Cache behavior

`RemoteOrgChart.RemoteCache` is one supervised GenServer that stores the
complete normalized hierarchy snapshot, not the sensitive raw Remote response.
The cache has one key because this application serves one configured company.

- A fresh cached snapshot is returned immediately.
- A missing or expired snapshot triggers one fetch. GenServer serialization
  prevents concurrent callers from issuing duplicate Remote requests.
- A successful fetch atomically replaces the snapshot and timestamp.
- A forced refresh bypasses freshness but still replaces the value only after
  a complete successful fetch.
- Timeouts, `429`, and upstream `5xx` responses may return an existing stale
  snapshot marked `stale: true`.
- `401`, `403`, invalid JSON, or invalid response structure never fall back to
  stale data; they surface a configuration/integration error.
- The cache is empty after restart or deployment by design.

Browser responses use `Cache-Control: no-store`; authenticated organization
data is cached only inside Phoenix.

## JSON API shape

The org-chart endpoint returns:

```json
{
  "company": { "id": "...", "name": "Acme Sandbox Corp" },
  "roots": [
    {
      "id": "...",
      "name": "Ada North",
      "title": "Chief Executive Officer",
      "department": null,
      "manager": null,
      "status": "active",
      "employment_type": "employee",
      "reports": []
    }
  ],
  "warnings": [],
  "meta": {
    "employee_count": 1,
    "root_count": 1,
    "fetched_at": "2026-09-03T12:00:00Z",
    "stale": false
  }
}
```

The controller is an HTTP adapter only: it calls the cache, maps typed errors
to status codes, sets response headers, and renders JSON. Remote access,
normalization, and hierarchy logic remain outside controllers.

## Error handling

- Invalid application credentials: `401 invalid_credentials`.
- Missing application session: `401 authentication_required`.
- Remote `401` or `403`: `502 remote_authentication_failed` with no upstream
  body exposed.
- Remote timeout, `429`, or `5xx` without stale data: `503
  remote_temporarily_unavailable`. Preserve a safe `Retry-After` value for
  `429` when available.
- Invalid Remote JSON or schema: `502 invalid_remote_response`.
- Unexpected internal errors: `500 internal_error` with a request ID.

The React application renders friendly messages and retry controls for these
classes. A `401 authentication_required` returns the user to the login screen.

## Frontend

The initial React/TypeScript UI is intentionally modest:

- session bootstrap and login form;
- app header with company name, refresh, cache timestamp, stale indicator, and
  logout;
- loading, empty, warning, and error states;
- a recursive semantic tree/outline of person cards showing name, title,
  department, status, employment type, and direct reports.

The first implementation favors readable responsive behavior over a heavy
chart library. The component boundary allows replacing the renderer later
without changing the API.

Frontend API calls use a small typed client, same-origin credentials, and the
session-provided CSRF token for state-changing requests. The Remote API token
and Remote response types do not exist in the browser bundle.

## Testing

Backend tests use ExUnit and injected Remote clients:

- fixture parsing and cursor traversal, including a manager on a later page;
- normalization of missing and blank fields;
- deterministic hierarchy construction for the complex fixture;
- duplicate, self-reference, dangling-manager, and cycle recovery;
- cache hit, expiry, forced refresh, single-flight behavior, and stale fallback
  policy;
- authentication comparison and session lifecycle;
- controller status/error mapping and CSRF protection.

Remote HTTP tests use an injected `Req` test adapter and never call the real
API. Cache time is injectable so TTL tests do not sleep.

Frontend tests use Vitest and Testing Library for login, authenticated loading,
tree rendering, warnings, refresh, stale data, and session expiry. Final
verification also includes a local production-image smoke test and a deployed
Render login/org-chart smoke test.

## Deployment

Render is the documented target. The repository contains a Dockerfile,
`.dockerignore`, a health check, and either a small Render Blueprint or exact
dashboard instructions. Secrets are entered in Render and are never committed.

The smallest always-on Render web service is sufficient. A free instance uses
the identical image and can be selected during development, but its cold start
is unsuitable for the review link.

The README documents local fixture mode, local API mode, tests, production
build, Render configuration, assumptions, limitations, and how to rotate the
application password and Remote token.

## Live-data validation

When the sandbox token becomes available, perform a read-only audit before
changing fixtures or application assumptions:

1. Confirm token identity without printing the token.
2. Read `total_count` from `GET /v1/employments?page_size=1`.
3. Inspect one bulk page only for field presence, null rates, status/type
   distribution, department count, and manager-link coverage.
4. Redact names and emails from diagnostics.
5. Compare the live shape with the fixtures and update normalization tests if
   the documented and observed contracts differ.

No live response body is committed to the repository.

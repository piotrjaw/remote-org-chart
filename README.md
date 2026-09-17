# Remote organization chart

A small take-home application that reads company and employment data from Remote,
recovers a safe manager-to-report hierarchy, and presents it behind a custom reviewer
login. Phoenix owns authentication, Remote access, normalization, caching, and the JSON
API. A React/TypeScript SPA owns the login and semantic tree UI. There is no database.

The production artifact is one Dockerized Phoenix release. It serves both `/api/*` and
the compiled SPA from the same origin, so the Remote token never enters the browser and
no CORS setup is needed.

## Architecture

```text
Browser (React SPA)
  │ encrypted cookie + CSRF
  ▼
Phoenix controllers ── RemoteCache (one normalized snapshot)
  │                         │
  │                     Remote + Hierarchy
  │                         │
  └── environment auth      ├── FixtureClient (local/test)
                            └── Client (Remote sandbox API)
```

Important boundaries:

- `RemoteOrgChart.Auth` looks like an authentication service to the web layer. Its
  current provider compares credentials configured from `APP_USERNAME` and
  `APP_PASSWORD`; it does not persist users.
- `RemoteOrgChart.Remote.Mapper` is the privacy boundary. Full Remote records are
  projected immediately into a small internal model.
- `RemoteOrgChart.Hierarchy` is pure and repairs malformed manager graphs
  deterministically.
- `RemoteOrgChart.RemoteCache` stores only the normalized chart in memory.
- Controllers adapt these services to HTTP; they do not acquire or reshape Remote data.

## Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
- Node.js 22+ and npm 10+
- Docker for the production-image smoke test

Install dependencies:

```bash
mix setup
```

## Run locally with synthetic fixtures

The committed fixtures contain 30 synthetic people over three cursor pages, including
late-page managers and malformed relationship examples. They use only reserved
`.example.test` email addresses.

Start Phoenix in one terminal:

```bash
APP_USERNAME=reviewer \
APP_PASSWORD=local-review-password \
REMOTE_DATA_SOURCE=fixture \
mix phx.server
```

Start Vite in a second terminal:

```bash
npm run dev --prefix assets
```

Open <http://127.0.0.1:5173> and sign in with the values you assigned above. Vite
proxies `/api` to Phoenix on port 4000.

## Run locally against Remote

Use the Remote API token from the sandbox credentials. This mode never falls back to
fixtures if the token or upstream request fails.

```bash
APP_USERNAME=reviewer \
APP_PASSWORD=local-review-password \
REMOTE_DATA_SOURCE=api \
REMOTE_API_TOKEN=replace-with-your-sandbox-token \
mix phx.server
```

Run Vite as shown above. Do not put live values in `.env.example` or commit a local
`.env` file.

## Test and build

```bash
mix format --check-formatted
mix test
npm test --prefix assets
npm run lint --prefix assets
npm run build --prefix assets
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

`mix assets.deploy` uses `npm ci`, builds Vite into `priv/static`, and creates compressed
Phoenix digests. Generated assets and release directories are ignored by Git.

## Configuration

| Variable | Development | Production | Default / purpose |
| --- | --- | --- | --- |
| `APP_USERNAME` | required | required | Reviewer login username |
| `APP_PASSWORD` | required | required | Reviewer login password |
| `REMOTE_DATA_SOURCE` | `fixture` or `api` | must be `api` | Explicit data provider |
| `REMOTE_API_TOKEN` | required in API mode | required | Server-only Remote bearer token |
| `REMOTE_WEBHOOK_SIGNING_KEY` | optional | required | Signing key returned when the Remote webhook callback is created |
| `REMOTE_API_BASE_URL` | optional | optional | `https://gateway.remote-sandbox.com` |
| `REMOTE_CACHE_TTL_SECONDS` | optional | optional | `300`; non-negative integer |
| `SECRET_KEY_BASE` | from `dev.exs` | required, at least 64 bytes | Encrypts/signs cookies |
| `PHX_HOST` | not used | optional | Custom public hostname without scheme; defaults to Render's `RENDER_EXTERNAL_HOSTNAME` |
| `RENDER_EXTERNAL_HOSTNAME` | not used | supplied by Render | Assigned `onrender.com` hostname |
| `PORT` | optional | supplied by Render | `4000` |

Generate a production cookie secret with `mix phx.gen.secret`. Startup errors name a
missing variable but never include its value.

## Authentication behavior

`GET /api/session` initializes the encrypted, signed, HTTP-only, SameSite=Lax cookie and
returns a CSRF token. Login renews both and stores a random session identifier in the
cookie. The server stores only its hash, a credential fingerprint, and an absolute
eight-hour expiry. Every protected request checks this record. Logout revokes it before
dropping the cookie, so a copied cookie cannot be replayed afterward. Credential changes
also invalidate existing sessions. The SPA keeps its CSRF token only in React state.
All session/API responses use `Cache-Control: no-store`.

Production cookies are Secure. Production responses include a restrictive CSP (scripts,
styles, and connections from the same origin, no inline scripts or framing) and one-year
HSTS. Render terminates HTTPS and redirects HTTP at its edge. Local development omits
CSP/HSTS for Vite and HTTP. Keep `SECRET_KEY_BASE` unique to production; the committed
development/test values must never be reused. Rotate it if it is exposed.

Session records live in memory on one application instance; restart, deployment, or a
security-state process restart signs everyone out. Legacy boolean-only cookies are
rejected. Records expire after eight hours without sliding renewal; at most 10,000 are
stored, with expired entries pruned. New sessions fail closed if capacity is reached.
Use a shared session/revocation store before deploying multiple instances.

Signing out immediately hides chart data, waits for server confirmation, and initializes
a fresh session/CSRF token before enabling login again. If logout fails, the UI warns
that the session may still be active and offers a retry. Failed session initialization
also retries the session endpoint before allowing login or chart requests.

If another tab or cookie expiry invalidates a CSRF token, login obtains a fresh token
and retries once after a `403` rejection. Refresh instead rechecks the session and
reloads the chart or returns to login. Repeated rejection does not loop. Only actual
invalid-credential errors are labeled as an incorrect username/password; network,
timeout, and server failures show a retry message.

Browser API requests have a 30-second deadline covering both response headers and body
reading. Expiry aborts the request and releases the pending UI so the user can retry.
A timeout does not prove the server cancelled the operation, so mutations are not
automatically retried on timeout; logout's existing session check resolves an uncertain
outcome before retrying.

Login allows ten attempts per 60-second window for the entire shared account, including
successful and malformed credential submissions. Excess attempts return `429` with
`Retry-After`; the form asks the reviewer to wait. The budget is atomic and does not
trust caller-supplied forwarding headers, so changing usernames/IP headers cannot bypass
it. This deliberately conservative global limit can temporarily block legitimate login
during an attack; it does not affect already-authenticated sessions. The budget resets
on restart and is not distributed. Add edge abuse protection and a real identity provider
for a larger deployment; do not simply raise the budget to address hostile traffic.

## Cache and refresh policy

- The first chart request fetches every Remote cursor page and atomically stores one
  normalized hierarchy.
- Requests within `REMOTE_CACHE_TTL_SECONDS` use that snapshot.
- A valid Remote employment webhook marks the snapshot for refresh. Webhooks arriving
  close together are coalesced for two seconds, then the next chart request refetches
  the complete snapshot.
- The Refresh button bypasses normal TTL freshness and replaces the snapshot only after
  a complete successful fetch. Manual attempts have a shared 30-second cooldown measured
  from completion. Calls during that window reuse the latest fetch result, including any
  newer webhook-triggered snapshot, instead of starting another upstream request.
- Concurrent calls are serialized by the GenServer; concurrent manual refreshes share
  the completed result on one instance.
- Each full fetch runs in a supervised task with a 20-second deadline. Expiry stops
  the task and returns stale data when available, otherwise a temporary error. Cache
  callers wait at most 25 seconds and receive a temporary error on timeout. Reads
  still queue behind a fetch; these deadlines bound waiting rather than implementing
  background refresh while serving the old snapshot.
- Timeouts, rate limits, and Remote `5xx` errors may return an existing snapshot marked
  stale. After such a failure, reads and manual refreshes wait at least 30 seconds before retrying
  Remote, or longer when its accepted `Retry-After` asks for it (up to 300 seconds).
  The cooldown starts when the attempt finishes and also applies to an empty cache;
  the Refresh button cannot bypass it. Authentication and invalid-schema errors never
  use stale data as the result of a failed fetch.
- Authentication, invalid-response, and internal failures are also held for 30 seconds
  after completion. Reads and manual refreshes return the same safe error during that
  window without contacting Remote or serving the old snapshot as a fallback. The next
  eligible request retries, allowing recovery after a configuration or upstream fix.
- Chart and session API responses are always `Cache-Control: no-store`.

`POST /api/webhooks/remote` is public so Remote can reach it, but it accepts an event
only when `X-Remote-Signature` matches the HMAC-SHA256 of the exact raw request body,
`":"`, and `X-Remote-Timestamp` under `REMOTE_WEBHOOK_SIGNING_KEY`. Invalid or missing
signatures return `401` and do not invalidate the cache. Remote does not provide one
catch-all employment-change event, so configure the callback for `employment.updated`,
`employment.details.updated`, `employment.personal_information.updated`,
`employment.administrative_details.updated`, `employment.status.updated`, and
`employment.work_email.updated`; see Remote's
[webhook setup](https://developer.remote.com/docs/working-with-webhooks) and
[signature verification](https://developer.remote.com/docs/verifying-webhooks).

Webhook invalidation has deliberate limits:

- Delivery is eventually consistent. Events are debounced for two seconds, and the
  refresh happens on the next chart read rather than in the webhook request.
- The callback is a hint, not the source of truth. A missed, delayed, or unsupported
  event can leave the snapshot current only when the five-minute TTL expires or a
  reviewer clicks Refresh. Remote retries connection, DNS, TLS, and timeout failures,
  but treats an HTTP response as delivered even when it is `4xx` or `5xx`.
- A signed event triggers a complete paginated snapshot fetch; it does not patch one
  employee in place.
- Signed timestamps must be Unix milliseconds within five minutes of server time,
  including future clock skew. Remote signs each retry with a fresh timestamp. Maintain
  accurate server clocks; out-of-window deliveries return `401` and rely on TTL recovery.
- Accepted signatures are hashed and remembered for ten minutes. An exact duplicate
  receives `204` without another invalidation. This is delivery replay protection, not
  durable event-ID deduplication: re-signed retries can invalidate again. Memory is
  bounded to 10,000 entries and fails closed with `503` at capacity. Restart clears this
  state, so a captured delivery still within the freshness window could invalidate once
  again after restart. The cache is also empty then. Use shared durable deduplication
  storage before scaling to multiple instances.
- The receiver reads at most 1 MB per delivery. Remote employment webhook payloads are
  expected to be much smaller; an oversized delivery is rejected.
- Cache state and invalidations live only in one BEAM process. They disappear on
  restart and are not shared across instances. Keep the Render service at one instance;
  use a shared cache or invalidation bus plus distributed refresh locking before
  scaling horizontally.

### Why the hierarchy is not fetched level by level

Remote cannot currently return only the direct reports of one manager. The
[`/v1/employments/bulk`](https://developer.remote.com/reference/get_v1_employments_bulk)
endpoint supports company, cursor, and page-size parameters, but no manager-ID filter.
The lighter `/v1/employments` list is smaller, but an aggregate sandbox validation found
that its first 100 records contained no `manager` or `manager_employment_id` fields.
Without every employment's manager ID, the application cannot determine roots, direct
reports, external managers, or cycles reliably.

Fetching the first layer and then requesting every employee individually would therefore
be an N+1 request pattern. Remote's
[workforce synchronization guidance](https://developer.remote.com/docs/sync-workforce-data)
also recommends seeding from a paginated list and explicitly discourages looping over
individual employments. At the observed sandbox size of 191 employments, the current
100-record bulk page size builds the complete graph with two employment requests after
the identity lookup.

If the organization grows enough to justify more infrastructure, the preferred design is
to persist a flat employment projection plus a `manager_id -> child_ids` index. A webhook
batch would fetch and patch only the changed employment IDs when the batch is small, while
large or ambiguous batches, process restarts, and periodic reconciliation would trigger a
complete bulk refresh. The browser could then load child layers from that local index.
This would reduce browser payload and small-update work; it would not remove the initial
full Remote seed needed to establish every relationship.

## Hierarchy assumptions and edge cases

`manager_employment_id` is authoritative. Manager names are display-only. The mapper
keeps all employment statuses and models rather than silently filtering them.

The backend disconnects reporting edges to archived managers and promotes those employees
to roots, preserving each employee's own reports and original manager summary. The API
marks these roots with `manager_archived: true`; the UI places them under “No reporting
line” with a “Manager archived” label. This rule applies whether archived employees are
shown or hidden. The archived checkbox only controls visibility, not these relationships.

The hierarchy always terminates and keeps every valid unique employment visible:

- `missing_id`: omit the unusable record;
- `missing_name`: show `Unknown employee`;
- `duplicate_id`: keep the first record;
- `self_manager`: move the employee to the top level;
- `external_manager`: top-level employee whose named manager is outside the response;
- `unresolved_manager`: top-level employee whose manager ID is absent;
- `cycle_detected`: break one deterministic edge in the cycle.

Roots and direct reports are sorted case-insensitively by name and then employment ID.
A manager may appear on a later API page without affecting relationship resolution.

## Privacy and operational errors

The browser receives only company ID/name and these employment fields: ID, name, title,
department, manager summary, status, employment type/model, and nested reports. Work
emails, manager emails, unknown Remote fields, raw response bodies, and bearer tokens
are discarded or remain server-only.

Logs may contain counts, timings, response classes, cache status, warning counts, and
request IDs. They must not contain tokens, raw Remote bodies, names, or email addresses.
Unexpected API failures return an opaque code plus a request ID for correlation.

## Docker smoke test

Build the same artifact Render will run:

```bash
docker build -t remote-org-chart:local .
```

For an end-to-end API-mode check without live credentials, first start the synthetic
Remote server:

```bash
APP_USERNAME=reviewer \
APP_PASSWORD=fixture-server-only \
REMOTE_DATA_SOURCE=fixture \
MIX_ENV=dev mix run scripts/remote_fixture_server.exs
```

In another terminal, generate a disposable secret and run the image:

```bash
export REMOTE_ORG_CHART_SMOKE_SECRET="$(mix phx.gen.secret)"

docker run --rm \
  -p 4000:4000 \
  -e SECRET_KEY_BASE="$REMOTE_ORG_CHART_SMOKE_SECRET" \
  -e PHX_HOST=localhost \
  -e APP_USERNAME=reviewer \
  -e APP_PASSWORD=local-smoke-password \
  -e REMOTE_DATA_SOURCE=api \
  -e REMOTE_API_TOKEN=non-secret-smoke-token \
  -e REMOTE_WEBHOOK_SIGNING_KEY=non-secret-smoke-signing-key \
  -e REMOTE_API_BASE_URL=http://host.docker.internal:4999 \
  remote-org-chart:local
```

Verify `curl --fail http://127.0.0.1:4000/api/health` and
`curl --fail http://127.0.0.1:4000/`. This local HTTP check covers process startup and
static/API routing; use HTTPS (as Render does) for the Secure login cookie.

## Deploy to Render

The repository includes a Render Blueprint with one Docker web service, manual deploys,
and `/api/health` as its health check. Render treats any `2xx`/`3xx` health response as
healthy. The Blueprint starts on the Free plan and prompts for all secret values marked
`sync: false`.

1. Push the repository to GitHub or GitLab.
2. In Render, choose **New → Blueprint** and connect the repository.
3. Supply `SECRET_KEY_BASE`, `APP_USERNAME`, `APP_PASSWORD`, `REMOTE_API_TOKEN`, and
   `REMOTE_WEBHOOK_SIGNING_KEY` when prompted. The last value is the signing key Remote
   returns when you register the public `/api/webhooks/remote` callback. Render supplies
   the assigned hostname automatically.
4. Subscribe that callback to the six `employment.*` events listed in the cache policy.
5. Create the service and wait for `/api/health` to pass.
6. Open the public HTTPS URL, sign in, load, refresh, and sign out.

The Free web-service plan costs $0 but spins down after 15 minutes without inbound
traffic; the next request can take about a minute. For an interview URL that must stay
warm, choose the `0.5c-512mb` plan (formerly Starter), currently advertised by Render at
$7/month. Render pricing and plan names can change, so verify the amount in the dashboard
before purchase. The Blueprint intentionally does not select a paid plan.

References: [Render Blueprint fields](https://render.com/docs/blueprint-spec),
[health checks](https://render.com/docs/health-checks),
[Free-plan behavior](https://render.com/docs/free), and
[current pricing](https://render.com/pricing).

## Read-only sandbox validation

When live credentials are available, validate the assumed contract without saving a raw
response:

1. call `/v1/identity/current` and confirm only that a company ID/name exist;
2. fetch a one-record employment page and record only the total count;
3. fetch bulk pages and calculate only field-presence booleans, record/null counts, enum
   distributions, department count, and manager-ID coverage;
4. compare those aggregate observations with `fixtures/remote/README.md`;
5. add a redacted failing test before changing the mapper for any contract mismatch.

Never print the Authorization header, names, emails, or raw response bodies during this
validation.

## Deliberate limitations and production hardening

This implementation has no user database, password reset, roles,
persistent/distributed cache, background synchronization, editing, or multi-company
selection. Its webhook invalidation has the delivery and single-instance constraints
listed above. It is designed for one configured company and one application instance.

For a longer-lived product, add edge abuse protection and audit events, a real identity
provider, secret rotation procedures, observability/alerts, shared security/cache state
with distributed refresh locking, contract monitoring, and load/accessibility testing.
Keep checking both npm and Hex advisories: Mint is pinned to 1.10.0, which fixes
CVE-2026-82728 and CVE-2026-82729. Dependency checks do not replace container/OS scanning.

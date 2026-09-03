# Remote Org Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a small Phoenix and React application that authenticates reviewers, fetches and safely normalizes Remote employment data, renders a deterministic organizational forest, caches the result in memory, and deploys as one Docker service on Render.

**Architecture:** Phoenix is an API and production static-file host with no Ecto, while Vite owns the React/TypeScript SPA under assets. RemoteOrgChart.Auth hides an environment-backed credential provider; RemoteOrgChart.Remote hides interchangeable HTTP and fixture providers; RemoteOrgChart.Hierarchy is pure; and RemoteOrgChart.RemoteCache serializes fetches and retains only normalized charts.

**Tech Stack:** Elixir 1.18+, OTP 27+, Phoenix 1.7+, Req 0.5+, React 19, TypeScript 5, Vite, Vitest, React Testing Library, Docker, and Render.

**Spec:** [Approved design specification](../specs/2026-09-03-remote-org-chart-design.md)

## Global Constraints

- Keep the repository API-only: no Ecto, LiveView, Phoenix HTML helpers, mailer, Redis, or database.
- Use test-driven development for every behavior task: write one focused failing test, run it and confirm the expected failure, implement the minimum behavior, then rerun the narrow test.
- Never expose, persist, commit, or log Remote access tokens, raw Remote response bodies, work email addresses, or manager email addresses.
- Never silently switch from live API mode to fixture mode.
- Keep controllers and React components thin; data acquisition, normalization, hierarchy recovery, cache policy, and HTTP error classification remain independently testable.
- All collections and warnings must be deterministic so tests and reviewer output do not depend on map enumeration order.
- Use fixture mode for implementation until a sandbox token is available. Live validation is read-only and redacted.
- Run mix format, mix test, npm test, npm run build, and the production release smoke test before claiming completion.

---

## Task 1: Generate the minimal Phoenix and Vite foundations

**Files:**

- Create: mix.exs, mix.lock, config/config.exs, config/dev.exs, config/test.exs, config/prod.exs, config/runtime.exs
- Create: lib/remote_org_chart.ex, lib/remote_org_chart/application.ex
- Create: lib/remote_org_chart_web.ex, lib/remote_org_chart_web/endpoint.ex, lib/remote_org_chart_web/router.ex
- Create: test/test_helper.exs, test/support/conn_case.ex
- Create: assets/package.json, assets/package-lock.json, assets/vite.config.ts, assets/tsconfig*.json
- Create: assets/src/main.tsx, assets/src/App.tsx, assets/src/test/setup.ts
- Create: .env.example
- Modify: .gitignore
- Retain and commit: fixtures/remote/*

**Interfaces:**

- Phoenix listens on port 4000 in development.
- Vite listens on port 5173 and proxies /api to http://127.0.0.1:4000.
- Vite production output is priv/static and is served by Phoenix.
- mix assets.deploy builds the SPA and digests Phoenix static assets.

- [ ] Verify the prerequisite versions.

Run:

~~~bash
elixir --version
mix phx.new --version
node --version
npm --version
~~~

Expected minimums: Elixir 1.18, OTP 27, Phoenix installer 1.7, Node 22, and npm 10.

- [ ] Generate Phoenix in the existing repository and answer Y when it confirms the non-empty destination.

Run:

~~~bash
mix phx.new . \
  --app remote_org_chart \
  --module RemoteOrgChart \
  --no-ecto \
  --no-html \
  --no-live \
  --no-mailer \
  --no-dashboard \
  --no-gettext \
  --no-assets \
  --no-install
~~~

Confirm that docs/ and fixtures/ remain untouched.

- [ ] Add Req and the asset command aliases to mix.exs.

Use these dependency and alias entries:

~~~elixir
defp deps do
  [
    {:phoenix, "~> 1.7.7"},
    {:phoenix_pubsub, "~> 2.1"},
    {:bandit, "~> 1.5"},
    {:jason, "~> 1.4"},
    {:req, "~> 0.5"}
  ]
end

defp aliases do
  [
    setup: ["deps.get", "cmd --cd assets npm install"],
    "assets.deploy": [
      "cmd --cd assets npm ci",
      "cmd --cd assets npm run build",
      "phx.digest"
    ]
  ]
end
~~~

- [ ] Generate the React/TypeScript application and install the test dependencies.

Run:

~~~bash
npm create vite@latest assets -- --template react-ts
npm install --prefix assets
npm install --prefix assets --save-dev vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event
~~~

Set the package scripts to:

~~~json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "lint": "eslint .",
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
~~~

- [ ] Configure Vite output, proxying, and Vitest.

Replace assets/vite.config.ts with:

~~~ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:4000",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "./src/test/setup.ts",
  },
});
~~~

Create assets/src/test/setup.ts:

~~~ts
import "@testing-library/jest-dom/vitest";
~~~

- [ ] Add one frontend smoke test, run it, then keep it as a harness check.

Create assets/src/App.test.tsx:

~~~tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import App from "./App";

describe("App", () => {
  it("renders the scaffold heading", () => {
    render(<App />);
    expect(screen.getByRole("heading", { name: /remote org chart/i })).toBeInTheDocument();
  });
});
~~~

Make App.tsx render an h1 named Remote org chart, then run:

~~~bash
npm test --prefix assets
~~~

Expected: one passing test.

- [ ] Document only safe configuration names in .env.example.

~~~dotenv
REMOTE_DATA_SOURCE=fixture
REMOTE_API_BASE_URL=https://gateway.remote-sandbox.com
REMOTE_API_TOKEN=
REMOTE_CACHE_TTL_SECONDS=300
APP_USERNAME=reviewer
APP_PASSWORD=change-me-locally
PHX_HOST=localhost
SECRET_KEY_BASE=
~~~

Ignore .env, .env.*, and preserve only !.env.example. Also ignore assets/node_modules, priv/static/assets, and release output.

- [ ] Install backend dependencies and run the generated backend and frontend checks.

Run:

~~~bash
mix deps.get
mix format --check-formatted
mix test
npm test --prefix assets
npm run build --prefix assets
~~~

- [ ] Commit the foundation and already-verified synthetic fixtures.

~~~bash
git add mix.exs mix.lock config lib test assets .gitignore .env.example fixtures
git commit -m "build: scaffold phoenix and react application"
~~~

---

## Task 2: Normalize Remote-shaped data at one privacy boundary

**Files:**

- Create: lib/remote_org_chart/remote/company.ex
- Create: lib/remote_org_chart/remote/person.ex
- Create: lib/remote_org_chart/remote/snapshot.ex
- Create: lib/remote_org_chart/remote/mapper.ex
- Create: test/support/fixture.ex
- Create: test/remote_org_chart/remote/mapper_test.exs
- Modify: config/test.exs

**Interfaces:**

~~~elixir
RemoteOrgChart.Remote.Mapper.map(identity_body, employment_maps)
# => {:ok, %RemoteOrgChart.Remote.Snapshot{}}
# => {:error, %RemoteOrgChart.Remote.Error{kind: :invalid_response}}
~~~

The normalized types are:

~~~elixir
defmodule RemoteOrgChart.Remote.Company do
  @enforce_keys [:id, :name]
  defstruct [:id, :name]
end

defmodule RemoteOrgChart.Remote.Person do
  @enforce_keys [:id, :name]
  defstruct [
    :id,
    :name,
    :title,
    :department,
    :manager,
    :status,
    :employment_type,
    :employment_model
  ]
end

defmodule RemoteOrgChart.Remote.Snapshot do
  @enforce_keys [:company, :people, :warnings]
  defstruct [:company, :people, :warnings]
end
~~~

Department is nil or %{id: string | nil, name: string | nil}. Manager is nil or %{id: string | nil, name: string | nil}.

- [ ] Add a fixture reader that resolves paths from the repository root and decodes JSON with Jason.decode!/1.

Create test/support/fixture.ex with read_json!/1 and employment_pages!/1. The latter must return the data lists from the three complex page files in page order.

- [ ] Write the mapper success test first.

The test must assert the company ID/name and the exact projection of one managed person:

~~~elixir
assert {:ok, snapshot} = Mapper.map(identity, List.flatten(pages))
assert snapshot.company.name == "Acme Sandbox Corp"

assert %Person{
         id: id,
         name: name,
         manager: %{id: manager_id, name: manager_name}
       } = Enum.find(snapshot.people, &(&1.manager != nil))

assert is_binary(id)
assert is_binary(name)
assert is_binary(manager_id)
assert is_binary(manager_name)
refute Map.has_key?(Map.from_struct(Enum.at(snapshot.people, 0)), :email)
~~~

Run:

~~~bash
mix test test/remote_org_chart/remote/mapper_test.exs
~~~

Expected failure: Mapper is undefined.

- [ ] Implement strict company extraction and permissive employment projection.

Mapper.map/2 must:

1. require data.company.id and data.company.name as nonblank strings;
2. require the employments argument to be a list;
3. trim optional strings;
4. skip a record with a missing/blank id and append %{code: "missing_id", index: index};
5. replace a missing/blank full_name with "Unknown employee" and append %{code: "missing_name", employment_id: id};
6. retain only approved person fields;
7. ignore unknown upstream fields.

Use this normalization rule:

~~~elixir
defp optional_string(value) when is_binary(value) do
  case String.trim(value) do
    "" -> nil
    trimmed -> trimmed
  end
end

defp optional_string(_value), do: nil
~~~

Do not use Map.take/2 on a complete Remote record because it leaves the upstream shape coupled to the application. Construct the Person struct field by field.

- [ ] Add missing-id, blank-name, unknown-field, and invalid-company tests.

The pathological fixture test must confirm:

~~~elixir
assert Enum.any?(snapshot.warnings, &(&1.code == "missing_id"))
assert Enum.any?(snapshot.warnings, &(&1.code == "missing_name"))
assert Enum.any?(snapshot.people, &(&1.name == "Unknown employee"))
refute Enum.any?(snapshot.warnings, &Map.has_key?(&1, :email))
~~~

Invalid identity bodies and a non-list employment body must return a typed invalid_response error, never raise a MatchError.

- [ ] Run the mapper suite and format.

~~~bash
mix test test/remote_org_chart/remote/mapper_test.exs
mix format
~~~

- [ ] Commit.

~~~bash
git add lib/remote_org_chart/remote test/support test/remote_org_chart/remote config/test.exs
git commit -m "feat: normalize remote employment data"
~~~

---

## Task 3: Build a deterministic, cycle-safe organization forest

**Files:**

- Create: lib/remote_org_chart/hierarchy/chart.ex
- Create: lib/remote_org_chart/hierarchy/node.ex
- Create: lib/remote_org_chart/hierarchy.ex
- Create: test/remote_org_chart/hierarchy_test.exs

**Interfaces:**

~~~elixir
RemoteOrgChart.Hierarchy.build(%RemoteOrgChart.Remote.Snapshot{})
# => %RemoteOrgChart.Hierarchy.Chart{
#      company: %Company{},
#      roots: [%Node{}],
#      warnings: [map()],
#      employee_count: non_neg_integer(),
#      root_count: non_neg_integer()
#    }
~~~

Node repeats the display fields from Person and adds reports: [].

- [ ] Write a complex-fixture test that proves all pages are normalized before relationship resolution.

Build the snapshot from all three page data lists, call Hierarchy.build/1, flatten every node recursively, and assert:

~~~elixir
assert chart.employee_count == 30
assert length(all_nodes) == 30
assert MapSet.size(MapSet.new(all_nodes, & &1.id)) == 30
assert chart.root_count == 4
assert maximum_depth(chart.roots) == 5
~~~

Also identify the fixture person whose manager is on a later page and assert that person is nested below that manager rather than becoming a root.

Run the test and confirm it fails because Hierarchy is undefined.

- [ ] Implement first-record-wins deduplication.

Reduce people in input order into {by_id, ordered_ids, warnings}. If an ID is already present, preserve the existing person and append:

~~~elixir
%{
  code: "duplicate_id",
  employment_id: person.id
}
~~~

Do not rely on Map.values/1 for output order; retain ordered_ids separately.

- [ ] Implement manager-edge classification in sorted employment-ID order.

For every unique person:

- manager.id equals person.id: create no edge and warn self_manager;
- manager.id is present in the person index: create child_id => manager_id;
- manager.id is nonblank but absent from the index: create no edge and warn unresolved_manager;
- manager.id is nil while manager.name is present: create no edge and warn external_manager;
- manager is nil or both manager values are nil: create no edge and no warning.

Warning maps must contain structural IDs and may include the non-email manager display name only for external_manager.

- [ ] Implement functional-graph cycle detection before recursive node construction.

Traverse each child-to-manager pointer with a local path and position map. On revisiting an ID in the same path, take the cycle suffix. Canonicalize each detected cycle as its sorted list of IDs and deduplicate cycles with MapSet.

For every unique cycle, in sorted cycle order:

1. select Enum.min(cycle_ids);
2. delete that employment ID's manager edge;
3. append %{code: "cycle_detected", employment_ids: Enum.sort(cycle_ids), broken_at: smallest_id}.

After this step the graph is acyclic, so recursive rendering cannot loop.

- [ ] Build nodes bottom-up and sort all sibling lists.

Group child IDs by manager ID. Root IDs are IDs with no child-to-manager edge. Recursively produce Node structs and sort every sibling list by:

~~~elixir
{String.downcase(node.name), node.id}
~~~

Return root_count from the final roots and employee_count from the unique-person index.

- [ ] Add pathological-graph tests.

Using employments_bulk_pathological.json, assert:

- missing IDs were skipped by the mapper;
- the first duplicate wins;
- a self-manager becomes a root;
- one three-person cycle becomes acyclic by breaking its lexicographically smallest ID;
- warnings include missing_id, missing_name, duplicate_id, self_manager, and cycle_detected;
- flattening terminates and contains each retained ID exactly once;
- two calls with identical input return exactly equal charts.

- [ ] Add isolated manager-recovery tests.

Use the complex fixture to assert its named manager without an employment ID emits external_manager. Add a two-person synthetic Snapshot whose report points to a nonexistent manager employment ID and assert it becomes a root with unresolved_manager. Verify neither warning contains an email field.

- [ ] Run the hierarchy and mapper suites and format.

~~~bash
mix test test/remote_org_chart/hierarchy_test.exs test/remote_org_chart/remote/mapper_test.exs
mix format
~~~

- [ ] Commit.

~~~bash
git add lib/remote_org_chart/hierarchy.ex lib/remote_org_chart/hierarchy test/remote_org_chart/hierarchy_test.exs
git commit -m "feat: construct resilient organization hierarchy"
~~~

---

## Task 4: Add fixture and HTTP Remote providers with safe error classification

**Files:**

- Create: lib/remote_org_chart/remote/error.ex
- Create: lib/remote_org_chart/remote/source.ex
- Create: lib/remote_org_chart/remote/client.ex
- Create: lib/remote_org_chart/remote/fixture_client.ex
- Create: lib/remote_org_chart/remote.ex
- Create: test/remote_org_chart/remote/client_test.exs
- Create: test/remote_org_chart/remote/fixture_client_test.exs
- Create: test/remote_org_chart/remote_test.exs
- Modify: config/config.exs, config/dev.exs, config/test.exs, config/runtime.exs

**Interfaces:**

~~~elixir
@callback fetch(keyword()) ::
  {:ok, %{identity: map(), employments: [map()], page_count: pos_integer()}}
  | {:error, RemoteOrgChart.Remote.Error.t()}

RemoteOrgChart.Remote.fetch_chart(keyword())
# => {:ok, %RemoteOrgChart.Hierarchy.Chart{}}
# => {:error, %RemoteOrgChart.Remote.Error{}}
~~~

fetch_chart/1 has a default empty keyword list so the supervised cache can call fetch_chart/0.

Error kinds are :authentication, :temporary, :invalid_response, and :internal. Error may carry retry_after as a bounded integer.

- [ ] Write the fixture-provider test first.

Configure its fixture directory explicitly and assert fetch/1 returns identity, 30 raw employment maps, and page_count 3. Then pass that provider through Remote.fetch_chart/1 and assert employee_count 30.

Confirm the first run fails because FixtureClient is undefined.

- [ ] Implement FixtureClient without a network fallback.

FixtureClient.fetch/1 reads identity_current.json and the three named complex page files from the configured directory. It validates that each body has a list under data and that cursor sequence is:

~~~elixir
["fixture-cursor-page-2", "fixture-cursor-page-3", nil]
~~~

A missing file, decode error, malformed data list, or unexpected cursor returns invalid_response. It does not try Client.

- [ ] Write Req-backed pagination tests before Client.

Create an injected Req request with a Req.Test plug. The test adapter must:

- return identity_current.json for /v1/identity/current;
- return page 1 without a cursor;
- return page 2 for fixture-cursor-page-2;
- return page 3 for fixture-cursor-page-3;
- record each query so the test asserts company_id and limit=100 on every bulk call.

Assert Client.fetch(req: request) returns 30 maps and page_count 3.

- [ ] Implement Client request construction and pagination.

Default request configuration:

~~~elixir
Req.new(
  base_url: base_url,
  auth: {:bearer, token},
  receive_timeout: 5_000,
  connect_options: [timeout: 3_000],
  retry: false
)
~~~

Client.fetch/1 must call identity first, extract a nonblank company ID, and fetch bulk pages with company_id, limit 100, and the opaque cursor. Track already-requested nonnil cursors in MapSet. If next_cursor points to an already-requested cursor, return invalid_response before sending another request.

Treat only 2xx responses with the expected map/list shape as success. Do not log response bodies.

- [ ] Add one focused test per error class.

Cover:

- 401 and 403 => authentication;
- 429 => temporary plus a Retry-After integer only when the header is a decimal value from 0 through 300;
- 500 through 599 => temporary;
- transport timeout => temporary;
- invalid JSON/body/schema and repeated cursor => invalid_response;
- any failed later page discards accumulated records and returns the error.

- [ ] Implement the public Remote orchestration boundary.

Remote.fetch_chart/1 chooses only the configured source module, calls source.fetch/1, calls Mapper.map/2, then Hierarchy.build/1:

~~~elixir
with {:ok, raw} <- source.fetch(source_options),
     {:ok, snapshot} <- Mapper.map(raw.identity, raw.employments) do
  {:ok, Hierarchy.build(snapshot)}
end
~~~

Emit metadata-only telemetry or Logger fields for page_count, employee_count, duration, response class, and warning count. Never interpolate raw records, names, email addresses, credentials, or tokens.

- [ ] Configure the source explicitly.

In dev, default to fixture only because config/dev.exs explicitly says fixture; setting REMOTE_DATA_SOURCE=api selects Client. In test, use injected modules. In runtime.exs:

- accept only api or fixture;
- require api in production;
- require REMOTE_API_TOKEN when api is selected;
- default REMOTE_API_BASE_URL to https://gateway.remote-sandbox.com;
- raise at startup for unknown values rather than falling back.

- [ ] Run all Remote tests and format.

~~~bash
mix test test/remote_org_chart/remote_test.exs test/remote_org_chart/remote
mix format
~~~

- [ ] Commit.

~~~bash
git add lib/remote_org_chart/remote.ex lib/remote_org_chart/remote config test/remote_org_chart/remote_test.exs test/remote_org_chart/remote
git commit -m "feat: fetch remote organization snapshots"
~~~

---

## Task 5: Cache one normalized chart with TTL and controlled stale fallback

**Files:**

- Create: lib/remote_org_chart/remote_cache.ex
- Create: lib/remote_org_chart/remote_cache/result.ex
- Create: test/remote_org_chart/remote_cache_test.exs
- Modify: lib/remote_org_chart/application.ex
- Modify: config/config.exs, config/runtime.exs

**Interfaces:**

~~~elixir
RemoteOrgChart.RemoteCache.get(server \\ RemoteOrgChart.RemoteCache)
RemoteOrgChart.RemoteCache.refresh(server \\ RemoteOrgChart.RemoteCache)

# success:
{:ok,
 %RemoteOrgChart.RemoteCache.Result{
   chart: %RemoteOrgChart.Hierarchy.Chart{},
   fetched_at: %DateTime{},
   stale: boolean()
 }}

# failure:
{:error, %RemoteOrgChart.Remote.Error{}}
~~~

start_link/1 accepts name, fetcher, now, and ttl_ms so tests need no sleeps. now is a zero-arity function returning %{monotonic_ms: integer(), utc: DateTime.t()}.

- [ ] Write a cache-hit test using an Agent-backed fetch counter and injected clock.

Start a uniquely named cache under the test supervisor. Call get twice without advancing time and assert:

~~~elixir
assert counter_value == 1
assert first.chart == second.chart
refute first.stale
refute second.stale
~~~

Confirm failure because RemoteCache is undefined.

- [ ] Implement fresh-hit and atomic-replacement behavior in one GenServer.

State contains only:

~~~elixir
%{
  value: nil | %Result{},
  fetched_at_ms: nil | integer(),
  ttl_ms: non_neg_integer(),
  fetcher: (-> {:ok, Chart.t()} | {:error, Error.t()}),
  now: (-> %{monotonic_ms: integer(), utc: DateTime.t()})
}
~~~

Handle each get or refresh within the GenServer call. A successful complete chart replaces value and both timestamps together. Never store raw Remote maps.

- [ ] Add expiry and forced-refresh tests.

Advance the injected monotonic clock beyond ttl_ms and assert get fetches again. Without advancing it, assert refresh fetches again. A failed refresh must leave the prior successful value and timestamp unchanged.

- [ ] Add concurrent single-flight coverage.

Make the injected fetcher block on a test message. Start five Task.async calls to get. Release the fetcher once and assert all five receive the same result and the counter is one. GenServer call serialization supplies the single-flight behavior; do not add a second worker/cache process.

- [ ] Add stale-policy tests.

After priming the cache and expiring it:

- temporary timeout, 429, or 5xx-shaped Error returns the stored Result with stale true;
- authentication, invalid_response, and internal errors return the error and never expose the stale value;
- any error with an empty cache returns the error;
- fresh hits always return stale false.

- [ ] Supervise the production cache.

Add:

~~~elixir
{RemoteOrgChart.RemoteCache,
 fetcher: &RemoteOrgChart.Remote.fetch_chart/0,
 ttl_ms: Application.fetch_env!(:remote_org_chart, :remote_cache_ttl_ms)}
~~~

to Application children before Endpoint. Parse REMOTE_CACHE_TTL_SECONDS as a nonnegative integer in runtime.exs, default 300, and convert once to milliseconds.

- [ ] Run tests and commit.

~~~bash
mix test test/remote_org_chart/remote_cache_test.exs
mix test
mix format
git add lib/remote_org_chart/remote_cache.ex lib/remote_org_chart/remote_cache lib/remote_org_chart/application.ex config test/remote_org_chart/remote_cache_test.exs
git commit -m "feat: cache normalized organization charts"
~~~

---

## Task 6: Implement environment-backed login behind an auth service boundary

**Files:**

- Create: lib/remote_org_chart/auth.ex
- Create: lib/remote_org_chart/auth/provider.ex
- Create: lib/remote_org_chart/auth/environment_provider.ex
- Create: lib/remote_org_chart_web/controllers/session_controller.ex
- Create: lib/remote_org_chart_web/plugs/require_auth.ex
- Create: test/remote_org_chart/auth_test.exs
- Create: test/remote_org_chart_web/controllers/session_controller_test.exs
- Modify: lib/remote_org_chart_web/endpoint.ex
- Modify: lib/remote_org_chart_web/router.ex
- Modify: config/config.exs, config/test.exs, config/runtime.exs

**Interfaces:**

~~~elixir
RemoteOrgChart.Auth.authenticate(username, password, provider \\ configured_provider)
# => :ok | {:error, :invalid_credentials}

RemoteOrgChart.Auth.Provider.credentials()
# => {:ok, %{username: binary(), password: binary()}}
~~~

HTTP:

- GET /api/session => 200 %{authenticated: boolean, csrf_token: string}
- POST /api/session => 200 session JSON or 401 %{error: %{code: "invalid_credentials"}}
- DELETE /api/session => 204
- protected unauthenticated request => 401 %{error: %{code: "authentication_required"}}

- [ ] Write Auth unit tests for exact match and all invalid combinations.

Use a test provider returning known values. Assert valid credentials produce :ok and wrong username, wrong password, and both wrong all produce the identical error tuple.

- [ ] Implement fixed-length constant-time comparison.

Calculate both comparisons before combining them:

~~~elixir
submitted_username_digest = :crypto.hash(:sha256, submitted_username)
configured_username_digest = :crypto.hash(:sha256, configured_username)
submitted_password_digest = :crypto.hash(:sha256, submitted_password)
configured_password_digest = :crypto.hash(:sha256, configured_password)

username_matches =
  Plug.Crypto.secure_compare(submitted_username_digest, configured_username_digest)

password_matches =
  Plug.Crypto.secure_compare(submitted_password_digest, configured_password_digest)
~~~

Return :ok only when both booleans are true. Coerce non-binary request values to an always-invalid fixed string before hashing; do not raise and do not reveal which field failed.

- [ ] Implement EnvironmentProvider.

Read already-validated runtime application configuration:

~~~elixir
Application.fetch_env!(:remote_org_chart, :app_credentials)
~~~

Runtime production startup must require nonblank APP_USERNAME and APP_PASSWORD. Test configuration points Auth at a deterministic test provider.

- [ ] Configure an encrypted, signed Phoenix cookie session.

Endpoint session options must include store :cookie, a project-specific key, signing_salt, encryption_salt, same_site "Lax", http_only true, and secure true only in production. The key material is derived by Plug from SECRET_KEY_BASE; credentials are not placed in the cookie.

- [ ] Write controller tests for bootstrap, login, renewal, logout, and generic failure.

The flow test must:

1. GET /api/session and capture csrf_token and response cookies;
2. POST valid JSON credentials with x-csrf-token;
3. assert authenticated true and that the session cookie is renewed;
4. GET /api/session using the new cookie and assert authenticated true;
5. DELETE /api/session with the current CSRF token;
6. GET /api/session and assert authenticated false.

Also test invalid credentials and a missing/invalid CSRF token on both state-changing endpoints.

- [ ] Implement SessionController and RequireAuth.

On successful login:

~~~elixir
conn
|> configure_session(renew: true)
|> put_session(:authenticated, true)
|> json(%{authenticated: true, csrf_token: get_csrf_token()})
~~~

On logout, clear/drop the session and send status 204. RequireAuth checks get_session(conn, :authenticated) == true, otherwise sends JSON 401 and halts.

- [ ] Define router pipelines.

Use:

- api for accepts JSON;
- api_session for fetch_session, protect_from_forgery, and secure headers;
- authenticated after api_session for RequireAuth.

Health uses only api. Session routes use api_session. Org routes added in Task 7 use api_session plus authenticated.

- [ ] Run auth tests and commit.

~~~bash
mix test test/remote_org_chart/auth_test.exs test/remote_org_chart_web/controllers/session_controller_test.exs
mix format
git add lib/remote_org_chart/auth.ex lib/remote_org_chart/auth lib/remote_org_chart_web config test/remote_org_chart/auth_test.exs test/remote_org_chart_web/controllers/session_controller_test.exs
git commit -m "feat: add environment-backed session authentication"
~~~

---

## Task 7: Expose the chart API, safe errors, health check, and SPA fallback

**Files:**

- Create: lib/remote_org_chart_web/controllers/health_controller.ex
- Create: lib/remote_org_chart_web/controllers/org_chart_controller.ex
- Create: lib/remote_org_chart_web/controllers/spa_controller.ex
- Create: lib/remote_org_chart_web/org_chart_serializer.ex
- Create: lib/remote_org_chart_web/remote_error_response.ex
- Create: test/remote_org_chart_web/controllers/health_controller_test.exs
- Create: test/remote_org_chart_web/controllers/org_chart_controller_test.exs
- Create: test/remote_org_chart_web/controllers/spa_controller_test.exs
- Modify: lib/remote_org_chart_web/router.ex
- Modify: lib/remote_org_chart_web/endpoint.ex

**Interfaces:**

- GET /api/health is public and returns 200 %{status: "ok"}.
- GET /api/org-chart is authenticated and uses RemoteCache.get/0.
- POST /api/org-chart/refresh is authenticated, CSRF-protected, and uses RemoteCache.refresh/0.
- Every chart response sets Cache-Control: no-store.
- Non-API GET paths serve priv/static/index.html after static files are checked.

- [ ] Write serializer tests through the controller success path.

Inject a cache module in application config and return a Result with a small nested Chart. Assert exact JSON keys:

~~~elixir
assert %{
  "company" => %{"id" => _, "name" => _},
  "roots" => [%{"id" => _, "reports" => [_]}],
  "warnings" => _,
  "meta" => %{
    "employee_count" => 2,
    "root_count" => 1,
    "fetched_at" => "2026-09-03T12:00:00Z",
    "stale" => false
  }
} = json_response(conn, 200)

assert get_resp_header(conn, "cache-control") == ["no-store"]
~~~

Confirm it fails because the route/controller does not exist.

- [ ] Implement recursive OrgChartSerializer.to_map/1.

Serialize only the approved fields:

- company: id and name;
- node: id, name, title, department, manager, status, employment_type, employment_model, reports;
- warnings from the normalized chart;
- meta: employee_count, root_count, ISO-8601 fetched_at, stale.

Do not serialize any unknown struct field automatically.

- [ ] Implement OrgChartController as an adapter.

index/2 calls the configured cache module's get/0. refresh/2 calls refresh/0. On success, set no-store and json the serializer output. On error, delegate only the typed Remote Error to RemoteErrorResponse.

- [ ] Test and implement error mapping.

Exact mappings:

- authentication => 502 remote_authentication_failed;
- temporary => 503 remote_temporarily_unavailable and safe retry-after header when present;
- invalid_response => 502 invalid_remote_response;
- internal or unknown => 500 internal_error with the Plug request ID in the JSON error object.

Never include an upstream body, exception message, token, request URL query, name, or email in the error response.

- [ ] Test route protection and refresh CSRF.

Assert unauthenticated GET and POST return authentication_required. After login, GET succeeds. Authenticated POST without x-csrf-token is rejected; the same POST with the bootstrap token calls refresh exactly once.

- [ ] Add and test the health endpoint.

It must be usable without a session cookie and return only:

~~~json
{"status":"ok"}
~~~

- [ ] Serve production static files and SPA fallback.

Endpoint Plug.Static should serve only the generated static allowlist. Place the root wildcard GET after all /api scopes. SpaController sends priv/static/index.html. Its test writes a temporary index only through the normal test static setup or uses the built fixture index; it must prove /api/unknown is not converted to HTML.

- [ ] Run web tests and the full backend suite.

~~~bash
mix test test/remote_org_chart_web
mix test
mix format
~~~

- [ ] Commit.

~~~bash
git add lib/remote_org_chart_web test/remote_org_chart_web
git commit -m "feat: expose protected organization chart api"
~~~

---

## Task 8: Build the typed browser session client and custom login screen

**Files:**

- Create: assets/src/api/types.ts
- Create: assets/src/api/client.ts
- Create: assets/src/api/client.test.ts
- Create: assets/src/components/LoginForm.tsx
- Create: assets/src/components/LoginForm.test.tsx
- Modify: assets/src/App.tsx
- Modify: assets/src/App.test.tsx
- Modify: assets/src/index.css

**Interfaces:**

~~~ts
export interface Session {
  authenticated: boolean;
  csrf_token: string;
}

export interface ApiError {
  code: string;
  message?: string;
  request_id?: string;
}

export interface ApiClient {
  session(): Promise<Session>;
  login(username: string, password: string, csrfToken: string): Promise<Session>;
  logout(csrfToken: string): Promise<void>;
  orgChart(): Promise<OrgChartResponse>;
  refresh(csrfToken: string): Promise<OrgChartResponse>;
}
~~~

- [ ] Write client tests first using a vi.fn fetch implementation.

Assert:

- all requests use credentials: "same-origin";
- login and refresh send content-type application/json and x-csrf-token;
- logout sends x-csrf-token;
- non-2xx JSON responses throw a typed ApiRequestError carrying status and code;
- a non-JSON server failure becomes internal_error without exposing response text.

- [ ] Implement createApiClient(fetchImpl = window.fetch).

Use same-origin relative /api URLs. Parse successful JSON only where a body is expected. Keep the Remote token and raw Remote types completely absent from assets.

- [ ] Write LoginForm behavior tests.

Cover labeled username/password inputs, disabled submit while pending, generic invalid-credentials text, and submitting trimmed username with the password unchanged. Do not log or persist either value.

- [ ] Implement the login form.

Use a real form, autocomplete username/current-password, an aria-live error region, and one primary submit button. Clear the password field after a rejected login.

- [ ] Write App session-bootstrap tests before changing App.

Test:

- initial loading state while session() is pending;
- unauthenticated bootstrap renders LoginForm;
- successful login transitions to the authenticated shell;
- authentication_required from a later API request returns to LoginForm;
- logout returns to LoginForm even if the subsequent bootstrap is delayed.

- [ ] Implement the App state machine.

Keep explicit states booting, unauthenticated, authenticated-loading, authenticated-ready, and authenticated-error. App owns the current CSRF token and replaces it whenever a session response supplies a new one. Do not use localStorage.

- [ ] Add modest base styles.

Use a centered login card, readable system font stack, visible focus state, and responsive container. Avoid a design framework or chart library.

- [ ] Run frontend tests and commit.

~~~bash
npm test --prefix assets
npm run build --prefix assets
git add assets
git commit -m "feat: add custom reviewer login"
~~~

---

## Task 9: Render the organization tree and all reviewer-facing states

**Files:**

- Create: assets/src/components/OrgChart.tsx
- Create: assets/src/components/OrgChart.test.tsx
- Create: assets/src/components/PersonNode.tsx
- Create: assets/src/components/WarningList.tsx
- Modify: assets/src/api/types.ts
- Modify: assets/src/App.tsx
- Modify: assets/src/App.test.tsx
- Modify: assets/src/index.css

**Interfaces:**

TypeScript mirrors only the JSON API:

~~~ts
export interface PersonNode {
  id: string;
  name: string;
  title: string | null;
  department: { id: string | null; name: string | null } | null;
  manager: { id: string | null; name: string | null } | null;
  status: string | null;
  employment_type: string | null;
  employment_model: string | null;
  reports: PersonNode[];
}

export interface OrgChartResponse {
  company: { id: string; name: string };
  roots: PersonNode[];
  warnings: Array<Record<string, unknown> & { code: string }>;
  meta: {
    employee_count: number;
    root_count: number;
    fetched_at: string;
    stale: boolean;
  };
}
~~~

- [ ] Write PersonNode and OrgChart rendering tests first.

Assert a three-level tree renders all names once, optional title/department are omitted cleanly when null, status/type remain visible, and the markup uses nested lists with accessible labels.

- [ ] Implement recursive PersonNode.

Each card shows:

- name, always;
- title or "Title unavailable";
- department or "Department unavailable";
- manager line when manager.name exists;
- status, employment type, and employment model badges when present;
- a direct-report count;
- nested reports in a ul only when nonempty.

React keys use employment ID, never array position or name.

- [ ] Implement OrgChart header and empty state.

Show company name, employee/root counts, fetched time formatted with Intl.DateTimeFormat, refresh, and logout. If roots is empty, render an explicit "No employees were returned" message rather than an empty region.

- [ ] Add warning and stale-state tests.

WarningList maps stable codes to readable structural messages without assuming optional keys. If meta.stale is true, show a prominent but nonblocking message that cached data is being displayed because Remote is temporarily unavailable.

- [ ] Add refresh and error-state tests in App.

Cover:

- refresh disables only the refresh button while keeping the current chart visible;
- successful refresh replaces data and CSRF remains valid;
- temporary failure with no stale data shows retry;
- invalid_remote_response and remote_authentication_failed show safe tailored messages;
- authentication_required clears chart state and returns to login;
- unexpected failures show request_id when supplied.

- [ ] Implement the state transitions and readable responsive styling.

Use CSS indentation/connectors for the semantic outline. On narrow screens remove decorative connectors before reducing readable content. No drag/zoom/canvas dependency is needed.

- [ ] Run frontend tests and build.

~~~bash
npm test --prefix assets
npm run build --prefix assets
~~~

- [ ] Commit.

~~~bash
git add assets
git commit -m "feat: render remote organization hierarchy"
~~~

---

## Task 10: Package one production release and document Render deployment

**Files:**

- Create: Dockerfile
- Create: .dockerignore
- Create: render.yaml
- Create: README.md
- Create: scripts/remote_fixture_server.exs
- Modify: config/prod.exs
- Modify: config/runtime.exs
- Modify: mix.exs

**Interfaces:**

- One Docker image contains the compiled Vite assets and a Phoenix OTP release.
- The image starts bin/remote_org_chart start and binds to Render's PORT.
- /api/health is the Render health check.
- No build stage or final layer contains a real .env file or token.

- [ ] Add a production configuration test before the Dockerfile.

Extract small pure parsers where needed and test that production configuration rejects blank SECRET_KEY_BASE, PHX_HOST, APP_USERNAME, APP_PASSWORD, REMOTE_API_TOKEN, and non-api REMOTE_DATA_SOURCE. Test TTL parsing for valid nonnegative integer and invalid values.

- [ ] Implement runtime configuration validation.

Use System.fetch_env!/1 for required production values. Set server: true, URL host from PHX_HOST, HTTP port from PORT default 4000, and IPv6-compatible transport options. Never print secret values in startup errors; name only the missing variable.

- [ ] Create the multi-stage Dockerfile.

Stages:

1. node:22-bookworm-slim installs from assets/package-lock.json and runs npm run build;
2. an official hexpm Elixir 1.18 / OTP 27 Debian image installs Hex/Rebar, fetches only prod deps, copies compiled priv/static from Node, runs mix phx.digest, compiles, and runs mix release;
3. debian:bookworm-slim installs ca-certificates, libstdc++6, openssl, and libncurses6, copies the release as a non-root user, exposes 4000, and starts bin/remote_org_chart start.

Build context excludes .git, .env files except .env.example, node_modules, _build, deps, and test artifacts.

- [ ] Build and smoke-test the production image locally.

Create scripts/remote_fixture_server.exs as a local-only Bandit/Plug server that returns the committed identity fixture and the correct bulk page for each requested cursor. It must bind to port 4999, validate the expected company_id, and never print response bodies. Start it in one terminal:

~~~bash
MIX_ENV=dev mix run scripts/remote_fixture_server.exs
~~~

Then build and run the production image in another terminal:

~~~bash
docker build -t remote-org-chart:local .
docker run --rm \
  -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=localhost \
  -e APP_USERNAME=reviewer \
  -e APP_PASSWORD=local-smoke-password \
  -e REMOTE_DATA_SOURCE=api \
  -e REMOTE_API_TOKEN=non-secret-smoke-token \
  -e REMOTE_API_BASE_URL=http://host.docker.internal:4999 \
  remote-org-chart:local
~~~

The non-secret token is accepted only by the local stub; runtime remains explicitly in api mode, matching Render. In a third shell:

~~~bash
curl --fail http://127.0.0.1:4000/api/health
curl --fail http://127.0.0.1:4000/
~~~

Expected: health JSON and SPA HTML. Stop the disposable container normally.

- [ ] Create render.yaml.

Define one Docker web service, healthCheckPath /api/health, autoDeploy false or the repository's chosen safe setting, and sync:false secret entries for:

- SECRET_KEY_BASE
- PHX_HOST
- APP_USERNAME
- APP_PASSWORD
- REMOTE_API_TOKEN

Set REMOTE_DATA_SOURCE=api and REMOTE_CACHE_TTL_SECONDS=300 as nonsensitive values. Do not force a paid plan in the blueprint; document the smallest always-on selection and its currently displayed price as a dashboard choice that must be verified before purchase.

- [ ] Write README.md.

Include:

1. outcome and architecture;
2. prerequisites;
3. fixture-mode setup and two development terminals;
4. live API-mode setup;
5. every backend/frontend test and build command;
6. environment variable table with required scope and defaults;
7. Docker build/run;
8. Render Blueprint/dashboard deployment;
9. application login behavior and credential rotation;
10. cache TTL, refresh, stale rules, and single-instance limitation;
11. hierarchy assumptions and all warning classes;
12. privacy/logging guarantees;
13. limitations: no rate limiter, no persistent/distributed cache, no user database;
14. production hardening ideas;
15. read-only live validation procedure.

- [ ] Run the complete local quality gate.

~~~bash
mix format --check-formatted
mix test
npm test --prefix assets
npm run build --prefix assets
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
docker build -t remote-org-chart:local .
git status --short
~~~

All commands must pass. Only expected source files may remain modified.

- [ ] Commit deployment support and documentation.

~~~bash
git add Dockerfile .dockerignore render.yaml README.md config mix.exs
git commit -m "docs: add production and render deployment"
~~~

---

## Task 11: Validate the documented contract against the sandbox when credentials arrive

**Files:**

- Modify only if observations require it: fixtures/remote/README.md
- Modify only if observations require it: lib/remote_org_chart/remote/mapper.ex
- Modify only if observations require it: test/remote_org_chart/remote/mapper_test.exs
- Do not create: raw live-response files

**Interfaces:**

- Validation is read-only.
- Diagnostics include counts, null rates, enum distributions, and field-presence booleans only.
- Diagnostics never print names, emails, tokens, or raw bodies.

- [ ] Confirm token identity using GET /v1/identity/current without shell tracing or printing the Authorization header.

- [ ] Query GET /v1/employments?page_size=1 and record only total_count.

- [ ] Query one /v1/employments/bulk page and calculate only:

- top-level key presence;
- record count;
- null counts for approved fields;
- distinct status/type/employment_model counts;
- department count;
- manager_employment_id coverage.

- [ ] Compare the observed contract with the committed fixture README and approved design.

If no mismatch affects behavior, make no code change. If a mismatch exists, first add a redacted failing mapper/client test, then make the smallest projection change.

- [ ] Run the Remote and full suites.

~~~bash
mix test test/remote_org_chart/remote test/remote_org_chart/remote_test.exs
mix test
npm test --prefix assets
~~~

- [ ] Commit only contract-driven changes.

~~~bash
git add fixtures/remote/README.md lib/remote_org_chart/remote/mapper.ex test/remote_org_chart/remote/mapper_test.exs
git commit -m "test: align fixtures with sandbox contract"
~~~

Skip this commit if validation required no source change.

---

## Final acceptance checklist

- [ ] A new browser session can bootstrap CSRF, sign in with environment-backed app credentials, load the chart, refresh, and sign out.
- [ ] The browser never receives Remote credentials or raw Remote employment payloads.
- [ ] Complex fixtures produce 30 unique nodes, 4 recovered roots, and maximum depth 5.
- [ ] Pathological fixtures cannot loop and report deterministic structural warnings.
- [ ] Remote pagination stops at nil and rejects repeated cursors.
- [ ] The cache has fresh-hit, expiry, refresh, single-flight, and selective stale tests.
- [ ] Authentication, CSRF, protected route, typed upstream error, and no-store behaviors are covered.
- [ ] Login, loading, tree, empty, warning, stale, retry, refresh, session-expiry, and logout UI states are covered.
- [ ] The production release serves both /api/health and the SPA from one origin.
- [ ] README instructions are reproducible from a clean clone.
- [ ] A repository scan finds no unfinished markers, live sandbox token, Remote response dump, or email address outside reserved .example.test fixtures.
- [ ] git status is clean after the final commit.

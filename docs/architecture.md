# Architecture and design decisions

This document explains the current design. The [README](../README.md) contains setup,
configuration, operating limits, and deployment instructions.

## One application, one origin

Phoenix serves the JSON API and the compiled React application from one origin. This
keeps cookie authentication and CSRF protection straightforward and avoids a separate
CORS policy. During development, Vite proxies `/api` to Phoenix.

The Docker build separates frontend compilation, the Elixir release build, and the
non-root runtime image. The application serves one configured company on one instance.
It has no database because it displays Remote data rather than maintaining an
independent employee directory.

## Boundaries and data flow

1. `Remote.Client` fetches company identity and all bulk-employment cursor pages.
   Repeated cursors or a failed page reject the new snapshot rather than publish a
   partial organization. `Remote.FixtureClient` supplies synthetic data through the
   same provider interface for local development and tests.
2. `Remote.Mapper` projects upstream records into a small internal model. The chart
   does not retain work emails, manager emails, or unrelated employment fields.
3. `Hierarchy` builds a deterministic forest using manager employment IDs. Reading
   all pages first allows managers to appear after their reports in the API response.
4. `RemoteCache` stores the normalized chart. Controllers translate results into
   safe HTTP responses; `OrgChartSerializer` explicitly selects browser-visible fields.

Fixture mode is explicit and never acts as a fallback for a failed live API request.
This keeps integration failures visible rather than presenting synthetic data as real.

## Reporting relationships

Relationship repair keeps usable employee records visible when manager data is
incomplete or inconsistent. Duplicate IDs keep the first record; self-references and
unresolved relationships become roots with warnings. Cycles are broken at a
deterministically chosen ID. Names are display data, not relationship identifiers.
Cycle detection remembers completed paths so shared ancestor chains are traversed once;
sorted cycle IDs keep repair choices and warning order stable across input orderings.

The backend detaches employees from archived managers while preserving their original
manager summary and marking the reason. Their own teams remain intact. This rule is
independent of the frontend's archived-employee visibility toggle.

The UI distinguishes an absent manager from an archived or unnamed assigned manager.
It does not infer that an employee is an executive merely because no manager is set.
Missing titles, departments, and names have explicit fallbacks.

## Snapshots and freshness

A complete snapshot makes cross-page relationship repair and consistent report counts
possible. Expanding a card therefore reveals data already loaded; it does not fetch
another hierarchy level. The README explains the API constraints behind this choice.

TTL expiry, authenticated manual refresh, and verified webhook invalidation can trigger
a replacement snapshot. Fetch deadlines and cooldowns bound work; concurrent manual
refreshes reuse the latest result. Only temporary upstream failures may fall back to
stale data. Configuration, malformed-response, and internal failures remain errors.

Cache and security state are bounded to the current single-instance design and are not
durable. Restarting clears the cache and revokes sessions. Shared storage and distributed
coordination are prerequisites for horizontal scaling, not features supplied by the
current in-memory processes.

## Authentication and failure recovery

Environment-backed credentials keep this small reviewer application independent of a
user database. The encrypted cookie holds a random session identifier; server-side
state enforces expiry, credential binding, and logout revocation. Authentication checks,
CSRF protection, login throttling, and webhook signature/replay checks have separate roles.

The browser distinguishes credential rejection from operational failure. It recovers
from stale CSRF tokens and applies a deadline to headers and body reading. A timed-out
mutation is not automatically retried because the server may already have completed it.
See the README for exact limits, retry behavior, and single-instance tradeoffs.

## Presentation and testing

Native `details` and `summary` elements provide expandable teams with keyboard support.
Decorative initials avoid loading employee photos. System fonts, semantic CSS color
variables, system-driven dark mode, and reduced-motion support keep the presentation
self-contained. Archived cards use opacity, stripes, and status text together.

`OrgChart` calculates descendant totals from the visible tree and passes them to cards;
expanding a team does not require another network request. Human-readable chip labels
are presentation only and preserve the original API values.

Pure mapping and hierarchy tests cover malformed data and graph repair. Injected
clients, clocks, and fetchers make upstream errors and cache recovery reproducible.
Endpoint tests cover authentication and HTTP behavior; frontend tests cover session
recovery, request deadlines, and the rendered hierarchy without calling Remote.

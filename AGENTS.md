# Repository guidance

See [README.md](README.md) for setup and limits and [docs/architecture.md](docs/architecture.md)
for design. Update them when behavior changes.

## Checks

- Backend: `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, `mix test`.
- Frontend: `npm test --prefix assets`, `npm run lint --prefix assets`, `npm run build --prefix assets`.
- Add regression tests for behavioral fixes; inject clocks/fetchers instead of sleeping.
- Verify setup changes in a fresh checkout. Keep Vite bound to `127.0.0.1:5173`;
  implicit `localhost` may bind only IPv6. Preserve synthetic fixtures for local runs/tests.

## Preserve these rules

- Keep credentials and raw Remote records server-side; use `Remote.Mapper` and
  `OrgChartSerializer` to control exposed fields. Never commit/log secrets or personal
  data. Retain the logger metadata allowlist; log exception types, not messages.
- Fetch all pages before building a deterministic hierarchy. Preserve every valid unique
  employee. Detach reports of archived managers in the backend, retaining their teams,
  original manager summary, and `manager_archived`; the checkbox only changes visibility.
- Only a successful fetch clears cache failure state. Webhooks must not restore freshness
  or postpone retries after cooldown. Only temporary failures permit explicitly stale data.
- Browser deadlines cover headers and bodies. Preserve HTTP status when error parsing
  fails; do not automatically retry mutations after ambiguous timeouts.
- Sessions, cache, and replay protection are single-instance/in-memory; restarts clear them.

## Deployment

- Pushes to `main`, including docs, deploy through GitHub after CI passes; PRs only run checks.
  Keep Render native auto-deploy off. The hook lives in `RENDER_DEPLOY_HOOK_URL`, never code.
- CI confirms acceptance, not rollout. Verify the matching commit is live and `/api/health`
  returns OK before claiming deployment success. Check Render before retrying: cancelling
  GitHub does not cancel an accepted deployment. Avoid duplicate manual deploys.

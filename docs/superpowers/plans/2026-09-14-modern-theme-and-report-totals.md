# Modern Theme and Report Totals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved Quiet depth light/dark visual system and show recursive total-report counts when they differ from direct reports.

**Architecture:** Keep the existing React component hierarchy and derive total reports recursively inside `PersonNode.tsx` from each person's nested `reports` array. Express the visual system entirely through semantic CSS custom properties, with dark values supplied by `prefers-color-scheme`.

**Tech Stack:** React 19, TypeScript, Vitest, Testing Library, CSS, Vite

**Spec:** `docs/superpowers/specs/2026-09-14-modern-theme-design.md`

## Global Constraints

- Preserve the existing Phoenix/React architecture and native `<details>/<summary>` interactions.
- Add no dependencies, API fields, backend changes, external fonts, theme switch, or persisted preference.
- Use `N direct · M total reports` only when total reports exceed direct reports.
- Use CSS `@media (prefers-color-scheme: dark)` rather than JavaScript theme state.
- Keep the ochre “No reporting line” treatment and visible focus styles in both themes.

---

### Task 1: Recursive report totals

**Files:**
- Modify: `assets/src/components/OrgChart.test.tsx`
- Modify: `assets/src/components/PersonNode.tsx`

**Interfaces:**
- Consumes: `PersonNode` values whose `reports` property contains nested `PersonNode` values.
- Produces: `countTotalReports(person: Person): number` and consumer-visible report-count copy.

- [ ] **Step 1: Write the failing nested-total test**

Add a test with one leader, two direct managers, and three nested reports. Expand the reporting group and assert that the leader card contains `2 direct · 5 total reports`; assert that a manager with one direct leaf contains `1 direct report`.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `npm test --prefix assets -- --run src/components/OrgChart.test.tsx`

Expected: FAIL because the leader currently renders only `2 direct reports`.

- [ ] **Step 3: Implement the recursive total**

Add this pure helper to `PersonNode.tsx`:

```tsx
function countTotalReports(person: Person): number {
  return person.reports.reduce(
    (total, report) => total + 1 + countTotalReports(report),
    0,
  )
}
```

Calculate `totalReportCount` in `PersonNode`, pass it to `PersonCardContents`, and render:

```tsx
const reportLabel =
  totalReportCount > reportCount
    ? `${reportCount} direct · ${totalReportCount} total reports`
    : `${reportCount} direct ${reportCount === 1 ? 'report' : 'reports'}`
```

- [ ] **Step 4: Run the focused test to verify GREEN**

Run: `npm test --prefix assets -- --run src/components/OrgChart.test.tsx`

Expected: all `OrgChart` tests pass.

### Task 2: Quiet depth token system and component polish

**Files:**
- Modify: `assets/src/index.css`

**Interfaces:**
- Consumes: existing component class names in the React frontend.
- Produces: light semantic tokens, dark token overrides, responsive component styling, focus states, and reduced-motion behavior.

- [ ] **Step 1: Define semantic light and dark tokens**

Expand `:root` with canvas, elevated surface, subtle surface, ink, muted ink, line, structure, focus, unassigned, warning, and danger tokens. Add `color-scheme: light` and an `@media (prefers-color-scheme: dark)` block that changes `color-scheme` to `dark` and overrides all theme-dependent values.

- [ ] **Step 2: Replace literal theme colors with tokens**

Update body, controls, login/error panels, notices, chart groups, cards, badges, empty state, and interactive states to use the semantic variables. No foreground/background pair may rely on a light-only literal color.

- [ ] **Step 3: Apply the Quiet depth geometry**

Use a quiet solid canvas, `10–12px` primary surface radii, restrained surface shadows, a 3px blue hierarchy rail, lighter connectors, compact badges, and deliberate hover/focus feedback. Preserve the current content order and disclosure layout.

- [ ] **Step 4: Verify responsive and reduced-motion rules**

Keep the existing narrow-screen stacking behavior, ensure report-count text wraps without overlapping badges, and disable added transform/shadow transitions inside `prefers-reduced-motion: reduce`.

### Task 3: Full verification and visual QA

**Files:**
- Modify only if verification exposes a defect in files already listed above.

**Interfaces:**
- Consumes: the completed React and CSS changes.
- Produces: a verified production-ready frontend change.

- [ ] **Step 1: Run automated frontend verification**

Run:

```bash
npm test --prefix assets
npm run lint --prefix assets
npm run build --prefix assets
git diff --check
```

Expected: all commands exit successfully with no test, lint, build, or whitespace errors.

- [ ] **Step 2: Inspect desktop light and dark modes**

Open the local application, authenticate, expand the reporting structure, and inspect the header, group summary, manager cards, nested connectors, badges, direct/total count, hover, and focus states under light and dark system emulation.

- [ ] **Step 3: Inspect mobile layout**

At a viewport near `390px`, verify actions, chart metadata, cards, badges, and report-count text wrap cleanly with no horizontal overflow.


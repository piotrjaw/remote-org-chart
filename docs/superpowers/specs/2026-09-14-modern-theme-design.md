# Modern Theme and Report Totals Design

**Date:** 2026-09-14

## Goal

Refresh the existing org chart with the approved “Quiet depth” visual direction, add automatic system-driven dark mode, and distinguish a manager's direct reports from all reports when those values differ.

## Scope

- Preserve the current Phoenix/React architecture and existing org-chart disclosure behavior.
- Restyle the current application, login, chart groups, employee cards, notices, errors, inputs, and buttons through the existing stylesheet.
- Calculate total reports from the already-loaded hierarchy in React; do not change the backend or Remote API requests.
- Add no dependencies, external fonts, theme switch, persisted preference, or new API fields.

## Visual Direction: Quiet Depth

The application should feel calm, current, and operational rather than decorative. Names and roles remain the visual focus. Hierarchy is expressed by a restrained blue rail and connector system; surface elevation is subtle and secondary.

### Color tokens

Light mode:

- Canvas: `#f5f7fb`
- Surface: `#ffffff`
- Primary ink: `#172238`
- Muted ink: `#64748b`
- Structure blue: `#4d78c4`
- Line: `#dbe3ef`

Dark mode:

- Canvas: `#0c1322`
- Surface: `#131d2d`
- Primary ink: `#edf3ff`
- Muted ink: `#a8b5c8`
- Structure blue: `#8bb2f1`
- Line: `#2a3952`

The existing ochre “No reporting line” semantics remain distinct in both themes. Warning, danger, and focus colors must remain readable against their corresponding surfaces.

### Typography

Use the existing local system sans-serif stack with no network font request. Retain the compact typographic scale, negative heading tracking, and clear weight contrast between person names, roles, departments, and metadata.

### Layout and components

```text
+------------------------------------------------------------------+
| Company and chart metadata                    Refresh / Sign out |
+------------------------------------------------------------------+
| Organization groups                                              |
|  v Reporting structure                               N employees |
|  +------------------------------------------------------------+  |
|  | > Manager identity                    employment metadata   |  |
|  |   role · department                 X direct · Y total      |  |
|  +------------------------------------------------------------+  |
|      |-- nested manager / employee cards                         |
+------------------------------------------------------------------+
```

- Keep the existing maximum-width, left-aligned content layout.
- Increase surface radii to roughly `10–12px`; use smaller radii for controls and badges to preserve hierarchy.
- Replace the prominent page grid with a quieter canvas treatment so reporting connectors carry the structure.
- Keep the whole parent card as the disclosure summary and retain collapsed-by-default behavior.
- Use restrained hover elevation and visible keyboard focus only where elements are interactive.
- Let metadata and actions wrap naturally on narrow screens without reducing tap targets.

## Report count behavior

- `directCount` is `person.reports.length`.
- `totalCount` is the recursive number of all descendants, excluding the manager.
- When `totalCount > directCount`, show `N direct · M total reports`.
- Otherwise show the existing singular/plural form: `1 direct report` or `N direct reports`.
- Leaf employees continue to show `0 direct reports`.
- Counts are derived from the rendered tree, so they are consistent with the visible hierarchy and require no backend changes.

## Dark mode

Define semantic CSS custom properties for light mode in `:root`, then override them inside `@media (prefers-color-scheme: dark)`. Set `color-scheme` so native controls match the active system appearance. There is no manual toggle and no JavaScript theme state.

## Accessibility and motion

- Preserve native `<details>` and `<summary>` keyboard behavior.
- Do not override the parent summary's accessible name; its visible descendant text supplies the name and description.
- Keep visible `:focus-visible` outlines in both themes.
- Respect `prefers-reduced-motion` for disclosure and hover transitions.
- Maintain sufficient contrast for muted copy, badges, unassigned state, warnings, errors, and disabled controls.

## Verification

- Component tests prove nested totals, direct-only counts, singular grammar, leaf counts, and disclosure behavior.
- Frontend tests, lint, and production build pass.
- `git diff --check` passes.
- Inspect the application in both emulated light and dark system appearances at desktop and mobile widths.


# Compact Monaco three-way panes

- Status: Implemented and validated
- Owner: GitN
- Date: 2026-11-07

## Summary

Make the three Monaco conflict panes display their own file lines compactly. Their scroll positions remain correlated by common/conflict segment progress, so a pane with fewer lines scrolls at a different rate rather than receiving blank view-zone padding. Render each source-line toggle as a checkbox instead of a plus sign.

## Behavior Change

- Before any choice, unequal sides show no artificial rows to match the ancestor or the longer side.
- Choosing source lines can grow or shrink output without adding blank rows beneath the other panes.
- A source-line gutter toggle has unchecked and checked checkbox states; clicking it still toggles that exact source line.
- Zero-line conflict sides retain a compact whole-block action and all three panes retain conflict navigation and synchronized scrolling.

## Non-Goals

- Do not change diff3 partitioning, line-membership/order semantics, save gates, Git index handling, or the general file inspector.
- Do not copy proprietary GitKraken source or assets.

## Change Boundary

- In scope: Monaco conflict host geometry, source-line toggle styling, WebView smoke and pure JS geometry tests, and the existing three-way RFC description.
- Out of scope: Swift document/service algorithms, normal diff rendering, toolbar layout, and conflict file fixtures.
- Protected hotspots reviewed: no new responsibility in RepoViewModel or GitService.

## Ownership

- Primary owner layer: Monaco conflict host for visual geometry, scroll mapping and line-gutter controls; CSS for appearance.
- Why this layer is the right owner: This is rendering-only state derived from the existing structural payload; the native document remains authoritative for choices and output.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not take on rendering or scroll state.

## Test Scope

- Unit tests: segment geometry stays compact on unequal and zero-length blocks; mapping changes scroll rate within unequal segments and still matches common boundaries.
- Integration tests: real WKWebView has no spacer zones before or after selection, source checkbox toggles emit line action, and bidirectional scroll mapping survives output growth.
- Manual verification: large 7k-line conflict fixture, initial and post-selection density, both scroll directions, checked/unchecked presentation.
- Failure modes / edge cases: empty side, near EOF, changed output length, metadata refresh, and scroll feedback loops.
- Known coverage blockers: no automated macOS screenshot comparison for checkbox appearance.

## Design Records

- RFC required? no new RFC; this refines the scroll geometry already owned by the existing Monaco three-way RFC, which will be updated.
- ADR required? no new boundary or repository-wide policy; the structural three-way ADR remains valid.

## Completion Criteria

- No artificial per-block line-height spacer remains in any pane.
- Navigating and scrolling align corresponding conflict segments at adaptive rates.
- Every selectable source line shows a checkbox state and toggles correctly.
- JS tests, WKWebView smoke, and focused build pass.

## Follow-up: Whole-block Checkbox Mouse Routing

- Behavior change: clicking the checkbox beside Take A block or Take B block with a real mouse selects that block exactly once; keyboard activation remains available. Include the zero-line-side whole-block control. Disable Monaco sticky headers in merge panes so conflict navigation does not hide these controls.
- Non-goals: no change to diff3 partitioning, output ordering, per-line choice semantics, scroll geometry, save/resolve behavior, or native Git operations.
- Boundary: the Monaco conflict host view-zone control, merge-pane editor options, and its WKWebView interaction test; no change to RepoViewModel, GitService, or other editors.
- Owner: the Monaco host view layer owns pointer-event routing for its own controls. Native document state remains the source of truth for selection.
- Test scope: exercise WebKit hit-testing plus pointer down/up on A, B, and empty-side block controls in WKWebView; check sticky headers are disabled and retain keyboard-focusable controls and per-line checkbox coverage; manually verify in an independent Swift preview without touching the user's active session.
- Design records: this local UI event-routing fix needs this feature intake only; the existing Monaco RFC and structural ADR remain unchanged.
- Completion criteria: whole-block controls remain visible after conflict navigation, respond to a real pointer click once, retain keyboard activation, and do not steal per-line actions or editor scrolling.

## Consolidated Validation — 2026-11-07

- Full workspace Swift suite: 517 tests, 5 git-lfs-dependent skips, zero failures; includes structural merge, conflict mutations, external Markdown and security coverage.
- Monaco frontend: 35 tests passed; production build and standard native WebKit smoke passed with upgraded dependencies.
- Conflict native WebKit smoke passed: line/block actions, undo/redo, source switching and editing; zero script errors.
- Repository intake harness and git diff --check passed after required intake fields were completed.

# Feature Intake: Diff modes and selection feedback

- Status: Implemented and validated
- Owner: GitN UI
- Date: 2026-11-07

## Summary

Normalize worktree children to the compact sidebar row language, introduce three text diff layouts, and soften graph/sidebar selection feedback.

## Behavior Change

Inline remains default. Hunk shows independent titled blocks with three context lines and hides the content between blocks; Split aligns original/modified sides. Display preference persists and switching preserves unsaved text and Git hunk actions. Worktree paths move to tooltips. Graph selection and sidebar feedback use 140 ms fades honoring Reduce Motion.

## Non-Goals

No three-way merge changes, Git mutation changes, graph layout/pagination changes, eager history loading, or exact GitKraken animation parity. Existing Kraken analysis does not establish animation timings.

## Change Boundary

- In scope: SidebarView, GraphView, SourcePreviewView, MonacoInspectorView, Monaco host assets and tests.
- Out of scope: Three-way merge, repository loading, Git operations, top chrome colors, provider integrations.
- Protected hotspots reviewed: RepoViewModel and GitService gain no responsibilities; existing uncommitted three-way work is preserved.

## Ownership

- Primary owner layer: Views and Monaco rendering host.
- Why this layer is the right owner: Layout preference, hunk section layout and visual feedback are rendering state; existing patch metadata remains authoritative for actions.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService.

## Test Scope

- Unit tests: JS host mode configuration, disposal, edit forwarding, Git hunk identity/action routing, metadata updates, empty/add/delete files; Swift local edit echo across layouts and graph cell reuse.
- Integration tests: WKWebView smoke runs production Monaco DiffEditor/worker, mode switches, pure deletion and existing Inline/Preview cases.
- Manual verification: Light/dark, Reduce Motion, compact sidebar rows, rapid graph selection, narrow inspector and stage/discard UI remain interactive visual checks.
- Failure modes / edge cases: Unsaved edits across modes, stale action controls after edits, native original read-only, source identity, model eviction and cell reuse.
- Known coverage blockers: Light appearance was visually checked in the preview app; dark appearance and live Reduce Motion switching remain manual checks. The compact three-way intake fields have since been completed; the full workspace harness now passes.

## Design Records

- RFC required? Yes, cross-screen presentation and native/web bridge: docs/rfcs/2026-11-07-diff-modes-sidebar-motion.md.
- ADR required? No, no new durable architecture or policy.

## Completion Criteria

Three selectable text diff layouts, safe existing Git hunk actions, preserved unsaved edits, compact worktree rows, finite selection transitions, relevant tests/build passing with validation gaps recorded.

## Open Questions

None blocking. User confirmed Kraken-style independent hunk sections; see correction intake below.

## Validation Results

- `swift build`: passed.
- `swift test --filter 'CommitSelectionFeedbackTests|MonacoLocalEditEchoTests'`: 6 tests passed.
- `node --test Monaco/tests/*.test.cjs`: 35 tests passed (including the Hunk correction).
- Production WKWebView smoke: passed; native diff calculation, read-only original, mode switches, unsaved content, pure deletion, active child disposal, 1k/10k/50k Inline/Preview checks, editor/JSON/TypeScript workers.
- Existing conflict WKWebView smoke: passed; no script errors.
- UI preview: compact worktree row matches branch rows; graph selection visible; Inline/Split/Hunk controls work; Hunk shows independent range headers and cropped context, without native fold widgets.
- Build compatibility: pinned Webpack 5.99.9 fixes missing imported bindings in native diff conversion; generated Monaco resources rebuilt.
- Preview app: `/private/tmp/GitN-HunkSectionsPreview.app`, isolated bundle identifier; signed and launched with current Monaco resources, current GitN repository open in Hunk view.
- `git diff --check`: passed. Existing unrelated uncommitted three-way changes retained.

## Hunk correction intake — 2026-11-07

- Behavior change: User confirmed Kraken-style independent hunk sections in one scrollable view. Replace native expandable unchanged-region folding with explicit cropped hunk ranges, `@@ -old,count +new,count @@` headers, gaps, and per-section Git actions. Multiple hunks remain continuously scrollable.
- Non-goals: No single-active-hunk pager, no Inline/Split or Git mutation changes, no snapshot/RepoViewModel expansion.
- Boundary / owner: Pure Monaco hunk layout helper owns range merging/hidden ranges and action association; host owns headers, zones and rendering-only state. Native full-text models preserve source line numbers and edit semantics.
- Test scope: Context boundaries/merge, insertion/deletion/empty files, exact Git hunk association, mode cleanup, metadata refresh, native WebKit multi-block rendering/navigation and existing conflict regression.
- Design records: Amend existing RFC before code; no ADR needed.
- Completion criteria: Independent titled hunk blocks; no fold widgets or content between blocks; correct per-block actions and navigation; stable model edits; tests and visual preview verified.
- Evidence: Previously extracted Kraken renderer bundle, factories 89526 (setupHunkFoldingAndOverlaysAndZones/createAndUpdateHunkHeaderOverlays), 22619 (makeHunkDataStructure/makeAddViewZoneForHunk), 43659 (toolbar modes). Exact provenance and REA results recorded in RFC.

## Hunk correction validation

- Production Monaco bundle rebuilt with Webpack 5.99.9; resources synchronized.
- All 35 JavaScript tests passed, including pure hunk ranges/association and host header lifecycle/action routing.
- Production WKWebView smoke passed: independent headers, no native folding widgets, pure deletion, no-change files, layout switches, edit preservation and editor disposal; existing worker and large-file checks also passed.
- Native app visual check: GitNResources.swift in commit d0a9512 displays two independent `@@` sections; first context ends at modified line 21 and the second starts at 65, with intervening content hidden and clear header spacing.
- `git diff --check` passed. Dark appearance and live Reduce Motion switching remain the manual gaps recorded above.

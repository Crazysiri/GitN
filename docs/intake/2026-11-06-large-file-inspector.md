# Feature Intake: responsive large-file inspector

- Status: Implemented; manual interaction review pending
- Owner: Codex
- Date: 2026-11-06

## Summary

Preview loads the selected snapshot without waiting for its patch or per-line diff artifacts. The Monaco host reuses an editor within each mode and computes its custom unified diff in a cancellable worker after displaying the text. Metadata updates preserve the editor. Superseded inspector opens cannot publish content or loading state.
Diff mode also publishes the selected snapshot as read-only text before waiting for its patch. Once the patch and action metadata arrive, it enables editing and replaces the provisional same-text baseline with the true old side.
Blame enrichment follows the same selection boundary: a canceled or superseded blame request cannot publish labels or replace the active cache after switching files or closing the inspector.

## Behavior Change

Text appears before diff decorations. Preview omits patch/per-line artifact work. One editor and model stay active per mode; superseded worker results are discarded.

## Non-Goals

No DiffEditor migration, three-way merge redesign, stash backend rewrite, Git mutation semantics changes, or unbounded document cache.

## Change Boundary

- In scope: standard preview/diff inspector loading, active editor reuse, worker scheduling and build integration.
- Out of scope: compare-mode patch optimization, stash backend, merge UI and Git writes.
- Protected hotspots reviewed: RepoViewModel only coordinates existing reads and guards request generations; GitService unchanged.

## Ownership

- Primary owner layer: Monaco host plus pure diff/scheduler helpers; ViewModel orchestrates snapshot loading.
- Why this layer is the right owner: editor lifecycle is WebView state; diff computation can be tested independently.
- Which larger type is intentionally not taking more responsibility: GitService; RepoViewModel gains no diff algorithm or worker policy.


The Monaco host owns editor lifecycle and decorations; a pure worker module owns diff computation and budgets. RepoViewModel only changes existing inspector orchestration and request validation; it does not absorb a new service. GitService remains unchanged. Build script invalidation must include worker sources.

## Affected Areas

File inspector preview/diff, Monaco host and webpack entries, RepoViewModel.openFileInspector, focused Swift and Node tests.

## Test Scope

Node tests: real diff results including deletion, Unicode, trailing newline, 10k+ lines, budget exhaustion; worker request supersession and host lifecycle with mocks. Swift integration tests: preview bypasses patch/artifacts and mode changes still load diff. Build bundled resources and Swift app; smoke-test worker in WKWebView if available. Manually verify scrolling/focus/stage controls where feasible. Preserve existing hunk mapping; async decoration results must match document revision before installing controls.

- Unit tests: 13 Node diff/scheduler/host tests; Swift DiffContentLogicTests (41 discovered, 40 passed, one pre-existing skip).
- Integration tests: native WKWebView local-resource smoke with Blob Worker, 12,002-line model, editor reuse/disposal, metadata preservation.
- Manual verification: full app scrolling, focus, stage/discard and end-to-end latency remain for user review.
- Failure modes / edge cases: cancellation, timeout, obsolete results, Unicode columns, pure deletion and untracked preview.
- Progressive diff: the first text belongs to the selected path; switching files during patch loading cannot publish the earlier file; a user cannot edit provisional text that would be overwritten on completion.
- Blame publication check: capture inspector-open, file-selection and blame-request generations; revalidate them before updating the cache and line labels. The existing selection-token tests cover the generation rule; rapid file-switch blame rendering still needs manual review because the Git service has no injected delay seam.
- Known coverage blockers: no automated visual interaction or app latency measurement; WK smoke emitted generic Script errors alongside successful assertions (recorded in RFC). The full Swift suite ran 410 tests with five skips and three failures because this machine has no `git lfs` command; all other tests passed.

## Design Records

- RFC required? Yes: ../rfcs/2026-11-06-large-file-inspector.md (cross-layer loading and worker flow).
- ADR required? No: bounded optimization inside the existing inspector boundary, no repository-wide policy.

## Completion Criteria

Preview skips diff loading; latest request owns content/loading; diff computation does not run on the WebView main thread; repeated content loads in the same mode reuse editor; failure/time budget leaves readable text and explicit status; tests and build pass or concrete limitations recorded.

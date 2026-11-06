# RFC: responsive large-file inspector

- Status: Accepted for first iteration
- Owner: Codex
- Date: 2026-11-06

## Problem / Scope

Large documents incur patch reads before preview, duplicate per-line artifacts, synchronous WebView JsDiff and editor destruction on source changes. Optimize the existing inspector; do not migrate to DiffEditor or change Git write behavior.

## Design

Preview selects the file synchronously, invalidates prior diff loading, reads its snapshot and publishes plain content without diff artifacts. Diff follows the current patch/action mapping path. An inspector-open generation guards every asynchronous publication including loading completion. Existing ViewModel responsibility is narrowed rather than expanded.
Diff now reads and publishes the selected snapshot before waiting for patch/action metadata. During that provisional stage the model is read-only and uses the same text as its baseline, so it shows no false additions. After the patch loads, the existing diff pipeline installs the real baseline and controls. The open-generation check guards both stages.

The host retains the current editor within a mode, switches models and disposes the previous model after detachment; no cross-document undo/cache is introduced. Store view state per path in a bounded map, and restore only the matching path. Mode switches may rebuild the editor because the preview/diff DOM differs.

Extract the existing unified diff algorithm into a pure CommonJS module, bundled solely into a dedicated worker. A small testable scheduler owns one worker, latest request token, cancellation by worker termination, and a hard deadline. Edits debounce diff computation; content first appears immediately. On new requests remove stale diff actions/decorations. Results install only for the matching editor model and version. Worker errors/budget exhaustion show status while preserving plain text. Main thread never falls back to synchronous full diff.

Keep hunk metadata separate from content. A result uses the latest metadata for the same selected document. Git actions remain governed by existing Swift action eligibility and dirty-state restrictions.
For asynchronous blame, capture a fresh enrichment token for every request and invalidate it on close. Before publishing, check that token, the open generation, the file selection generation and the selected path. Cancellation alone does not guarantee that an in-flight Git read stops before its result arrives.

## Alternatives

Monaco DiffEditor would alter deletion zones and action mapping and needs separate validation. Unbounded model caches consume memory; this version retains only the active model plus bounded view-state snapshots. Main-thread asynchronous JsDiff still shares the UI thread; use a real Worker.

## Tests / Rollout / Risks

Pure diff fixtures, cancellation/error/timeout scheduling, host reuse and stale-result tests, preview integration tests, bundle build, Swift tests and WKWebView worker smoke test. Worker loading from local resources must be checked; failure is visible and leaves readable text. Build cache must notice source edits. No data migration. Performance measurements use generated 10k/50k-line documents, reported separately from actual application latency.

## Implementation / Validation (2026-11-06)

The worker is compiled first as a self-contained bundle, embedded by the Monaco compiler as source, and instantiated from a Blob URL. Direct file workers failed in native WKWebView; the Blob implementation passed. Both compilers are part of npm run build. No new runtime dependency. Generated bundles remain ignored and are synced into app resources by the build script.

- npm test: 13 passing (real diff, UTF-16 columns, 10k lines, budgets, cancellation/error/deadline, host editor reuse and scroll restoration, stale results, readable timeout fallback, line-number width and red deletions).
- npm run build / Scripts/build_monaco.sh: passed, resources synced.
- swift test --filter DiffContentLogicTests: 41 discovered, 40 passed, one existing skip; includes 12k-line preview→diff and untracked Markdown preview. App target compiled successfully as part of tests.
- swift Monaco/tests/wkwebview-smoke.swift: passed in native WKWebView with local resources and a 12,002-line active model; checked Blob Worker, preview/diff editor reuse, old model disposal and unchanged metadata preserving the model. Two generic host Script errors were logged during the latest full editor smoke; assertions and diff decorations completed successfully. Their source is unresolved; do not interpret this as a clean console or complete UI acceptance.
- Full `swift test`: 410 tests executed, five skipped, three failures limited to Git LFS tests because `git lfs` is not installed on this machine.
- Actual file-opening latency, scrolling/focus quality, undo and stage/discard need full app manual review. Algorithm fixture timings are not app benchmarks.

Preview also avoids the second raw-data read when decoded content is text. Compare-mode preview still follows its existing compare loader and is outside this iteration. No stash/three-way backend changes.

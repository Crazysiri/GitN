# Feature Intake: Monaco Deleted-Line Visibility

- Status: Implemented and preview-verified
- Owner: GitN
- Date: 2026-11-06

## Summary

Restore red deleted lines in the unified Monaco inspector diff and keep large-file diff computation from blocking text display. The current renderer places deleted rows in a view zone with a separate overlay; a failed model or overlay pass can leave only additions visible.

## Behavior Change

- Deleted text and its red background appear for replacements, pure deletions, and deletions at file boundaries.
- The old and new line-number columns stay separate when switching files and when line counts exceed two digits.
- The selected file text appears immediately; diff decoration runs asynchronously and stale results cannot decorate another file.
- Failure to compute a large diff is visible, while the file content remains readable.

## Non-Goals

- No change to Git patch application or three-way conflict semantics.
- No change to Monaco's editing model or GitKraken asset reuse.

## Change Boundary

- In scope: tracked Monaco entry/host/style sources, build assets, Node tests, WKWebView smoke test.
- Out of scope: full inspector state architecture and unrelated styling.
- Protected hotspots reviewed: renderer-only behavior remains in Monaco; no Git logic added to RepoViewModel.

## Ownership

- Primary owner layer: Monaco host and its diff worker.
- Why this layer is the right owner: deleted rows are generated and painted in the WebView.
- Which larger type is intentionally not taking more responsibility: RepoViewModel supplies text only.
- Why: deleted rows are generated and painted in the web view.
- Larger type intentionally not expanded: RepoViewModel only supplies before/after text.

## Affected Areas

- Screens / flows: file inspector diff mode.
- Services / helpers / view models: Monaco payload renderer and worker.
- Files likely to change: Monaco/src, Resources/Monaco/host.js, host.css, renderer tests.

## Test Scope

- Unit tests: deletion entries for replacement/pure deletion, rendering zones, stale-result cancellation.
- Integration tests: WKWebView DOM smoke with visible red deletion content and a large file.
- Manual verification: dark/light themes, top/middle/bottom deletion, scroll and rapid file switching.
- Failure modes: worker failure/timeout, view-zone measurement, absent before/after text.
- Failure modes / edge cases: worker failure, file URL restrictions, view-zone measurement, and absent text.
- Known coverage blockers: long-running rapid-switch performance and every file type have not been manually profiled; the representative running-app diff and WKWebView cases passed.

## Design Records

- RFC required? Yes; worker and host lifecycle cross a bundle boundary.
- ADR required? No; this is a scoped renderer change.

## Completion Criteria

- Both deleted content and red styling are present in WKWebView; large-file text loads without synchronous diff work; host and worker tests pass.

## Verification (2026-11-06)

- Switching files called editor.updateOptions(editorOptions(...)), resetting the diff's 10-character line-number gutter to the preview default of 4. Diff reuse now retains two-column width, expanding to 12 characters for a 12,000-line file.
- Node host tests passed 11/11; WKWebView smoke covered replacements, pure deletions, dark/light red backgrounds, three-digit numbers, and 12,000 lines. A running InspectorPreview showed red deleted and green added lines with separate old/new numbers.
- Release build, harness checks, and code signing of the updated preview bundle passed.

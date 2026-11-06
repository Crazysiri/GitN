# Feature Intake: Large Markdown Editor Responsiveness

- Status: Implemented; 50,001-line preview interaction verified
- Owner: GitN
- Date: 2026-11-06

## Summary

Keep Markdown editing responsive for large files by avoiding full-document regex highlighting and eager layout on every update or redraw.

## Behavior Change

- Markdown source larger than the existing 256 KB rich-render cap stays editable as plain monospaced text without full-document syntax colors.
- The line-number view lays out only its visible rectangle when drawing; small documents retain syntax colors.

## Non-Goals

- No Markdown parser replacement, Monaco migration, diff algorithm change, or Git mutation change.

## Change Boundary

- In scope: Markdown editor highlight policy and LineNumberTextView layout.
- Out of scope: file loading, rich Markdown rendering, inspector diff and Git operations.
- Protected hotspots reviewed: neither RepoViewModel nor GitService changes.

## Ownership

- Primary owner layer: AppKit Markdown editor and its line-number view; a pure policy chooses whether whole-file highlighting is safe.
- Why this layer is the right owner: the blocking work occurs in these views.
- Which larger type is intentionally not taking more responsibility: RepoViewModel.

## Affected Areas

- Screens / flows: inspector Markdown Edit mode and standalone Markdown editor.
- Services / helpers / view models: none.
- Files likely to change: MarkdownPreviewView.swift, LineNumberTextView.swift, Markdown tests.

## Test Scope

- Unit tests: highlight policy at and above the threshold.
- Integration tests: Swift app build and relevant XCTest suite.
- Manual verification: open/edit/scroll a 50,000-line Markdown file and verify text and line numbers.
- Failure modes / edge cases: small-file colors remain; large-file edit has no forced full layout.
- Known coverage blockers: end-to-end frame timing needs uncontended GUI access.

## Design Records

- RFC required? No; local view-only behavior and policy with no new cross-module contract.
- ADR required? No; no enduring architecture boundary.

## Completion Criteria

- Large Markdown editing no longer performs full regex highlighting or eager whole-file layout per input; tests and app build pass.

## Verification (2026-11-06)

- Full Swift suite: 445 tests, 5 skipped, 0 failures; Release build passed.
- In the signed feature-preview app, opened a 50,001-line Markdown fixture, switched from Preview to Edit, scrolled, and jumped to the final line. The final text and five-digit line numbers remained visible without a crash.
- This confirms interaction and correctness for the fixture; it is not a benchmark of frame time or all large-file sizes.

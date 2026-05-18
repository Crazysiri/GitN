# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-27

## Summary

Fix a crash that occurs when previewing Markdown code blocks in script-built GitN app bundles. The crash is triggered when `HighlightSwift` attempts to initialize its bundled highlight.js resources and those resources are unavailable from the packaged app at runtime. The change makes Markdown code-block rendering fall back to plain text when syntax-highlighting resources are unavailable instead of crashing.

## Behavior Change

- Markdown preview will stop attempting syntax highlighting when highlight resources are unavailable and will render plain code blocks instead of crashing.

## Non-Goals

- Mermaid rendering behavior is not changing.
- Markdown preview layout and theming are not changing.
- No upstream changes to the `HighlightSwift` dependency are included.

## Change Boundary

- In scope:
  - Markdown preview code-block highlighting decision logic
  - Targeted tests for the fallback decision
- Out of scope:
  - `RepoViewModel`
  - `GitService`
  - General resource-loading refactors outside Markdown preview
- Protected hotspots reviewed:
  - `RepoViewModel` not involved
  - `GitService` not involved

## Ownership

- Primary owner layer: view/helper plus build script
- Why this layer is the right owner: the issue is caused by resource packaging plus a view-level decision to invoke third-party syntax highlighting
- Which larger type is intentionally not taking more responsibility: `RepoViewModel`

## Affected Areas

- Screens / flows:
  - Markdown preview code block rendering
  - Script-built app runtime resource loading
- Services / helpers / view models:
  - `GitNResources`
  - Markdown preview helper logic
- Files likely to change:
  - `GitN/Sources/GitN/App/GitNResources.swift`
  - `GitN/Sources/GitN/Views/MarkdownPreviewView.swift`
  - `GitN/Tests/GitNTests/MarkdownPreviewRenderingTests.swift`

## Test Scope

- Unit tests:
  - Markdown code block selection falls back when highlight resources are unavailable
- Integration tests:
  - None planned
- Manual verification:
  - Open a Markdown file with fenced code blocks in a script-built app that does not expose `HighlightSwift` resources
- Failure modes / edge cases:
  - Missing `HighlightSwift` bundle
  - Missing `highlight.min.js` inside the bundle
- Known coverage blockers:
  - No automated packaging test currently exercises the final `.app` bundle layout

## Design Records

- RFC required? No. Localized bug fix with clear ownership and no new cross-cutting boundary.
- ADR required? No. No durable architecture or repository-wide policy change.

## Completion Criteria

  - Markdown preview does not crash when highlight resources are absent
  - Tests cover the fallback decision path

## Open Questions

- None at intake time

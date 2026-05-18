# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-29

## Summary

Reduce stutter when the middle file inspector switches between regular source files and Markdown files by keeping rich Markdown rendering for smaller documents and automatically falling back to a lighter plain-text preview for Markdown content that is large enough to trigger expensive text layout.

## Behavior Change

- Markdown files in the file inspector and standalone Markdown preview continue to render as rich Markdown for smaller documents.
- Larger Markdown documents now open in a plain-text preview by default instead of the rich Markdown renderer, avoiding repeated layout spikes during file switching.
- The UI indicates when a Markdown document is being shown in the lighter preview mode.

## Non-Goals

- Changing git loading, file selection, or `RepoViewModel` orchestration.
- Replacing the existing Markdown renderer for small documents.
- Adding a new persisted user preference for preview mode.

## Change Boundary

- In scope: Markdown preview rendering decisions, Markdown preview presentation, file inspector Markdown branch, targeted tests for the new heuristic.
- Out of scope: Monaco diff behavior, non-Markdown preview rendering, git services, hosted review flows.
- Protected hotspots reviewed: `RepoViewModel` and `GitService` remain unchanged because this is a view-layer rendering policy decision.

## Ownership

- Primary owner layer: View/helper.
- Why this layer is the right owner: the change is a presentation-time rendering policy based on the current Markdown text size and should stay local to preview rendering.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is intentionally not taking on Markdown performance policy.

## Affected Areas

- Screens / flows: middle file inspector preview, standalone Markdown preview window.
- Services / helpers / view models: Markdown preview helper only.
- Files likely to change: `GitN/Sources/GitN/Views/MarkdownPreviewView.swift`, `GitN/Sources/GitN/Views/SourcePreviewView.swift`, `GitN/Tests/GitNTests/MarkdownPreviewRenderingTests.swift`.

## Test Scope

- Unit tests: Markdown preview fallback heuristic thresholds and explicit small/large document cases.
- Integration tests: none for this UI-only rendering decision.
- Manual verification: switch repeatedly between a regular source file and a large Markdown file in the file inspector; verify small Markdown still renders richly; verify large Markdown shows the lighter preview without the previous stall.
- Failure modes / edge cases: thresholds accidentally disable rich preview for small docs; editable Markdown still switches to editor mode correctly; read-only large Markdown remains selectable and scrollable.
- Known coverage blockers: UI rendering smoothness must be verified manually.

## Design Records

- RFC required? No. This is a local UI-only rendering policy change with clear ownership.
- ADR required? No. This does not establish a long-lived architectural boundary.

## Completion Criteria

- Large Markdown files no longer route through the expensive rich Markdown renderer in the affected preview surfaces.
- Small Markdown files still render with the existing Markdown presentation.
- The new heuristic is covered by unit tests.
- Manual verification confirms the file inspector no longer stalls noticeably when switching between source and large Markdown files.

## Open Questions

- The exact threshold may need a follow-up adjustment after profiling more repositories.

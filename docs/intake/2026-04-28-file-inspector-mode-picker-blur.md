# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-28

## Summary

Adjust the file inspector mode picker rendering so the `Preview` / `Diff` / `History` segmented control remains crisp on high-DPI displays during markdown preview and diff workflows. The change removes view-level scaling that causes the segmented control to be rasterized and interpolated.

## Behavior Change

- Users should see sharp text and symbols in the file inspector mode picker on Retina and 2.5K displays.
- The picker should keep its existing modes and behavior without visual blur caused by fractional scaling.

## Non-Goals

- No changes to markdown rendering, Monaco diff rendering, or file inspector mode-switch behavior.
- No redesign of the inspector header layout or chrome styling beyond what is needed to preserve crisp rendering.

## Change Boundary

- In scope: file inspector header layout and segmented picker rendering in `SourcePreviewView`.
- Out of scope: markdown preview internals, diff editor internals, repo toolbar, and unrelated segmented controls.
- Protected hotspots reviewed: `RepoViewModel` and `GitService` are not involved; this stays in the view layer.

## Ownership

- Primary owner layer: View.
- Why this layer is the right owner: the bug is caused by presentation-time scaling of a native segmented control.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` should not own rendering fixes for header controls.

## Affected Areas

- Screens / flows: file inspector header in preview, diff, and history modes.
- Services / helpers / view models: none.
- Files likely to change: `GitN/Sources/GitN/Views/SourcePreviewView.swift`.

## Test Scope

- Unit tests: none; this is a rendering-only layout fix.
- Integration tests: none.
- Manual verification: open the file inspector on markdown and diffable text files, switch between `Preview`, `Diff`, and `History`, and confirm the segmented control is sharp and layout remains stable.
- Failure modes / edge cases: picker becomes too large for the header row, or alignment shifts noticeably after removing scaling.
- Known coverage blockers: no automated UI snapshot coverage for AppKit-backed segmented control sharpness.

## Design Records

- RFC required? No. This is a local UI-only rendering fix with clear ownership.
- ADR required? No. No durable architecture or policy decision is changing.

## Completion Criteria

- The file inspector mode picker no longer uses view scaling that can blur the control.
- The project builds successfully.
- Manual verification guidance is recorded for the affected preview/diff/history flows.

## Open Questions

- If the unscaled native control feels too large after the blur fix, a follow-up should adjust spacing or width without reintroducing scale transforms.

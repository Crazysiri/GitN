# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-24

## Summary

Fix file history commit loading so rename-only or copy-follow history entries still produce a renderable patch instead of an empty or metadata-only result when users select them in the file history panel.

## Behavior Change

- Selecting a file history entry that was reached through rename/copy follow history will now fall back to a commit-scoped `git show` patch when the current `git log -1 -p --follow` query returns no hunks.
- The file history panel should show content for those entries instead of the current empty/no-content outcome.

## Non-Goals

- Do not redesign the file history UI.
- Do not change commit list ordering or follow-history resolution.
- Do not add provider-specific or repo-specific logic.

## Change Boundary

- In scope: file history patch loading command selection, targeted service tests for rename history.
- Out of scope: `FileHistoryView` layout, Monaco diff rendering, broader diff parsing changes.
- Protected hotspots reviewed: `RepoViewModel` remains orchestration-only; `GitService` change is limited to existing file-history patch retrieval behavior.

## Ownership

- Primary owner layer: Service/helper.
- Why this layer is the right owner: choosing the git CLI query and fallback behavior is repository-command plumbing, not view or view-model policy.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is not taking on command fallback logic.

## Affected Areas

- Screens / flows: file inspector history mode.
- Services / helpers / view models: `GitService.fileLogDiff`.
- Files likely to change:
  - `GitN/Sources/GitN/Services/GitService.swift`
  - `GitN/Tests/GitNTests/GitServiceBehaviorTests.swift`

## Test Scope

- Unit tests: verify rename-history file diff retrieval returns a patch with hunks instead of metadata-only output.
- Integration tests: none planned.
- Manual verification: open file history for a copied/renamed file and confirm problematic commits render content.
- Failure modes / edge cases: rename-only commits, copy-follow history entries, existing copy commits that already return hunks should keep their current output path.
- Known coverage blockers: UI rendering of the Monaco history panel remains manual.

## Design Records

- RFC required? No. This is a focused bug fix inside an existing service boundary.
- ADR required? No. No long-lived architectural decision changes.

## Completion Criteria

- Selecting rename/copy-follow file history entries yields non-empty, renderable patch content.
- Automated tests cover the fallback case.

## Open Questions

- None.

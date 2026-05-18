# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-30

## Summary

Remove the main-thread linear commit scan used during commit navigation so clicking branches or navigating by abbreviated hashes does not stall the app when the target commit is far back in history.

## Behavior Change

- Navigating to a branch tip no longer falls back to scanning the loaded commit array by short hash on the main thread.
- Navigating by an abbreviated commit hash still works, but the abbreviation is resolved through git to a full commit hash before pagination-based reveal continues.
- Older branch targets should remain reachable without UI hangs even when they are not part of the currently loaded commit page.

## Non-Goals

- Changing commit pagination strategy or graph layout behavior.
- Reworking reflog navigation or tag navigation beyond what is needed for this lookup fix.
- Adding new long-lived navigation state outside the existing `RepoViewModel` flow.

## Change Boundary

- In scope: commit lookup behavior used by commit navigation, abbreviated hash resolution, targeted regression tests for branch navigation and abbreviated commit navigation.
- Out of scope: commit graph rendering, diff loading, provider integrations, theme/UI changes.
- Protected hotspots reviewed: `RepoViewModel` remains orchestration-only and does not gain new provider logic; `GitService` only gains a focused git revision-resolution helper.

## Ownership

- Primary owner layer: ViewModel orchestration plus service/helper.
- Why this layer is the right owner: navigation flow belongs in `RepoViewModel`, while revision parsing/resolution belongs in `GitService` because it is a git operation.
- Which larger type is intentionally not taking more responsibility: `RepoViewModel` is intentionally not learning git revision parsing rules itself.

## Affected Areas

- Screens / flows: sidebar branch navigation, commit-detail parent/reflog navigation when abbreviated hashes are used.
- Services / helpers / view models: `RepoViewModel`, `GitService`.
- Files likely to change: `GitN/Sources/GitN/Models/RepoViewModel.swift`, `GitN/Sources/GitN/Services/GitService.swift`, `GitN/Tests/GitNTests/RepoViewModelBehaviorTests.swift`.

## Test Scope

- Unit tests: branch navigation to an unloaded older commit; abbreviated commit navigation still resolves correctly.
- Integration tests: none beyond repo-backed `RepoViewModel` behavior tests.
- Manual verification: click a branch whose tip is far back in history and confirm the detail pane updates without a long main-thread stall.
- Failure modes / edge cases: abbreviated hashes that resolve uniquely; older commits not present in the first loaded page; missing or invalid revisions should fail without selecting the wrong commit.
- Known coverage blockers: the actual UI smoothness improvement still needs manual profiling/interaction verification.

## Design Records

- RFC required? No. This is a focused performance bug fix with clear ownership and no new cross-cutting workflow.
- ADR required? No. This does not create a new architectural boundary or repository-wide policy.

## Completion Criteria

- Branch navigation no longer performs a loaded-commit linear scan by short hash.
- Abbreviated commit navigation still reaches the intended commit.
- Regression tests cover the unloaded-branch and abbreviated-hash cases.

## Open Questions

- None for this scoped fix.

# Feature Intake

- Status: Draft
- Owner: Codex
- Date: 2026-04-30

## Summary

Promote lightweight repository refreshes to a full reload when external git commands change `HEAD` or the current branch, so the sidebar and commit view update immediately after command-line `git checkout` without requiring a tab switch.

## Behavior Change

- When the repo watcher triggers a lightweight refresh after external filesystem activity, GitN now detects whether `HEAD`, detached state, or the current branch changed underneath it.
- If branch identity changed, the view model upgrades that refresh to `loadAll()` so the LOCAL branch highlight, current branch label, and commit list refresh immediately.

## Non-Goals

- Reworking the FSEvents watcher implementation.
- Changing periodic fetch behavior or app activation behavior.
- Adding new persistent app state or UI affordances.

## Change Boundary

- In scope: repository refresh decision logic and a regression test covering external checkout during a lightweight refresh path.
- Out of scope: sidebar rendering, tab lifecycle, code hosting, and general git operation flow.
- Protected hotspots reviewed: `RepoViewModel` remains orchestration-only; no provider/network logic is added there.

## Ownership

- Primary owner layer: ViewModel orchestration.
- Why this layer is the right owner: the fix is about deciding whether an observed repository change can stay incremental or must escalate to a full reload.
- Which larger type is intentionally not taking more responsibility: `GitService` is intentionally not taking on UI refresh policy.

## Affected Areas

- Screens / flows: active repo tab after external command-line checkout.
- Services / helpers / view models: `RepoViewModel`.
- Files likely to change: `GitN/Sources/GitN/Models/RepoViewModel.swift`, `GitN/Tests/GitNTests/RepoViewModelBehaviorTests.swift`.

## Test Scope

- Unit tests: repo-backed behavior test that simulates an external checkout followed by the lightweight refresh path.
- Integration tests: none beyond existing repo-backed view-model tests.
- Manual verification: run `git checkout <other-branch>` in Terminal while the repo tab is open and confirm the LOCAL sidebar switches immediately.
- Failure modes / edge cases: external checkout to another branch; detached HEAD transitions; lightweight refresh should still remain incremental for ordinary working-tree edits.
- Known coverage blockers: actual watcher event classification still relies on manual verification.

## Design Records

- RFC required? No. This is a focused bug fix within an existing orchestration boundary.
- ADR required? No. This does not establish a new architectural rule.

## Completion Criteria

- External checkout updates the current branch UI without tab switching.
- Lightweight refreshes still avoid full reloads unless branch identity changed.
- Regression coverage exists for the fallback path.

## Open Questions

- None for this scoped fix.

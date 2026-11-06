# Feature Intake: Worktree Management

- Status: Implemented; manual sidebar interaction review pending
- Owner: GitN
- Date: 2026-11-06

## Summary

Expose linked Git worktrees in the repository sidebar. Users can create a new worktree for a new branch or an existing local branch, open it in a GitN tab, and safely remove a clean linked worktree. The existing worktree metadata watcher is separate from this user-facing workflow.

## Behavior Change

- List the main and linked worktrees with branch, path, and locked/prunable state.
- Create a worktree at an explicit destination, using either a new branch from HEAD or a selected local branch.
- Open a worktree in a tab. Confirm removal; never force-remove a dirty or locked worktree.
- Refresh the list after external changes to Git's shared worktree metadata without rebuilding the commit graph.

## Non-Goals

- No automatic deletion of branches, forced removal, remote branch creation, or switching the current tab's working directory.
- No replacement of libgit2 or change to commit graph behavior.

## Change Boundary

- In scope: a focused Git CLI-backed WorktreeService, RepoViewModel state/actions, sidebar section and sheet.
- Out of scope: general Git mutation queue and hosted review flows.
- Protected hotspots reviewed: worktree parsing and safety live in the new service; RepoViewModel only coordinates UI state and refresh.

## Ownership

- Primary owner layer: WorktreeService for porcelain parsing and Git operations; sidebar for interaction; RepoViewModel for orchestration.
- Why this layer is the right owner: Worktree metadata and mutation safety are testable without SwiftUI.
- Which larger type is intentionally not taking more responsibility: GitService gains no worktree commands; RepoViewModel gains no parser.

## Affected Areas

- Sidebar Worktrees section and local-branch context menu; AppModel's existing open-repository tab flow.
- New service and tests, plus minimal RepoViewModel metadata refresh/actions.

## Test Scope

- Unit tests: NUL porcelain parsing, branch/path states, malformed output, and worktree metadata event classification.
- Integration tests: add/list/openable path/remove, existing-branch checkout, duplicate checkout rejection, dirty/main/current removal rejection, and open-tab protection.
- Manual verification: create from current HEAD and branch context menu, open tab, inspect locked/dirty state, confirm removal.
- Failure modes / edge cases: Duplicate branch checkout, missing destination, dirty/locked worktree, stale list.
- Known coverage blockers: No automated SwiftUI click/scroll test; the add sheet and cancellation were manually inspected.

## Design Records

- RFC required? Yes; service, model and sidebar cross layers. See `docs/rfcs/2026-11-06-worktree-management.md`.
- ADR required? No; this is a scoped feature using the established Git CLI bridge.

## Completion Criteria

- All worktree actions are visible and safe, focused tests pass, app compiles, and UI behavior is manually checked or the remaining gap is recorded.

## Validation

- WorktreeServiceTests: 6 passed; RepositoryFileWatcherTests: 2 passed.
- Swift app target compiles. The add sheet and context menu are wired to the existing AppModel tab flow.
- Live click/scroll review of the new sidebar section remains pending.

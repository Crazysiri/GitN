# Feature Intake: Independent AI Workbench Tab

- Status: Ready for initial implementation
- Owner: GitN
- Date: 2026-11-08

## Summary

Add an opt-in workbench as a distinct top-level tab kind. Preserve the existing Git repository interface and reuse focused Git and Worktree services. The user approved an independent workbench rather than replacing the existing repository screen.

## Behavior Change

- Users can open a Git tab or a workbench tab from the new-tab flow.
- A Git tab and a workbench tab can coexist for the same repository.
- Recommended initial scope: persistent tasks, explicit Task–Worktree associations, Worktree management, real change inspection, and navigation to an existing Git tab.
- User confirmed initial functional Task/Worktree/change-view scope and GitN-native styling. Both Codex and Kiro are release targets; actual Agent integration is a subsequent milestone, not part of this initial slice.

## Non-Goals

- Replacing the existing Git screen or changing commit graph semantics.
- Automatically opening a tab per task or Session.
- Implicitly installing hooks, collecting prompts, or launching Agents.
- First-release semantic conflict detection, automatic merge, or task rollback.

## Change Boundary

- In scope: tab identity and persistence, new-tab entry, independent workbench presentation and state, task storage, reuse of Worktree services.
- Out of scope: existing Git screen layout, graph pagination, hosted-review behavior, broad GitService refactoring.
- Protected hotspots reviewed: RepoViewModel and GitService must not absorb task, Session, or adapter responsibilities.

## Ownership

- Primary owner layer: dedicated workbench model and focused persistence/Git-read services.
- Why this layer is the right owner: task workflows are independent of the existing Git screen.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService.

- AppModel owns tab lifecycle and routing only; a small tab descriptor/codec owns identity and compatibility mapping.
- Workbench views own presentation; a separate Workbench model owns screen state.
- A focused task store owns persistence and associations; existing WorktreeService owns Git Worktree operations.
- RepoViewModel remains responsible for its existing repository screen.

## Affected Areas

- ContentView, TabBarView, NewTabView, RepoTab, and AppModel.
- New workbench views/models and task persistence boundary.
- Existing Git tab opening can be reused for “Open in Git”.

## Test Scope

- Unit tests: tab kind decoding, legacy tab restoration, type-aware deduplication, task CRUD and associations, state restoration.
- Integration tests: task persistence across restart; Worktree association and real diff selection; missing/deleted Worktrees.
- Manual verification: mixed tab switching, drag reorder, closing/reopening, light/dark appearance, 1100-point window, existing Git workflows.
- Failure modes / edge cases: identical paths across different tab kinds, obsolete paths, invalid persistence, storage failures, externally changed files.
- Known coverage blockers: none identified; concrete storage design will define integration fixtures before coding.

## Design Records

- RFC required? Yes: cross-screen feature and new state/persistence boundaries.
- ADR required? Yes: durable independent workbench and Git surface boundary.
- See ../rfcs/2026-11-08-ai-workbench-tab.md and ../adr/2026-11-08-independent-workbench-boundary.md.

## Completion Criteria

- Existing Git tabs remain independently usable, including startup restoration.
- Workbench tabs coexist with Git tabs and have independent selection state.
- Initial scope matches the user's answers; visible data reflects real persisted tasks and Git state.
- Closing a workbench does not delete tasks or Worktrees.
- Relevant automated tests and manual regression checks pass.

## Open Questions

- Product decisions resolved: functional core first; native GitN styling; Codex and Kiro required before release.
- No further user decision is required for the initial core. Adapter capabilities and supported versions require evidence before shipping.

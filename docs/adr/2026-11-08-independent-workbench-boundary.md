# ADR: Independent Workbench and Git Surfaces

- Status: Accepted
- Date: 2026-11-08

## Context

GitN has an established per-directory Git interface and top-level tabs. Task-centric AI workflows need a new presentation and data model while their product value is still being validated. The user explicitly chose an independent new panel to preserve the existing experience.

## Decision Drivers

- Preserve the existing Git interface and multi-tab workflow.
- Make the experimental surface removable without repository conversion.
- Keep task/session logic out of RepoViewModel and GitService.

## Decision

Represent the workbench as an opt-in top-level tab kind with independent presentation and screen state. Reuse focused Git services while keeping workbench metadata behind its own persistence boundary. Git remains authoritative for code state. A workbench tab is a view of durable project/task data, not the owner of that data or of externally launched Agent lifetimes.

Opening or closing tabs must not implicitly create/delete Worktrees, install/uninstall integrations, terminate external Agents, or discard task history. Explicit user commands own those operations. Existing Git tab behavior is preserved.

## Consequences

- Positive: the workbench can be iterated or withdrawn without replacing the Git screen.
- Positive: both surfaces can inspect the same underlying repository using shared services.
- Negative: tab identity and startup persistence require type-aware compatibility handling.
- Negative: separate UI surfaces do not prevent concurrent writes to shared files.
- Follow-up: typed tab RFC, task storage design, and explicit monitoring/Agent ownership designs before those capabilities ship.

## Alternatives Considered

- Replacing the existing repository screen: rejected by the user's chosen direction.
- Adding task/session state to RepoViewModel: rejected because it widens a protected hotspot.
- Completely separate app: unnecessary duplication of Git services and navigation.

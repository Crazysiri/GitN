# Feature Intake: External Agent Sessions

- Status: Ready for implementation
- Owner: GitN
- Date: 2026-11-08

## Summary

Make discovered external conversations the workbench's default entry. Retain independent Git tabs and manual task creation. Users can associate sessions with existing Worktrees and group sessions into tasks after starting work in Codex or Kiro.

## Behavior Change

- Add a Sessions page with independent provider-scoped identities, external titles, fallback names, observed directory history, and optional task grouping.
- Discover Codex metadata through read-only local app-server requests on explicit action. Accept minimized Codex/Kiro hook events through a bundled local relay and inbox.
- Offer explicit project hook installation/uninstallation with configuration preservation and instructions; do not install anything during implementation or on application launch.
- Multiple sessions can share a Worktree; a session may have no Worktree or multiple historical associations. New directories alone never establish ownership.

## Non-Goals

- Embedded Agent chat, autonomous execution, prompt/transcript collection, inferred precise progress, automatic task grouping, or exact file attribution.
- Assuming Kiro title/list capability or installed runtime when unavailable.
- New background daemon, cross-process metadata writes, or replacing the existing Git screen.

## Change Boundary

- In scope: workbench session models/store, metadata and event parsers, local process protocol, directory resolver, relay target, setup helper, Sessions UI, packaging, focused tests.
- Out of scope: RepoViewModel, GitService, graph pagination, hosted review, AI review, rollback, arbitrary tool-argument parsing.
- Protected hotspots reviewed: new logic belongs in focused services; AppModel tab routing remains unchanged.

## Ownership

- Primary owner layer: session repository within the existing single-writer actor, focused discovery/resolution/setup services, and a workbench screen model.
- Why this layer is the right owner: external conversation identity and filesystem observation are independent of Git-screen orchestration.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService.

## Test Scope

- Unit tests: provider/namespace/ID separation, title updates, fallback names, duplicates/ordering, cwd resolution, hook minimization, setup merge/uninstall, protocol decoding.
- Integration tests: version-1 task data migration/backup, shared/moved/missing Worktrees, task grouping without a directory, relay inbox ingestion, fake app-server lifecycle and pagination.
- Manual verification: default Sessions page, new-task retention, setup disclosure, native mixed tabs, installed Codex metadata discovery without executing a turn.
- Failure modes / edge cases: tool missing, Kiro unavailable, malformed/oversized events, partial writes, timeouts, title arriving later, resume identity, nested paths/symlinks, deletion of grouped tasks, invalid persistence.
- Known coverage blockers: Kiro CLI is not on PATH on this machine; supported event fixtures and setup can be tested, but Kiro live validation remains a release gate.

## Design Records

- RFC required? Yes: new service boundaries, helper executable, persistence migration, and cross-screen workflow.
- ADR required? Existing independent workbench ADR applies; no replacement policy is needed. Relay only appends independent inbox files; the GUI remains the sole metadata writer.

## Completion Criteria

- Sessions are usable without pre-creating a task or selecting a Worktree.
- Same-provider and cross-provider sessions sharing a Worktree stay separate; resumed identities deduplicate.
- Explicit grouping and directory association preserve task titles and earlier baselines/history.
- Existing task records migrate without loss and originals are backed up before writing the new schema.
- Both hook event formats have tested ingestion; actual runtime availability is displayed accurately.
- Discovery never starts/resumes an Agent turn and never persists prompt previews or transcripts.

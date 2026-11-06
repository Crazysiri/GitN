# Feature Intake: Safe Remote Ref Sync

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Sync should remove stale remote-tracking branches and local copies of tags demonstrably fetched from a remote that has since deleted them. It must preserve local branches and locally created or changed tags. Current `--prune-tags` and an unconditional local-tag deletion pass erase unpushed tags.

## Behavior Change

- Fetch all remote tags and prune remote-tracking branches without Git's destructive tag-prune option.
- Record only tags newly acquired by a successful Sync, including the exact ref OID and remote identity. On later successful Sync, delete a tracked local tag only when it disappeared from every configured remote and still has the recorded OID.
- Skip tag cleanup on fetch or remote-query failure; report an error rather than claiming a complete Sync.
- Explicit user tag deletion remains available.

## Non-Goals

- Do not infer ownership of tags that were already local before this version first observed the repo.
- Do not delete local branches or change explicit tag commands.
- No general remote-ref database or Git backend rewrite.

## Change Boundary

- In scope: Sync flow, fetch arguments, a small tag-provenance helper, temporary-repo integration tests.
- Out of scope: periodic fetch, ordinary pull/push, repository migration.
- Protected hotspots reviewed: RepoViewModel only orchestrates Sync; GitService changes fetch options.
- Protected hotspots: `RepoViewModel` only orchestrates the helper; `GitService` only changes fetch options.

## Ownership

- Primary owner layer: RemoteTagPruner owns provenance and cleanup policy.
- Why this layer is the right owner: remote tag ownership requires persistent evidence outside UI orchestration.
- Which larger type is intentionally not taking more responsibility: RepoViewModel does not implement tag policy.
- Primary owner: `RemoteTagPruner` for provenance and cleanup policy; Git CLI for conditional ref deletion.
- `RepoViewModel` owns UI progress and error feedback, not tag-policy rules.

## Affected Areas

- Repository toolbar Sync, tag list, `GitService`, `RepoViewModel`, new helper and tests.

## Test Scope

- Unit tests: tag provenance rules and temporary-repo Sync scenarios.
- Manual verification: Sync and tag context menu in a disposable repository.
- Failure modes / edge cases: local-only tags, moved tags, deleted remote tags, and unavailable remote.
- Known coverage blockers: no end-to-end remote UI automation.
- Real temporary Git repos: local-only tag/branch retained; tag first fetched then removed remotely is pruned; locally moved tag retained; missing remote skips cleanup.
- Pure parser/storage boundary tests if needed.
- Manual Sync and tag-menu check in a disposable repo.

## Design Records

- RFC required? Yes; a persisted helper and Sync transaction cross layers.
- ADR required? No; the policy is scoped to remote tag cleanup.
- RFC required: a new persisted service and cross-layer Sync transaction. See `docs/rfcs/2026-11-06-safe-remote-ref-sync.md`.
- ADR not required: this does not establish a general repository-wide Git architecture.

## Completion Criteria

- All four scenarios pass; no automatic `--prune-tags` or indiscriminate local-tag deletion remains.
- Cleanup never runs after an incomplete remote observation.

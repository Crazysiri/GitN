# Feature Intake: bounded inspector model cache

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Keep bounded Monaco models by source identity and document revision.

## Behavior Change

- Keep bounded Monaco models by source identity and document revision.

## Non-Goals

- Persistent drafts, unbounded diff cache and eliminating Git reads.

## Change Boundary

- In scope: Monaco model lifecycle, identity payload and eviction.
- Out of scope: Persistent drafts, unbounded diff cache and eliminating Git reads.
- Protected hotspots reviewed: RepoViewModel and GitService only retain their existing orchestration or service roles.

## Ownership

- Primary owner layer: Monaco host owns models; Swift supplies opaque source identity.
- Why this layer is the right owner: The named layers already own the relevant state or rendering boundary.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not gain unrelated policy or UI rendering.

## Test Scope

- Unit tests: Revisits, stale content, eviction, source isolation and disposal.
- Manual verification: Switch repeatedly between large files and verify focus and undo.
- Failure modes / edge cases: Stale snapshots reset undo; active model remains usable.
- Known coverage blockers: Native UI frame-time and interaction behavior are not fully automated.

## Design Records

- RFC required? Yes; identity crosses Swift and WebView.
- ADR required? No; bounded optimization only.

## Completion Criteria

- Inactive cache stays within eight models and four million UTF-16 units.

## Earlier Intake Detail

### Change, boundary and owner

The Monaco host retains up to eight recently used models with a total text budget of 4 million UTF-16 units (roughly 8 MB of text, excluding Monaco overhead). The active model is retained even if larger than the budget. Switching files restores a model's undo history only when its document identity and authoritative content still match. Changed snapshots replace contents and reset undo. Source identity includes repository, context and selected commit/stash. Diff and preview use separate models. UI state stays in the host; Swift sends an opaque identity and retains no cache logic.

Non-goals: persistent drafts, eliminating Git reads, caching unbounded diff results or replacing the editor. Tests cover revisits, stale content, eviction, source isolation and disposal. RFC required because the payload crosses Swift and WebView.

# RFC: Safe Remote Ref Sync

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Preserve local-only refs while pruning remote-tracking branches and remote tags whose provenance is known.

## Scope

- In: Sync fetch options, persisted remote-tag provenance, fail-closed cleanup, integration tests.
- Out: retroactive classification of existing tags, manual deletion, generic operation scheduling.

## Problem

Git tags share `refs/tags` between local and remote use; unlike `refs/remotes`, their names alone do not record ownership. `git fetch --prune --prune-tags` and comparing all local tag names against `ls-remote` both delete local-only tags. A failed `ls-remote` can make the remote set appear empty.

## Proposed Design

1. Before Sync, record local tag ref OIDs. Fetch with `--prune --tags --all`, omitting `--prune-tags`. Git prunes remote-tracking branches; tags remain intact.
2. Only after successful fetch, query *all* configured remotes with `ls-remote --tags --refs`. If any query fails, do not delete or rewrite the provenance snapshot.
3. Persist per-repository, per-remote-identity tag-name/OID maps only for tags absent locally before fetch and acquired during it, or previously tracked tags still matching the remote and local OID. The identity includes a digest of remote name and URL so a repointed remote cannot inherit deletion authority.
4. For a tracked tag absent from every configured remote, delete its local ref only when its OID still matches the previously recorded OID. Use one `git update-ref --stdin` transaction with expected OIDs so external mutation aborts the transaction. Save the new snapshot only after successful cleanup.
5. Existing tags at initial observation are unclassified and remain local even if their remote counterpart later disappears. This conservative rule is intentional because their origin is unknowable from standard Git refs.

## Layer Ownership

- `RemoteTagPruner`: provenance, remote observation, eligibility, persistence.
- `GitService`: existing fetch execution with safe arguments.
- `RepoViewModel`: sequencing and user-visible result.

## Alternatives Considered

- `--prune-tags`: rejected because it deletes local-only tags; independently reproduced in a local Git fixture.
- Delete all tags absent from `ls-remote`: rejected because name absence proves no local ownership and remote-query failure can masquerade as emptiness.
- Custom refs under `refs/gitn/*`: durable but pollutes repository state and can be mirrored/pushed by other tools.

## Test Plan

Use local temporary remotes with real fetches to cover ownership acquisition, deletion, local-only preservation, changed-OID preservation, and failed remote observation.

## Migration / Rollout

Start with an empty ownership snapshot for every repo. Existing local tags are preserved. Tag cleanup becomes effective for tags first fetched by this version.

## Risks

- Ref mutation between observation and deletion: expected-OID transaction aborts.
- Remote identity change or incomplete query: skip deletion.
- A user recreating a previously tracked tag with the same name and identical OID is indistinguishable from the fetched ref; this rare case can still be pruned after remote deletion.

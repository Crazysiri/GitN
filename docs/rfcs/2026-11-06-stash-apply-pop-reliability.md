# RFC: Stash Apply and Pop Reliability

- Status: Implemented; user's live stash not mutated
- Owner: GitN
- Date: 2026-11-06

## Decision

Use the selected stash OID for git stash apply without --index. Git's default apply permits unrelated staged changes, whereas libgit2's apply rejects a dirty index even without reinstating the saved index. The current unconditional GIT_STASH_APPLY_REINSTATE_INDEX also rejects otherwise applicable stashes when their saved index cannot be reinstated. Pop first applies the selected OID, then resolves the same OID's current reflog position and drops it. Do not retry a failed Pop after it may have made partial changes.

## Failure behavior and tests

Apply first, drop only on success. Preserve the stash after a conflict and refresh the UI to reveal any partial untracked restore. Show the original error message in a toast; if the drop fails after apply, state that the stash was applied but not removed. Cover unrelated staged changes, failed Pop, and OID/index movement in temporary repositories.

The Stash-filtered Swift tests passed 28 tests with no failures. The user's repository was not used for Apply/Pop validation, so its exact prior failure remains a live-repository verification boundary.

# RFC: Pull Auto-Stash Restore Safety

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Decision

On fallback pull failure, attempt checkout of the original branch, then read the current branch through GitService. Pop the saved OID only when that branch matches. If checkout or verification fails, keep the stash and show its OID in the error. If Pop fails, preserve Git's remaining stash and report the failure. Never silently discard recovery errors.

## Tests

Cover the safe branch-verification predicate and a failed target pull with a dirty tree in a temporary repository. Manually verify recovery failure messaging.

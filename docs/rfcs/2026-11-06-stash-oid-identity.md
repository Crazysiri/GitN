# RFC: Stable Stash OIDs

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Design

Capture the OID supplied by libgit2 stash enumeration and return the OID from stash save. Use that OID as StashInfo identity and as the immutable revision for all selected-stash reads. Retain stash@{n} only as a display label.

For apply, pop, and drop, resolve the selected OID against the current stash list inside GitService immediately before the synchronous libgit2 operation. Because there is no await between resolution and mutation, actor reentrancy cannot retarget the operation. Reject a missing OID; never fall back to index zero.

AutoStashRunner passes the newly created OID from push to its pop callback. The pull fallback similarly holds the saved OID through success and recovery.

## Boundaries and risk

- Existing index-based service APIs remain for an explicit newest-stash toolbar command and existing callers, but selected-entry actions use OID APIs.
- This does not solve concurrent writes across awaits; the repository write queue remains a separate follow-up.
- A stash that disappears before mutation yields an error rather than acting on a replacement entry.

## Tests

Use real repositories to shift stash indices before apply/drop and verify the original OID is targeted; verify a removed OID is rejected. Test AutoStashRunner callback identity independently.

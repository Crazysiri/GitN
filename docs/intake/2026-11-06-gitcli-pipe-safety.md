# Feature Intake: Git CLI Pipe Safety

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Summary

Buffered Git commands must drain stdout and stderr concurrently while supplying stdin. A command producing more than one pipe buffer of diagnostics must finish or fail rather than hang. Callers that need a blob's original bytes must be able to request Data without a UTF-8 round trip.

## Behavior Change

- Large simultaneous stdout, stderr, and stdin no longer deadlock the buffered runner.
- Blob callers can retain original bytes; string callers receive an explicit decoding error for non-UTF-8 data rather than a false empty result.

## Non-Goals

- No change to Git operation semantics, streaming UI, command logging, or global timeout policy.
- No implicit decoding of non-UTF-8 bytes.

## Change Boundary

- In scope: GitCLI process setup, buffered capture, original-byte output, and tests.
- Out of scope: operation semantics, streaming UI, logging, and global timeout policy.
- Protected hotspots reviewed: GitService and RepoViewModel retain their existing orchestration roles.

## Ownership

- Primary owner layer: GitCLI process runner.
- Why this layer is the right owner: it owns subprocess pipes and decoding boundaries.
- Which larger type is intentionally not taking more responsibility: GitService does not manage pipe concurrency.

## Test Scope

- Unit tests: large stdout/stderr/stdin stress, exact binary output, and nonzero exit diagnostics.
- Manual verification: run affected Git commands from a disposable repository.
- Failure modes / edge cases: full stderr pipe, binary bytes, large stdin, and failed commands.
- Known coverage blockers: no real remote command timing benchmark.

## Design Records

- RFC required? Yes; the central CLI execution boundary changes.
- ADR required? No; the shared runner remains within GitCLI.

## Completion Criteria

- Stress tests pass and existing GitCLI callers compile.

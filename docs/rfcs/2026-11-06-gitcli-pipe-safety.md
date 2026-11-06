# RFC: Git CLI Pipe Safety

- Status: Implementing
- Owner: GitN
- Date: 2026-11-06

## Design

The current buffered runner reads stdout to EOF, then stderr, after writing all stdin. A child can block on a full stderr pipe while the parent waits on stdout; the same can happen while the parent is writing stdin. Replace the duplicated buffered process setup with one capture primitive that starts stdout and stderr readers and the optional stdin writer independently before waiting for termination. Each stream is read to EOF, then the process exit code and raw bytes are returned. Throwing wrappers convert non-zero exit into the existing GitError behavior. A raw-output method exposes exact stdout bytes for blob readers.

## Scope and failure behavior

- In scope: GitCLI.capture, execute, raw stdout accessor, tests with real local Git aliases.
- Out of scope: streaming process executor refactor and arbitrary command timeouts.
- Failure to launch throws. Non-zero exit remains a capture result; run and output throw. Stdin writes that fail because the child already exited do not mask the Git exit code.

## Risks and test plan

Unbounded capture can consume memory on enormous output; existing behavior already buffered entire streams, so output caps are a later change. Tests exercise full pipes and byte-preserving output. Future consolidation with the streaming executor should keep one cancellation model.

# RFC: External Sessions First

- Status: Accepted for implementation
- Owner: GitN
- Date: 2026-11-08

## Summary

Users work in external Codex/Kiro sessions, then inspect and associate them in GitN. Sessions become the default workbench page; New Task stays optional. See ../intake/2026-11-08-external-agent-sessions.md and ../adr/2026-11-08-independent-workbench-boundary.md.

## Boundary and ownership

WorkbenchSession stores an internal UUID plus provider, local source namespace, external conversation ID, external title, last-observed directory and timestamps. Directory observations carry source, canonical Worktree/common-gitdir, first/last observed times; sessions need not have one. Explicit task membership uses a separate join record. Never deduplicate by cwd/title or merge tasks because they share files. The focused resolver validates a reported cwd using Git and supports nested directories; a missing directory remains unresolved. It does not infer the target of shell commands or newly created Worktrees.

WorkbenchTaskStore remains the only metadata writer. Document version 2 adds sessions, task joins and consumed-event IDs; decode old task records with empty new collections and preserve a version-1 backup before the first version-2 save. Candidate documents are written atomically. Relay processes only create unique minimized JSON inbox files, never write the metadata document. No global agent config is changed automatically.

## Discovery and ingestion

- Explicit Discover Codex launches the installed local CLI's stdio app-server, initializes, pages thread/list, parses only IDs, name, cwd and timestamps, then terminates the child. Do not request turns, resume, execute tools, set titles, or retain preview/transcript fields. Timeout/cancellation must stop the child. Missing executable and errors are visible.
- Codex/Kiro hook relay reads one bounded JSON object from stdin, keeps session_id/cwd/hook_event_name and safe timestamps only, and writes an atomic uniquely named envelope under Application Support/GitN/Workbench/inbox. It emits no stdout and fails open, so reporting failures do not block the Agent. Raw tool arguments, prompts, transcripts and tokens are excluded.
- Project setup is an explicit UI action: install a copy of the helper in GitN Application Support; merge only GitN-owned Codex hooks or add a dedicated Kiro hooks file, preserving unrelated settings. Display the exact target paths and current integration state. Removal deletes only owned definitions. Codex trust remains the user's /hooks action; do not bypass it. Kiro schema is the current v1 hooks array for IDE/CLI V3; older CLI requires upgrade.
- Refresh imports valid inbox events idempotently and resolves directories. Event arrival order cannot regress newer titles/locations. Hooks without title do not erase known external names. Retain source timestamps separately from received timestamps.

## UI and grouping

Sessions list distinguishes provider, title/fallback, associated directories, last observed event, and membership. “Unassociated” is a valid state. Scope to this repository's known directory associations, with an explicit toggle to include globally unassociated sessions. “Associate Worktree” is explicit and does not erase reported-directory history. “Create Task from Session” can work without a directory; if present, capture current HEAD as an association-time baseline. “Add to Task” is many-to-many, preserves edited task titles and existing baselines, and can include both providers. Worktree cards list observed sessions rather than claiming exclusive ownership. Current change inspection is a comparison from association time, not a reconstructed starting snapshot.

## Compatibility and tests

Versioned migration, duplicate/resumed IDs, two sessions sharing one directory, provider ID collisions, name arrival/rename, out-of-order events, missing cwd, nested/symlink paths, multiple directories, optional task membership, removed directories, invalid files, helper failure, config ownership preservation, app-server pagination/errors/cancellation and existing workbench tests are required. Native preview verifies routing and default page. Kiro is not installed on PATH here; event-fixture verification is not live-runtime certification.

## Official evidence

Fetched in the preceding discussion: https://developers.openai.com/codex/app-server/ (thread/list metadata and nullable thread.name), https://developers.openai.com/codex/hooks/ (session_id/cwd), https://kiro.dev/docs/hooks/ and https://kiro.dev/docs/hooks/types/ (v1 hooks, session_id/cwd, IDE/CLI differences). Installed Codex CLI 0.164.0 generates schemas used to validate this read-only client. External IDE visibility and Kiro automatic title discovery remain capability-dependent; do not claim a global subscription or guaranteed title feed.

## Implementation validation

- 2026-11-08: 34 targeted tests passed across external sessions, workbench, Worktree service, mutation coordination and repository watching, including the opt-in installed Codex discovery test. Swift build, diff whitespace check and repository harness passed.
- Installed Codex 0.164.0 returned 26 local threads, with 24 titles and 26 working directories. Native preview discovery displayed six matching repository sessions independently, sharing the same directory without merging their identities. No agent turn was started or resumed.
- Native preview verified the Sessions default page and the Codex/Kiro setup sheet. Hooks remain unconfigured in the real repository; setup was tested using temporary configurations. The packaged relay is included in GitN-SessionsPreview2.app.
- A stale task referring to a removed Worktree no longer blocks the Sessions page with a changes-loading modal. Task changes are loaded on the Tasks page and failures are displayed inline.
- Kiro configuration generation, minimized event ingestion and identity handling pass fixture tests. A live Kiro runtime and automatic Kiro titles remain unverified because Kiro CLI is unavailable in this environment; release acceptance still requires that validation.

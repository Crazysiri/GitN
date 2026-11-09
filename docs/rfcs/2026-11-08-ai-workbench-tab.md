# RFC: Independent AI Workbench Tab

- Status: Accepted for initial core
- Owner: GitN
- Date: 2026-11-08

## Summary

Introduce a separate workbench tab without replacing the established Git repository screen. Feature intake: ../intake/2026-11-08-ai-workbench-tab.md.

## Scope

- In scope: typed tab routing, compatible persistence, independent workbench screen and task state, explicit Worktree associations, real Git change inspection, opening target directories in Git tabs.
- Out of scope by default: Agent hook installation, Bridge, automated review, snapshot restoration, and semantic merge. Codex and Kiro are required release targets, to be integrated after this initial functional core.

## Problem

The proposed task-centric interface is experimental. Replacing the established three-pane Git interface would couple product validation to regressions in mature workflows. Existing AppModel deduplicates tabs by path and persists only SavedRepo records, so a second tab kind requires explicit identity and restoration rules.

## Proposed Design

1. Add a typed tab descriptor for Git and workbench surfaces. Keep existing Git tab path semantics. Identify tabs by kind plus canonical opening path so identical paths can coexist across kinds.
2. Preserve the current plus-to-new-tab flow; offer separate “Open Git Repository” and “New Workbench” actions there.
3. ContentView routes each tab to its appropriate container and retains loaded-tab behavior. Workbench owns its navigation and selection independently.
4. Start with one repository per workbench. It can associate tasks with multiple linked Worktrees. A separate repository clone remains a separate project unless a future explicit association is introduced.
5. Keep task identity independent of view/tab identity. Use an internal project ID and repository locator; common gitdir can locate linked Worktrees but paths are not immutable identity. Missing or moved directories require explicit recovery rather than silently creating a duplicate project.
6. Proposed workbench areas are overview, tasks, and Worktrees; show Review only when backed by usable behavior. Task detail can own changes, verification, and activity as capabilities arrive. No invented progress or mock health claims in the shipped functional UI.
7. Reuse WorktreeService and Git read operations. Task and association storage stays outside repository metadata, behind a testable interface; initial storage is a versioned, atomically replaced JSON document in Application Support/GitN, managed by one shared actor. Each transaction loads/validates before use, persists a candidate before publishing, and reports errors without overwriting invalid data. Projects have UUIDs and a canonical common-gitdir locator; tasks hold multiple Worktree paths and starting commit IDs. A future SQLite migration must preserve IDs and retain the old document until verified.
8. “Open in Git” routes the selected Worktree to the existing Git tab path and activates an existing matching Git tab when present.
9. Monitoring for all managed Worktrees is a separate follow-up boundary. The existing Git container stops watching inactive tabs; do not claim background tracking until a shared monitor exists. Initial workbench can refresh on activation and explicit request, with visible freshness.

## Layer Ownership

- AppModel: tab lifecycle and routing.
- Tab descriptor/codec: type-aware identity, persistence compatibility.
- Workbench model: task screen orchestration and selection.
- Task store: durable task and association operations.
- Existing Git/Worktree services: code state and Git operations.
- RepoViewModel: existing Git UI only, no new task engine.

## Alternatives Considered

- Replace the Git screen: rejected because it couples an experimental workflow to the established UI.
- Embed a workbench drawer in the Git screen: rejected because task navigation and review need sufficient space and independent state.
- Open a tab for every task: rejected because Task and Worktree are not one-to-one.

## Test Plan

- Legacy saved tabs restore as Git tabs; mixed kinds round-trip and reorder/close correctly.
- Same path can have one tab of each kind; repeated opens select the matching kind.
- Existing Git deduplication, repository opening, and recent repositories keep their meaning.
- Task records survive closing/reopening tabs; failed persistence is surfaced.
- Deleted Worktrees remain recoverable associations and do not silently delete tasks.
- Git tab regressions: commit pagination, WIP selection, diff, conflict resolver, and terminal lifecycle.
- Workbench manual QA: compact window, system light/dark, keyboard navigation, long names, empty and error states.

## Migration / Rollout

- Workbench is opt-in. Existing sessions continue to open Git tabs.
- Store mixed tab descriptors under a new versioned key; read the legacy key as fallback and retain legacy data during initial rollout.
- Keep recent Git repositories distinct from workbench task records.
- Removing the workbench feature must not require changing Git repository contents.

## Risks

- UI isolation does not isolate working-directory writes. Show target paths and existing changes; offer dedicated Worktrees for task creation.
- Reusing RepoContainerView would inherit close-time terminal cleanup; workbench must not casually adopt ownership of Agent processes.
- Multiple workbenches for linked directories require shared task storage rather than per-tab duplicate databases.
- User confirmed functional core and native styling. Codex/Kiro ownership in task records is an intended assignment only, not evidence of an active Session. Release readiness requires separate adapter validation.

## Initial Core Validation (2026-11-08)

- Swift build passed.
- 21 targeted tests passed across WorkbenchTests, WorktreeServiceTests, RepositoryMutationCoordinatorTests, and RepositoryFileWatcherTests.
- Native preview at build/GitN-WorkbenchPreview.app (within the GitN package): verified new-tab workbench entry, repository selection, empty task layout at the default compact window, task form defaulting to a dedicated Worktree, Codex/Kiro assignment selection, opening the same repository in a separate Git tab, and switching back.
- Native preview followed system light appearance. Dark appearance, populated task layout, large-repository performance, and full historical Git UI regression remain manual QA items before release.
- Computer-use timeout after closing the file chooser was resolved by rebinding the main window; sampled main thread was idle in the AppKit event loop.

## Release Gates After the Initial Core

- Codex and Kiro both require actual Session integration, documented supported versions/surfaces, lifecycle/duplicate/out-of-order event tests, and a verified install/uninstall workflow before claiming release support.
- Background monitoring, verification execution, Snapshot restoration, and AI Review remain separate capabilities; this core does not claim them.
- Before adding a Bridge or allowing concurrent application processes to write metadata, replace the process-local JSON writer with a cross-process transactional boundary and a tested migration.
- Change inspection compares the selected Worktree against its task association’s starting commit, including pre-existing modifications. It does not claim Agent attribution. Untracked paths are listed without automatically ingesting their contents.
- Initial core supports manual task stages, task creation with a dedicated new Worktree by default, association with existing Worktrees, explicit refresh, and safe removal via existing WorktreeService. No automatic test execution or Agent launch.

## Follow-up Product Direction: External Sessions First (2026-11-08)

The user described the primary workflow as creating sessions and Worktrees inside Codex/Kiro, then associating them in GitN. Retain manual New Task as an optional entry; do not require a task or Worktree choice before an external session starts. The initial core above remains implemented; the following is the next integration design, not shipped functionality.

### Identity and relationships

- Persist an external conversation identity scoped by provider, source installation/account namespace, and external conversation ID. Opening/resuming a conversation does not create a new logical conversation; separate runtime connections/activations can be recorded beneath it.
- Keep external title and user-owned task title separate, including provenance and observed timestamps. Neither title nor cwd is a session identity.
- Session–Worktree is an observed association with source, confidence, validity interval, and optional turn/event scope. Multiple Codex sessions, multiple Kiro sessions, and both providers can share a Worktree without being merged into one session or task.
- A session can use multiple Worktrees. Preserve prior associations instead of overwriting cwd or retrospectively moving all events.
- Task grouping is explicit: associate selected sessions/turn ranges and Worktrees. Shared directories alone must not automatically merge unrelated tasks.

### Discovery and deferred association

- Show discovered sessions (including unassociated sessions) and Git-native Worktrees before requiring task creation.
- Resolve reported cwd/tool working paths to a verified Git top-level directory; canonicalize paths and resolve common gitdir to identify linked Worktrees in the same project.
- Use explicit adapter-reported Worktree changes where available. A newly observed Worktree or file activity alone does not prove which session owns it.
- If an Agent creates a Worktree while its session cwd remains in the main checkout, keep the new directory as a candidate until an explicit signal or user confirmation identifies it. Never choose the latest Worktree as a silent default.
- On ambiguity, retain an unassociated/multiple-candidate state and offer a focused association action after evidence exists. There is no mandatory chooser each time the AI tool opens.
- Offer “Create Task from Session” and “Add to Existing Task”. Capture the comparison baseline at association time and label that timestamp; late discovery cannot reconstruct an uncommitted starting state or exact Agent attribution.

### Titles and verified integration evidence

Official pages fetched on 2026-11-08:

- Codex app-server: https://developers.openai.com/codex/app-server/ — thread/list and thread/read hydrate thread.name when set; thread/start may initially omit it; thread/name/updated is documented. Read without resuming where possible. Cross-client runtime visibility/subscription and shared-store access still need installed-version verification.
- Codex Hooks: https://developers.openai.com/codex/hooks/ — common input includes session_id, cwd, and transcript_path. Hooks are not a documented title field; transcript format is explicitly unstable.
- Kiro Hooks: https://kiro.dev/docs/hooks/types/ — documented event examples contain session_id and cwd; SessionStart availability depends on surface/harness.
- Kiro ACP: https://kiro.dev/docs/acp/ and https://kiro.dev/docs/cli/acp/ — negotiate running-server capabilities; a client-owned ACP process does not establish passive access to arbitrary IDE conversations. A stable externally readable title/list feed is not established by the pages reviewed.

Title preference: official external title if available; user-entered title; otherwise a clearly identified fallback such as provider plus short session ID. Optional prompt-derived suggestions require consent to access prompt content. An external rename updates the external display title but must not overwrite an edited GitN task title. Do not write back titles into the AI tools in the passive workflow.

### Required next intake/testing

Before implementing adapters/persistence migrations, create a separate intake and RFC with concrete versioned payload fixtures and storage migration. Test same-provider concurrent sessions in one Worktree, cross-provider sharing, session resume and rename, delayed titles, missing cwd, nested paths and symlinks, Worktree creation without cwd changes, conflicting candidates, session movement across Worktrees, late observation, duplicate/out-of-order events, unavailable integrations, and explicit task grouping. No application code was changed for this follow-up design.

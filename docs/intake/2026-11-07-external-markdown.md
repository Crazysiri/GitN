# Feature Intake: External Markdown Viewer

- Status: Implemented and verified
- Owner: App/document presentation layer
- Date: 2026-11-07

## Summary

Opening an external .md, .markdown, or .mdown file with GitN presents a standalone read-only Markdown window, including outside repositories. Register GitN as an optional Markdown viewer. Reopening a file focuses its existing window. Reading failures remain visible in the document window.

## Non-Goals

No editing/saving, default-app changes, repository discovery, document persistence, or directory browsing. Existing repository commands and tabs retain their behavior.

## Behavior Change

Local Markdown opens in a dedicated read-only window; repeated opens focus that window, and Launch Services lists GitN as an optional viewer.

## Change Boundary

- In scope: App launch/open-file handling, standalone Markdown windows, relative resource URLs and document type declarations in build.sh.
- Out of scope: Editing, default-app ownership, repository discovery and unrelated conflict work.
- Protected hotspots reviewed: RepoViewModel and GitService gain no document responsibilities.

## Ownership

- Primary owner layer: App/document presentation and a testable local file reader.
- Why this layer is the right owner: File-open events and native window lifetime belong to the app layer; validation/loading has no repository dependency.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService.


AppDelegate receives macOS open-file events; a focused document window controller owns file-window lifetime. A testable file reader validates/loads local UTF-8 Markdown off the main thread. The thin document view reuses MarkdownInspectorContentView and its rendering limits. GitN/build.sh owns Launch Services declarations. RepoViewModel, GitService, history, and in-progress conflict changes are outside scope.

## Test Scope

Automated coverage: extension matching, non-file URLs, directories, UTF-8 including BOM/Unicode, missing/invalid files, canonical identity, repeated opens and window cleanup where feasible. Run relevant Markdown tests and Swift build. Manual checks: Finder/open -a, cold/warm launch, multi-file open, read failures, close/reopen, normal repository launch, and system theme. Launch Services GUI verification may require approval to launch a preview bundle.

- Unit tests: Extension matching, local URLs, UTF-8/BOM/Unicode, missing/invalid files, directories and canonical identity.
- Manual verification: Existing cold/warm launch, multi-file opening, document focus and File > Open Repository preview acceptance is recorded below; Finder Open With and theme sweeps remain release checks.
- Failure modes / edge cases: Invalid encoding, non-files, duplicate URLs, closed windows and cold launch with multiple files.
- Known coverage blockers: Launch Services registration and native focus/appearance are verified in preview/manual flows rather than a headless unit test.

## Design Records

- RFC required? Yes, new app-level window controller and launch-event flow; see ../rfcs/2026-11-07-external-markdown.md.
- ADR required? No, localized use of existing AppKit window and Markdown renderer patterns, no repository-wide policy.

## Completion Criteria

External Markdown opens directly in its own preview without requiring Git state; duplicate opens focus one window; failures are readable; existing repository operations build unchanged; bundle metadata offers GitN in Open With without claiming default ownership.

## Open Questions

None. First version is a read-only viewer.

## Verification

- `swift test --filter 'ExternalMarkdown|Markdown'`: 36 tests passed.
- Final app compilation passed; build.sh shell syntax and generated Launch Services metadata checked.
- Native preview acceptance: external Markdown foreground on cold launch; two-file cold launch retains both windows; opening an existing document after revealing the repository scene restores document foreground. File > Open Repository still presents the directory chooser.
- Packaged review app: `GitN/build/GitN-MarkdownFocusPreview.app` (separate bundle identifier; installed GitN not replaced).
- Subsequent full-workspace security regression: 517 Swift tests, 5 git-lfs-dependent skips, zero failures. Dedicated light/dark visual sweeps remain release checks.

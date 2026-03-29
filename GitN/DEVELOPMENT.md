# Developing GitN

## What Lives Where

GitN has two very different layers in this repository:

- `GitN/Sources/GitN`: the app code you will modify most of the time
- `GitN/Sources/Clibgit2/libgit2`: vendored upstream source; treat it as third-party code unless you are intentionally changing libgit2 integration

Top-level app folders:

- `Sources/GitN/App`: app entry, window setup, global environment injection
- `Sources/GitN/Models`: app state, view models, shared UI palette, data models
- `Sources/GitN/Services`: git operations, hosted review APIs, file watching, graph/layout helpers, AI commit integration
- `Sources/GitN/Views`: all SwiftUI/AppKit UI, including the main three-pane repo screen
- `Sources/GitN/Resources/Monaco`: embedded Monaco host assets used by the file inspector

## App Entry And Global State

Startup path:

1. `GitNApp.swift` creates and injects `AppModel` and `ThemeManager`.
2. `ContentView.swift` owns the top chrome, tab strip, and New Tab screen.
3. Each opened repository gets one `RepoContainerView`.
4. Each `RepoContainerView` owns one `RepoViewModel`.

Important state owners:

- `AppModel`: multi-tab state, recent repos, open/clone/init flows, persistence of opened tabs
- `RepoViewModel`: almost all per-repo UI state and orchestration
- `GitService`: git/libgit2 and CLI bridge for repository operations
- `ThemeManager`: app-level theme preference, defaults to system
- `ChromePalette`: shared chrome colors for tab bar and repo toolbar

## Main Screens

The core repo screen is a three-pane layout in `RepoContainerView.swift`:

- Left: `SidebarView`
- Middle: `GraphView`
- Right: `DetailPanelView`

Other major screens:

- `NewTabView`: open/clone/recent repositories
- `SettingsView`: AI, Git tokens, editor settings, about
- `ConflictMergeView`: full-screen three-way conflict resolver
- `FileInspectorOverlayView` in `SourcePreviewView.swift`: Monaco-based file inspector, diff/history/preview modes
- `TerminalPanelView`: embedded terminal below the graph pane

## Primary Data Flow

Repository load path:

1. `RepoContainerView.task` calls `RepoViewModel.loadAll()`.
2. `RepoViewModel.loadAll()` pulls metadata in parallel from `GitService`.
3. `RepoViewModel` creates a `CommitWalker` and loads the first commit page.
4. `GraphView` renders commits through `CommitTableView -> CommitRowCellView`.
5. Selecting a commit or file drives `DetailPanelView` and, when needed, `FileInspectorOverlayView`.

Commit history notes:

- History is paginated, not eagerly loaded.
- Graph layout is view-driven and computed lazily.
- `commits` currently assumes real commits plus one optional uncommitted pseudo-entry.

## Key Shared Components

UI pieces worth reusing before creating new variants:

- `ChromePalette.swift`: top chrome colors; selected tab and repo toolbar should change together
- `HoverTooltip.swift`: shared hover tooltip behavior; prefer this over system tooltips for custom hover hints
- `MonacoInspectorView.swift`: file inspector bridge to Monaco
- `MarkdownPreviewView.swift`: markdown preview/editor surface
- `LineNumberTextView.swift`: AppKit text view with line numbers

Patterns already used across the app:

- `@Observable` models instead of ad-hoc environment objects
- `Task { await ... }` from view events, with heavy work pushed into services
- AppKit bridges for complex controls that SwiftUI does not handle well enough

## Service Boundaries

`GitService.swift` is the repository backend. It currently mixes:

- libgit2-backed reads and mutations
- shell-based git commands for operations that are simpler or more reliable via CLI
- patch application and file-content helpers
- conflict and reflog helpers

Hosted review support is split across:

- `CodeHosting.swift`: GitHub API types and service
- `GitLabService.swift`: GitLab API and GitLab-specific merge flow

Supporting services:

- `RepositoryFileWatcher.swift`: FSEvents watcher for `.git` and working tree changes
- `AICommitService.swift`: external CLI integration for commit message generation
- `GraphLayoutEngine.swift`: graph lane/layout work
- `TabCompletionEngine.swift`: terminal/editor completion support

## Code Hotspots

These files carry the most behavior and deserve extra caution when editing:

- `Models/RepoViewModel.swift`: repository orchestration and most UI state
- `Services/GitService.swift`: git backend, shell/libgit2 boundary
- `Views/Detail/DetailPanelView.swift`: large right-pane surface with many modes
- `Views/Graph/GraphView.swift`: commit table and context actions
- `Views/Sidebar/SidebarView.swift`: sidebar sections, sheets, context menus

Large-file risk in this codebase is real: changes in one concern can easily regress another because state, commands, and view logic are still concentrated.

## Current Design Debt To Keep In Mind

These are not blockers for every change, but they should influence refactors:

- `RepoViewModel` is acting as screen state, interaction coordinator, and feature store for many unrelated concerns.
- `GitService` has become a mixed abstraction: low-level git API, process runner, and workflow layer.
- GitHub and GitLab services duplicate remote URL parsing, request plumbing, and git CLI wrappers.
- Several views still encode styling and hover logic locally instead of leaning on shared chrome components.
- Theme usage is mixed: some surfaces use dynamic AppKit colors, others still branch on `isDark` and hard-coded RGB values.

## Safe Areas For Future Extraction

If you are refactoring, these seams are the most promising:

- Split `RepoViewModel` by feature: commit graph, detail panel, hosted review, conflict state, file inspector
- Extract a shared hosted review transport layer from `GitHubService` and `GitLabService`
- Normalize shared toolbar and chrome button styles
- Pull right-pane submodes out of `DetailPanelView`

## Development Checklist

Before shipping a change, verify at least the relevant parts of this list:

- Open multiple tabs and switch between them
- Load a large repository and scroll far enough to trigger commit pagination
- Select uncommitted changes, a normal commit, and a stash
- Open the file inspector in preview, diff, and history modes when applicable
- Exercise at least one sidebar mutation path if you changed branch/remote/tag behavior
- Confirm top chrome colors still keep navigation, selected tab, and repo toolbar visually distinct
- Confirm hover affordances still exist on top chrome controls and New Tab primary actions

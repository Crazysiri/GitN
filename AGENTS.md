# GitN Active Rules

Use this file as the execution-time rulebook. For repo orientation, read `GitN/DEVELOPMENT.md`. For mandatory pre-implementation intake, read `docs/ENGINEERING_WORKFLOW.md`. For durable policy, read `docs/ENGINEERING_GUIDELINES.md`.

## Pre-Implementation Gate

Before implementing a feature, refactor, or non-trivial bug fix, write down:

- what behavior is changing
- explicit non-goals
- the intended boundary
- the owning layer
- the test scope
- whether feature intake only, RFC, ADR, or both are required

Use `docs/ENGINEERING_WORKFLOW.md` and `docs/templates/feature-intake-template.md` for this step.

Do not start coding until those decisions are explicit.

## UI And Theme Guardrails

- For top chrome, keep three layers distinct:
  - Navigation/tab bar: darkest chrome color.
  - Selected tab: same color as the repo toolbar below, so they visually merge.
  - Repo toolbar: slightly lighter than the navigation/tab bar.
- When changing toolbar colors, always update the selected tab color in the same change.
- Prefer dynamic AppKit colors or a shared dynamic palette over hard-coded dark-only RGB values.
- Default theme behavior should follow the macOS system appearance unless the user explicitly chooses a fixed light/dark mode.
- Avoid adding new `isDark` branches for general SwiftUI surfaces when a system-driven color or dynamic palette can be used.
- Keep tab width content-driven first, then compress only when horizontal space is insufficient.
- Top chrome buttons and the primary action buttons on the New Tab page should have a visible hover state; keep that feedback consistent with the shared button/chrome language.
- For custom hover hints, use the shared `hoverTooltip(...)` / `HoverTooltipBubble` component in `GitN/Sources/GitN/Views/HoverTooltip.swift` instead of system tooltips so timing and styling stay consistent.

## Architecture Guardrails

- The middle history pane is driven by `CommitInfo -> RepoViewModel.commits -> CommitTableView -> CommitRowCellView`.
- Commit graph layout is computed lazily in the view layer via `LazyGraphProcessor`; avoid moving graph-specific transient state into `RepoViewModel` unless necessary.
- Commit loading is pull-based and paginated through `CommitWalker.nextBatch(count:)`, not an eager full-history load. Features tied to commit rows must tolerate partially loaded history.
- `RepoViewModel.loadAll()` loads repo metadata first, then creates a `CommitWalker`, loads the first commit page, and appends an uncommitted/WIP pseudo-entry at the top when needed.
- The graph table supports append-style updates; preserving existing row identity/order allows incremental graph extension instead of full graph resets.
- The current graph row model assumes rows represent real commits plus the single uncommitted pseudo-entry. Do not mix unrelated event rows directly into `commits` without reworking selection, pagination, diff loading, and graph layout assumptions.

## Protected Hotspots

Before adding logic to these areas, stop and justify why extraction is not the better default:

- `RepoViewModel`: do not add new provider-specific hosted review, authentication, remote parsing, or API request logic here. Keep it focused on UI state and orchestration.
- `GitService`: do not keep expanding it with unrelated hosted review, code hosting, or general network/auth responsibilities. Prefer focused helpers and services.
- GitHub/GitLab integration: prefer shared abstractions for remote parsing, git CLI runner behavior, and HTTP request plumbing instead of duplicating provider-specific branches.

## Testing And Documentation Obligations

- New code should ship with tests by default. If a change affects non-UI logic, add or update automated tests in the same change unless there is a concrete blocker.
- Treat ViewModel and service-layer logic as testable code. New behavior in these layers should be exercisable without SwiftUI views.
- Keep SwiftUI views thin where practical. If UI behavior is hard to test directly, move the underlying logic to a testable boundary.
- Write an RFC before implementing cross-cutting changes, new services/coordinators, or non-trivial additions to `RepoViewModel` or `GitService`.
- Write an ADR for long-lived architecture decisions and repository-wide policy changes.
- In PRs, explain why new logic lives in its chosen layer and what part of the change is directly unit-testable.

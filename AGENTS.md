# GitX UI Rules

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

# GitX Architecture Notes

- The middle history pane is driven by `CommitInfo -> RepoViewModel.commits -> CommitTableView -> CommitRowCellView`.
- Commit graph layout is computed lazily in the view layer via `LazyGraphProcessor`; avoid moving graph-specific transient state into `RepoViewModel` unless necessary.
- Commit loading is pull-based and paginated through `CommitWalker.nextBatch(count:)`, not an eager full-history load. Features tied to commit rows must tolerate partially loaded history.
- `RepoViewModel.loadAll()` loads repo metadata first, then creates a `CommitWalker`, loads the first commit page, and appends an uncommitted/WIP pseudo-entry at the top when needed.
- The graph table supports append-style updates; preserving existing row identity/order allows incremental graph extension instead of full graph resets.
- The current graph row model assumes rows represent real commits plus the single uncommitted pseudo-entry. Do not mix unrelated event rows directly into `commits` without reworking selection, pagination, diff loading, and graph layout assumptions.

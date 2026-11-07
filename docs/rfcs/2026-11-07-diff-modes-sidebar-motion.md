# RFC: Diff display modes and selection feedback

- Date: 2026-11-07
- Status: Implemented and validated

## Design

The file inspector owns an AppStorage display preference (inline/hunk/split), passed as an optional/defaulted host payload field. This is presentation state, so neither RepoViewModel nor GitService owns it. Include display mode in local-edit echo comparison so a preference change cannot be swallowed as an edit echo.

Inline retains the existing asynchronous diff renderer and Git hunk controls. Hunk uses Monaco DiffEditor in inline mode with independent range headers, three context lines and explicit hidden areas outside the blocks (see the Kraken revision below). Split uses the same Monaco DiffEditor in side-by-side mode with original read-only and modified following the existing editability permission. Monaco owns aligned scroll and diff computation. Git hunk actions use the existing patch payload and are exposed separately from Monaco's computed changes, never inferred from Monaco row indices. Split has labeled old/new sides, change navigation, and a Git hunk action strip. Native diff computation has a time budget and does not collapse to inline at narrow widths.

Switching layouts captures view state and recreates the rendering shell with cached models. All editors are disposed on exit; original models are protected from cache eviction while active. Editing forwards the modified model only and disables stale Git action controls until refreshed by Swift. Preview/history/conflict retain their current behavior.

Worktree rows reuse SidebarBranchRow: one line, matching padding/fonts/hover with path in the shared tooltip and existing context menus. Current, locked and prunable states remain visible.

Graph feedback animates only the selected background using a backing layer. Reused cells reset instead of animating another commit's selection; graph geometry, row order, and pagination remain unchanged. Sidebar row hover/selection animates only the row fill. Reduce Motion disables both.

## Validation / Risks

Node host tests exercise mode switching, hunk section layout/lifecycle and action mapping. Swift bridge tests exercise local edit echoes across display modes. WebKit smoke/build validate DiffEditor integration. Visually inspect narrow widths, light/dark, deleted-only files, stage/unstage/discard, unsaved edits across layouts, and fast graph selection. Monaco-computed hunks can differ from Git patch hunks; action UI explicitly uses Git controls and never computed indices.

## Build compatibility discovered during integration

The pinned Webpack 5.99.0 skips rewriting imported bindings in Monaco's hoisted `toLineRangeMappings` helper after a return statement. Native diff worker results then fail on the page with `DetailedLineRangeMapping` undefined; Inline never exercised that path. Pin Webpack 5.99.9, whose parser continues visiting hoisted function declarations after termination. Keep Monaco at 0.52.0. The production WebKit smoke exercises actual native diff results to catch recurrence; disabling innerGraph pruning alone does not fix the parser issue.

## Revision: Kraken hunk sections (user confirmed 2026-11-07)

Supersedes the initial native `hideUnchangedRegions` interpretation of Hunk. Source in `/private/tmp/gitkraken-static-analysis/render.bundle.js` was re-examined as inert text. Factory 89526 at character 11790939 builds independent hunk headers with `@@` ranges, hunk actions, paired view zones, and explicit `setHiddenAreas` outside the hunks. Factory 22619 at character 2924196 constructs three-line context ranges and merges nearby changes. This shows all hunks in one scrollable document, rather than a one-hunk pager or native folding UI. Factory 43659 at character 5697301 wires Hunk/Inline/Split toolbar modes.

Implementation: Keep full native original/modified models, disable built-in unchanged folding, calculate display hunks in a pure helper from Monaco changes, hide the complement, and add aligned per-hunk header zones. Group only changes whose context regions overlap/touch. Header actions use the existing Git controls matched to changed line intervals; never use Monaco's ordinal as the Git hunk index. A display block may contain multiple Git hunks, which retain separate action identities. All display zones/hidden ranges disappear with native editor disposal. Editing clears stale Git controls and recomputes display ranges through Monaco's existing diff-update event.

Tests: Pure layout/association boundary tests; host lifecycle, metadata and header action tests; real WebKit verifies multiple headers and no native fold widgets, insertion/deletion, switching and content preservation. No change to Swift payload or Git mutation orchestration is needed.

REA static analysis input: `/private/tmp/gitkraken-hunk-analysis` (wrapped inert factories); complete evidence `/private/tmp/gitkraken-hunk-rea-evidence-20261107-v2.json`. Static evidence does not claim runtime UI execution or complete application coverage.

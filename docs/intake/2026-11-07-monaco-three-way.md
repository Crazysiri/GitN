# Monaco structural three-way merge

- Status: Implemented and validated
- Owner: GitN
- Date: 2026-11-07

## Summary
Replace the native, manually synchronized conflict editors with three Monaco editors in one WebView. Replace the production zdiff3 marker parsing / content-search reconstruction with line-array diff3 using the O(NP) two-way edit script and overlapping ancestor hunk clustering observed in Kraken. Identical edits auto-merge; adjacent ancestor edits cluster as in the reference. Carry exact source coordinates into the conflict model. Support ordered line and block selection, manual output, navigation, undo and reset.

For modify/delete conflicts with one missing index stage, present explicit keep-modified, keep-deleted, and keep-ancestor choices. A deletion removes the path and stages its absence; a present stage is checked out through Git so file mode and filters remain Git-owned. Never reinterpret a missing stage as an empty text file.

## Non-Goals
Do not replace Git index reading, repository mutation serialization, save snapshot protection, encoding handling, fallback handling, or general inspector behavior. Do not copy Kraken application code/assets. Preserve GitN's explicit unresolved/empty/base resolution safety rather than reproduce ambiguous reference save policy.

## Behavior Change

Conflict editing uses three persistent Monaco panes, structural merge coordinates, ordered source-line choices and explicit modify/delete resolution.

## Change Boundary

- In scope: Structural diff3 computation, conflict document state, Monaco transport/rendering and index-stage conflict resolution.
- Out of scope: Hosted review, graph/history loading, general inspector behavior and replacement of Git's index/merge machinery.
- Protected hotspots reviewed: RepoViewModel orchestrates choices; GitService retains existing snapshot/index mutation ownership without gaining rendering or provider logic.

## Ownership

- Primary owner layer: Pure StructuralDiff3, ConflictEditorDocument and the Monaco view host.
- Why this layer is the right owner: Algorithms and selection state are independently testable, while editor geometry belongs to the web view.
- Which larger type is intentionally not taking more responsibility: RepoViewModel and GitService do not own diff3 algorithms or scroll state.

Focused diff3 helper owns pure merge computation; ConflictEditorDocument owns source selection/output state; Monaco host owns rendering, block geometry and animation-frame scroll mapping. SwiftUI routes actions. RepoViewModel only routes conflict choices; GitService owns index-stage checkout/deletion and existing save guards. No graph/history/hosting changes.

## Test Scope
Pure algorithm fixtures and differential comparison against locally extracted reference modules (research only); exact repeated-line coordinates, empty and insertion/deletion cases, literal markers, false conflicts, adjacent edits, Unicode/newline preservation. Model line order, toggling, disjoint manual edits, undo and existing save gates. Modify/delete integration tests cover both missing-side directions, delete versus checkout of a stage, executable and symbolic-link modes, binary fallback and stale snapshots. JS block mapping edge cases. Real WKWebView integration: three live Monaco models, metadata reuse, selection/edit/undo, unequal and empty block scrolling, light/dark and disposal. Swift focused tests and build.

- Unit tests: Structural coordinates, repeated/empty/adjacent edits, ordered line/block choices, manual edits, undo and snapshot guards.
- Manual verification: Existing preview checks cover compact panes, source checkboxes and output editing; visual appearance sweeps remain manual.
- Failure modes / edge cases: Missing index stages, executable/symlink modes, binary fallback, stale snapshots, zero-line sides, EOF and asynchronous edit echoes.
- Known coverage blockers: No automated screenshot comparison; native WebKit smoke verifies editor runtime, geometry and event routing.

## Design Records
- RFC required? Yes, cross-layer editor migration; see ../rfcs/2026-11-07-monaco-three-way.md.
- ADR required? Yes, durable algorithm/editor boundary; see ../adr/2026-11-07-structural-three-way.md.

## Completion Criteria
Production conflict loading uses structural diff3, with no marker re-identification. Live conflict UI uses Monaco only; output and selection remain coherent across manual edits and undo. Focused regression tests and WebKit smoke pass. Document any remaining UI validation limits.

## Consolidated Validation — 2026-11-07

- Full workspace Swift suite: 517 tests, 5 git-lfs-dependent skips, zero failures; includes structural merge, conflict mutations, external Markdown and security coverage.
- Monaco frontend: 35 tests passed; production build and standard native WebKit smoke passed with upgraded dependencies.
- Conflict native WebKit smoke passed: line/block actions, undo/redo, source switching and editing; zero script errors.
- Repository intake harness and git diff --check passed after required intake fields were completed.

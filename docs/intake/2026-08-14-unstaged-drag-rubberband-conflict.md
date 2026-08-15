
# Feature Intake

- Status: Implemented
- Owner: (unassigned)
- Date: 2026-08-14

## Summary

Two related interaction problems in the Detail panel staged/unstaged file
lists:

1. **(Fixed in prior iteration)** A gesture-priority conflict where a SwiftUI
   rubber-band (marquee) `LongPressGesture + DragGesture` attached to the
   whole unstaged list competed with each row's `.draggable`, causing
   drag-to-move to intermittently fail to start. Resolved by removing the
   row-overlapping SwiftUI marquee gesture and relying solely on the
   blank-area `BlankSelectionNSView`.

2. **(This iteration)** Two follow-ups:
   - Dragging a row still requires a brief press-and-hold before the drag
     starts, because SwiftUI's `.draggable()` on macOS internally waits on a
     long-press-style recognizer before beginning the drag session. Users
     want Finder-like behavior: press + small move = immediate drag.
   - The list rows are edge-to-edge with no spacing, so marquee selection can
     only start in the blank area below the last row, unlike Finder where the
     gaps around items are themselves valid marquee start regions.

## Behavior Change

- Replace SwiftUI `.draggable(payload)` on file rows with a custom AppKit drag
  source (`ImmediateDragSourceView`, an `NSViewRepresentable` wrapping an
  `NSView`) that begins an `NSDraggingSession` as soon as the pointer moves
  past a small threshold after mouseDown — no hold required. A mouseUp without
  crossing the threshold is treated as a click and forwarded to the existing
  selection logic (⌘/Shift aware).
- Add row spacing: 2px vertical gap between rows and 4px horizontal inset, so
  there are real blank pixels between/around rows.
- Marquee (rubber-band) selection continues to be driven by the AppKit
  blank-area hit view; with the new spacing, the inter-row gaps and bottom
  blank area are valid marquee start regions. Rows themselves never start a
  marquee (press on a row = click or immediate drag).
- ⌘/Shift multi-select behavior is preserved.

## Non-Goals

- Not adding modifier-key marquee-from-row.
- Not changing the drop side (`onDrop` / `handleDrop`) or the payload string
  format (`StageFileDragPayload`), so existing drop handling and its unit
  tests keep working unchanged.
- Not changing staged-vs-unstaged semantics or the ViewModel selection API.

## Change Boundary

- In scope: `DetailPanelView.swift`
  - new `ImmediateDragSourceView` (NSViewRepresentable) + backing NSView drag
    source
  - `StagingFileRow` drag wiring (replace `.draggable` modifier usage)
  - row spacing / inset in the staged & unstaged lists
  - marquee blank-area coverage to include inter-row gaps
- Out of scope: `RepoViewModel`, `GitService`, drop handlers, payload codec,
  conflict staging list.
- Protected hotspots reviewed: `RepoViewModel` / `GitService` untouched;
  pure View-layer interaction change.

## Ownership

- Primary owner layer: View (`DetailPanelView`).
- Why: purely AppKit/SwiftUI drag + gesture wiring; no orchestration/service
  logic. The drag payload construction and drop handling already live at the
  view boundary and are unchanged.
- Which larger type is intentionally not taking more responsibility:
  `RepoViewModel` — still only exposes selection + stage/unstage APIs.

## Affected Areas

- Screens / flows: Detail panel staged/unstaged file list (staging view).
- Services / helpers / view models: none.
- Files likely to change: `GitN/Sources/GitN/Views/Detail/DetailPanelView.swift`.

## Test Scope

- Unit tests:
  - Keep existing `StageFileDragPayloadTests` (payload codec unchanged).
  - Keep `UnstagedRubberBandSelectionTests` for the pure containment helper.
  - Add a small pure helper for the click-vs-drag threshold decision
    (e.g. `ImmediateDragDecider.shouldBeginDrag(from:to:threshold:)`) and unit
    test it, so the core "did the pointer move far enough to be a drag"
    decision is testable without AppKit event plumbing.
- Manual verification:
  - Press + small move on a row → drag begins immediately (no hold), drop on
    the other section stages/unstages reliably.
  - Simple click on a row (no move) → selects, opens diff, ⌘/Shift modify
    selection as before.
  - Marquee from inter-row gap and from bottom blank area both work.
  - Multi-select drag still carries all selected paths.
- Failure modes / edge cases: click with sub-threshold jitter must not become
  a drag; drag started on a selected row in a multi-selection must drag the
  whole selection; window/coordinate translation for the drag image.
- Known coverage blockers: `NSDraggingSession` initiation and AppKit event
  tracking can't be unit tested here; verified manually.

## Design Records

- RFC required? Borderline. This introduces a new reusable AppKit drag-source
  seam in the view layer, but it is confined to one file, one screen, and does
  not add a service/coordinator or cross-module boundary. Proceeding with
  intake-only per the workflow matrix (local UI change with clear ownership);
  will escalate to an RFC if the drag source needs to be generalized/shared
  across other lists later.
- ADR required? No.

## Completion Criteria

- Row drag starts immediately on a small pointer move, no press-and-hold.
- Click (no move) still selects and opens the diff, ⌘/Shift preserved.
- Marquee works from inter-row gaps and bottom blank area.
- Multi-selection drags carry the full selection.
- Builds and passes the existing test suite; new threshold-decider unit test
  passes.

## Open Questions

- None outstanding. Confirmed with stakeholder: 2px vertical / 4px horizontal
  spacing, and replacing `.draggable()` with a custom AppKit drag source is
  acceptable.

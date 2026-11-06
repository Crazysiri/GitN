# Feature Intake: defer tooltip window creation

- Status: Implemented and startup verified
- Owner: Codex
- Date: 2026-11-06

## Summary

The preview app crashes during first-window layout because StateObject initialization eagerly creates a tooltip NSPanel with an NSHostingView. Attaching the nested hosting view reenters AttributeGraph while it is updating the main view.

## Behavior Change

Tooltip controllers start without a window. A hover request queues panel creation on the main queue outside the current SwiftUI graph update; hide/disappear cancels queued work without creating a panel.

## Non-Goals

No tooltip visual redesign, inspector algorithm changes or Git backend changes.

## Change Boundary

- In scope: HoverTooltipPanelController lifecycle and modifier wiring, startup regression coverage, preview app rebuild.
- Out of scope: theme, merge, stash and unrelated navigation.
- Protected hotspots reviewed: RepoViewModel and GitService unchanged.

## Ownership

- Primary owner layer: shared tooltip presentation controller.
- Why this layer is the right owner: owns the AppKit window lifecycle and cancellation.
- Which larger type is intentionally not taking more responsibility: AppModel and RepoViewModel.

## Test Scope

- Unit tests: queued tooltip cancellation and no eager panel allocation.
- Integration tests: attach a view containing shared hover modifiers to an NSWindow, then lay it out.
- Manual verification: launch the packaged app and observe its first window; hover interaction where possible.
- Failure modes / edge cases: no hover, canceled hover, missing anchor window, disappearance before queued creation.
- Known coverage blockers: no full automated visual tooltip positioning checks.

## Design Records

- RFC required? No: local lifecycle fix within the existing view component.
- ADR required? No: no new architectural boundary.

## Completion Criteria

Controllers allocate no hosting view during StateObject initialization, canceled work cannot show a panel, focused tests pass and the repackaged app survives actual launch.

## Validation Results

- swift test --filter HoverTooltipLifecycleTests: 3 passed, zero failures. Includes initial NSHostingView attachment/layout and cancellation before queued creation.
- Rebuilt the app target and replaced/re-signed GitN/build/GitN-InspectorPreview.app; CFBundleVersion is now 1. codesign --verify --deep --strict passed.
- Launched the actual packaged executable on the reported macOS environment. Computer-use inspection confirmed the visible Repositories window with Open/Clone controls and no startup abort. Full visual tooltip hover positioning was not exercised.

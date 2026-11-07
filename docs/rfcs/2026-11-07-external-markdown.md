# RFC: External Markdown windows

- Date: 2026-11-07
- Status: Accepted for implementation

## Design

Handle AppKit application(_:open:) (the full URL batch), legacy application(_:openFiles:), and SwiftUI onOpenURL in the app layer, separately from repository state. All entries route to the same controller. The native URL-batch callback is necessary to retain every file in a cold multi-file event. Retain a dedicated MarkdownWindowController indexed by canonical local URL. Each NSWindow hosts a thin read-only document view with the application's shared ThemeManager. Close removes the retained entry; repeated open activates the existing window. The document window never creates a RepoViewModel or asks GitService to discover a repository. Existing repository windows are preserved on warm opens.

Read through a small Foundation helper, off the main actor, with paired security-scoped access. Validate local file URL, supported extension, regular file and UTF-8; expose loading and errors in the document view. Forward the containing directory to the existing Markdown renderer for relative links/images. Reuse MarkdownInspectorContentView's rich/plain decision and opt-in for large files. The external viewer is read-only to avoid silently discarding edits or introducing saving semantics.

Register net.daringfireball.markdown as an imported public.plain-text type, extensions md/markdown/mdown, document role Viewer, handler rank Alternate. AppDelegate replies to legacy open events after dispatching document windows. The normal repository scene and File > Open Repository command remain available. A repository scene first constructed in document mode stays hidden with no ContentView until explicitly requested, preserving a SwiftUI receiver for subsequent URLs. Capture that bootstrap status per scene so warm document events cannot tear down an existing repository view. File > Open Repository or reopening with no visible windows exits document bootstrap mode. Remove the unconditional application-activation main-window raise and restore the requested document's focus after scene routing completes.

## Validation / Risks

Test reader acceptance/rejection, canonical URLs, content fidelity and read errors without SwiftUI. Test controller duplicate and close behavior on the main actor. Build and run existing Markdown tests. Inspect launch metadata and manually exercise cold/warm/multi-file opens. Relative local images depend on the shared MarkdownUI image provider's existing support; no new image-loading engine is introduced. Files are snapshots; reopening an already open file focuses it, and closing/reopening reloads it. No file writes or default-handler changes occur.

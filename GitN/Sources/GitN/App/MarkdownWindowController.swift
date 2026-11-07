import AppKit
import SwiftUI

/// Local document loading deliberately has no dependency on repository state.
enum ExternalMarkdownFile {
    static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func supports(_ url: URL) -> Bool {
        url.isFileURL && url.lastPathComponent.isMarkdownFile
    }

    static func read(_ url: URL) throws -> String {
        guard supports(url) else { throw ReadError.unsupportedType }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ReadError.notRegularFile
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum ReadError: LocalizedError {
        case unsupportedType
        case notRegularFile

        var errorDescription: String? {
            switch self {
            case .unsupportedType: "Choose a local Markdown file (.md, .markdown, or .mdown)."
            case .notRegularFile: "The selected path is not a regular file."
            }
        }
    }
}

@MainActor
final class MarkdownWindowController: NSObject, NSWindowDelegate {
    private(set) var windows: [URL: NSWindow] = [:]
    private let theme: ThemeManager

    init(theme: ThemeManager) {
        self.theme = theme
    }

    func open(_ url: URL) {
        let identity = ExternalMarkdownFile.canonicalURL(url)
        if let window = windows[identity] {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            focusAfterSceneRouting(window, identity: identity)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.representedURL = url
        window.minSize = NSSize(width: 680, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView:
            ExternalMarkdownView(url: url).environment(theme)
        )
        windows[identity] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusAfterSceneRouting(window, identity: identity)
    }

    private func focusAfterSceneRouting(_ window: NSWindow, identity: URL) {
        // Launch Services can finish creating/activating a SwiftUI scene after
        // delivering the file event. Restore document focus once that turn ends.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.windows[identity] === window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}

private struct ExternalMarkdownView: View {
    let url: URL
    @Environment(ThemeManager.self) private var theme
    @State private var content: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let content {
                MarkdownInspectorContentView(
                    filePath: url.path,
                    text: .constant(content),
                    isEditable: false,
                    baseURL: url.deletingLastPathComponent()
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Open Markdown", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(errorMessage).textSelection(.enabled)
                }
            } else {
                ProgressView("Opening Markdown…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
        .task {
            let documentURL = url
            let load = Task.detached(priority: .userInitiated) {
                try ExternalMarkdownFile.read(documentURL)
            }
            do {
                let text = try await load.value
                guard !Task.isCancelled else { return }
                content = text
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

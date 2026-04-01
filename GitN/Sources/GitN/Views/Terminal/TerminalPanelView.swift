import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let repoPath: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            SwiftTermView(repoPath: repoPath)
        }
        .background(ChromePalette.toolbarBackground)
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(ChromePalette.terminalAccent)
            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChromePalette.terminalPrimaryText)
            Spacer()

            Button(action: { isVisible = false }) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(ChromePalette.terminalSecondaryText)
            }
            .buttonStyle(.plain)
            .hoverTooltip("Hide Terminal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ChromePalette.toolbarBackground)
    }
}

// MARK: - SwiftTerm NSViewRepresentable

struct SwiftTermView: NSViewRepresentable {
    let repoPath: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let termView = DropReceivingTerminalView(frame: .zero)
        termView.wantsLayer = true
        termView.processDelegate = context.coordinator

        let fontSize: CGFloat = 12
        termView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        termView.optionAsMetaKey = true

        applyTheme(termView)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")
        env.append("TERM_PROGRAM=GitN")
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env.append("HOME=\(home)")
        }

        termView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: repoPath
        )

        context.coordinator.terminalView = termView
        return termView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyTheme(nsView)
    }

    private func applyTheme(_ termView: LocalProcessTerminalView) {
        termView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        termView.nativeBackgroundColor = .textBackgroundColor
        termView.nativeForegroundColor = .labelColor
        termView.caretColor = .controlAccentColor
        termView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        termView.appearance = nil
        termView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var terminalView: LocalProcessTerminalView?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
        }
    }
}

enum TerminalDropInsertionFormatter {
    static func pastedText(for paths: [String]) -> String {
        let escapedPaths = paths
            .filter { !$0.isEmpty }
            .map(shellEscape)

        guard !escapedPaths.isEmpty else { return "" }
        return escapedPaths.joined(separator: " ") + " "
    }

    static func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private final class DropReceivingTerminalView: LocalProcessTerminalView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFilePaths(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFilePaths(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedFilePaths(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = droppedFilePaths(from: sender)
        let pastedText = TerminalDropInsertionFormatter.pastedText(for: paths)
        guard !pastedText.isEmpty else { return false }

        window?.makeFirstResponder(self)
        send(txt: pastedText)
        return true
    }

    private func droppedFilePaths(from draggingInfo: NSDraggingInfo) -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let classes: [AnyClass] = [NSURL.self]
        let urls = draggingInfo.draggingPasteboard.readObjects(forClasses: classes, options: options) as? [URL] ?? []
        return urls.map(\.path)
    }
}

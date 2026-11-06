import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let store: TerminalSessionStore
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            if let activeView = store.activeView {
                TerminalSessionHost(terminalView: activeView)
            } else {
                ContentUnavailableView("No Terminal Session", systemImage: "terminal")
            }
        }
        .background(ChromePalette.toolbarBackground)
        .onAppear { store.ensureSession() }
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(ChromePalette.terminalAccent)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(store.sessions) { session in
                        terminalTab(session)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button { store.createSession() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .hoverTooltip("New Terminal")

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

    private func terminalTab(_ session: TerminalSessionInfo) -> some View {
        let isSelected = session.id == store.activeID
        return HStack(spacing: 3) {
            Button { store.selectSession(session.id) } label: {
                HStack(spacing: 4) {
                    if !session.isRunning {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                    }
                    Text(session.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 110)
                }
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(ChromePalette.terminalPrimaryText)
            }
            .buttonStyle(.plain)

            Button { store.closeSession(session.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ChromePalette.terminalSecondaryText)
            }
            .buttonStyle(.plain)
            .hoverTooltip("Close Terminal")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? ChromePalette.chromeButtonHoverFill : ChromePalette.chromeButtonFill)
        )
        .contextMenu {
            Button("Move Left") { store.moveSession(session.id, by: -1) }
            Button("Move Right") { store.moveSession(session.id, by: 1) }
            Divider()
            Button("Close Others") { store.closeOtherSessions(keeping: session.id) }
                .disabled(store.sessions.count < 2)
            Button("Close Terminal") { store.closeSession(session.id) }
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

final class DropReceivingTerminalView: LocalProcessTerminalView {
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

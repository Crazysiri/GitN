import AppKit
import Darwin
import Observation
import SwiftTerm
import SwiftUI

struct TerminalSessionInfo: Identifiable {
    let id: UUID
    var title: String
    var isRunning = true
}

/// Owns PTYs for one repository tab, independently of panel visibility.
@Observable @MainActor
final class TerminalSessionStore {
    let repoPath: String
    private let shellPath: String
    private(set) var selection = TerminalSessionSelection()
    private(set) var sessionInfo: [UUID: TerminalSessionInfo] = [:]
    @ObservationIgnored private var terminalViews: [UUID: DropReceivingTerminalView] = [:]
    @ObservationIgnored private var delegates: [UUID: TerminalSessionProcessDelegate] = [:]
    @ObservationIgnored private var nextOrdinal = 1

    init(repoPath: String, shellPath: String? = nil) {
        self.repoPath = repoPath
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var sessions: [TerminalSessionInfo] {
        selection.orderedIDs.compactMap { sessionInfo[$0] }
    }

    var activeID: UUID? { selection.activeID }
    var activeView: LocalProcessTerminalView? {
        guard let id = activeID else { return nil }
        return terminalViews[id]
    }

    func ensureSession() {
        if selection.orderedIDs.isEmpty { createSession() }
    }

    func createSession() {
        let id = UUID()
        let ordinal = nextOrdinal
        nextOrdinal += 1
        let terminalView = DropReceivingTerminalView(frame: .zero)
        terminalView.wantsLayer = true
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.optionAsMetaKey = true
        TerminalSessionTheme.apply(to: terminalView)
        let delegate = TerminalSessionProcessDelegate(id: id, store: self)
        terminalView.processDelegate = delegate

        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("LANG=en_US.UTF-8")
        environment.append("TERM_PROGRAM=GitN")
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            environment.append("HOME=" + home)
        }

        terminalViews[id] = terminalView
        delegates[id] = delegate
        sessionInfo[id] = TerminalSessionInfo(id: id, title: "Terminal " + String(ordinal))
        selection.append(id)
        terminalView.startProcess(
            executable: shellPath,
            args: ["-l"],
            environment: environment,
            execName: "-" + (shellPath as NSString).lastPathComponent,
            currentDirectory: repoPath
        )
    }

    func selectSession(_ id: UUID) { selection.select(id) }
    func moveSession(_ id: UUID, by offset: Int) { selection.move(id, by: offset) }
    func selectAdjacentSession(_ offset: Int) { selection.selectAdjacent(offset) }

    func closeSession(_ id: UUID) {
        guard selection.orderedIDs.contains(id) else { return }
        selection.close(id)
        terminateSession(id)
    }

    func closeOtherSessions(keeping id: UUID) {
        for otherID in selection.closeOthers(keeping: id) {
            terminateSession(otherID)
        }
    }

    func closeAllSessions() {
        let ids = selection.orderedIDs
        selection = TerminalSessionSelection()
        for id in ids { terminateSession(id) }
    }

    private func terminateSession(_ id: UUID) {
        sessionInfo.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
        if let view = terminalViews.removeValue(forKey: id) {
            view.removeFromSuperview()
            let shellPID = view.process.shellPid
            // Interactive shells may ignore SIGTERM. forkpty makes the shell a
            // process-group leader, so hang up the entire terminal job first.
            if shellPID > 0 {
                let signalTarget = getpgid(shellPID) == shellPID ? -shellPID : shellPID
                _ = kill(signalTarget, SIGHUP)
            }
            view.terminate()
            if shellPID > 0 {
                Task.detached(priority: .utility) {
                    // SwiftTerm cancels its process monitor during terminate(),
                    // so reap the child ourselves instead of leaving a zombie.
                    for _ in 0..<20 {
                        var status: Int32 = 0
                        let result = waitpid(shellPID, &status, WNOHANG)
                        if result == shellPID || (result < 0 && errno == ECHILD) { return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    let signalTarget = getpgid(shellPID) == shellPID ? -shellPID : shellPID
                    _ = kill(signalTarget, SIGKILL)
                    var status: Int32 = 0
                    _ = waitpid(shellPID, &status, 0)
                }
            }
        }
    }

    fileprivate func sessionTitleChanged(_ id: UUID, title: String) {
        guard !title.isEmpty, var info = sessionInfo[id] else { return }
        info.title = title
        sessionInfo[id] = info
    }

    fileprivate func sessionExited(_ id: UUID) {
        guard var info = sessionInfo[id] else { return }
        info.isRunning = false
        sessionInfo[id] = info
    }
}

private final class TerminalSessionProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let id: UUID
    weak var store: TerminalSessionStore?

    init(id: UUID, store: TerminalSessionStore) {
        self.id = id
        self.store = store
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.store?.sessionTitleChanged(self.id, title: title)
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.store?.sessionExited(self.id)
        }
    }
}

struct TerminalSessionHost: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        for view in nsView.subviews where view !== terminalView {
            view.removeFromSuperview()
        }
        if terminalView.superview !== nsView {
            terminalView.removeFromSuperview()
            terminalView.frame = nsView.bounds
            terminalView.autoresizingMask = [.width, .height]
            nsView.addSubview(terminalView)
            DispatchQueue.main.async { [weak nsView, weak terminalView] in
                guard let nsView, let terminalView,
                      terminalView.superview === nsView else { return }
                nsView.window?.makeFirstResponder(terminalView)
            }
        }
        TerminalSessionTheme.apply(to: terminalView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}

private enum TerminalSessionTheme {
    static func apply(to view: LocalProcessTerminalView) {
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        view.nativeBackgroundColor = .textBackgroundColor
        view.nativeForegroundColor = .labelColor
        view.caretColor = .controlAccentColor
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
        view.appearance = nil
        view.needsDisplay = true
    }
}

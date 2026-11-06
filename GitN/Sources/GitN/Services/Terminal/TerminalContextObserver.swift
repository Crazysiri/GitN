import Darwin
import Foundation
import Observation

/// Observes shell context (cwd + foreground process) for terminal sessions by
/// low-frequency polling of the OS, per SPEC §6.2. No shell injection: cwd comes
/// from the shell PID's vnode info, foreground from the PTY's tcgetpgrp.
///
/// The poll is a safety net; prompt events (M3) can refresh on top of it. The
/// cadence here is deliberately modest, not a performance target, and is not a
/// copy of any reference app's hysteresis.
@Observable @MainActor
final class TerminalContextObserver {
    private struct Tracked {
        let shellPID: () -> pid_t
        let masterFD: () -> Int32
        let shellName: String
    }

    /// Published per-session context for the UI.
    private(set) var contexts: [UUID: TerminalContext] = [:]

    @ObservationIgnored private var tracked: [UUID: Tracked] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let interval: TimeInterval

    init(interval: TimeInterval = 2.0) {
        self.interval = interval
    }

    func track(id: UUID, transport: XtermPTYTransport) {
        tracked[id] = Tracked(
            shellPID: { transport.shellPID },
            masterFD: { transport.masterFD },
            shellName: transport.shellName
        )
        contexts[id] = .empty
        startTimerIfNeeded()
        pollSession(id) // immediate first read
    }

    func untrack(id: UUID) {
        tracked.removeValue(forKey: id)
        contexts.removeValue(forKey: id)
        if tracked.isEmpty { stopTimer() }
    }

    func context(for id: UUID) -> TerminalContext {
        contexts[id] ?? .empty
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func pollAll() {
        for id in tracked.keys { pollSession(id) }
    }

    private func pollSession(_ id: UUID) {
        guard let t = tracked[id] else { return }
        let pid = t.shellPID()
        let fd = t.masterFD()

        let observedCwd = ProcessInspector.workingDirectory(ofPID: pid)

        // Foreground process: nil when the shell itself is in the foreground
        // (i.e. sitting at the prompt), otherwise the running command's name.
        var observedForeground: String?
        if let fgName = ProcessInspector.foregroundProcessName(masterFD: fd),
           fgName != t.shellName {
            observedForeground = fgName
        }

        let previous = contexts[id] ?? .empty
        let next = previous.merging(observedCwd: observedCwd, observedForeground: observedForeground)
        if next != previous {
            contexts[id] = next
        }
    }
}

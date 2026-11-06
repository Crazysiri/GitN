import Darwin
import Foundation

/// Owns one `ForkPTY`, runs its read loop off the main thread, and forwards
/// output bytes and exit to the host on the main actor. Route-B PTY backend
/// for the xterm.js renderer — no Node, no node-pty.
final class XtermPTYTransport: @unchecked Sendable {
    private let pty = ForkPTY()
    private let repoPath: String
    private let shellPath: String
    private let readQueue = DispatchQueue(label: "com.gitn.terminal.pty-read", qos: .userInitiated)
    private var readSource: DispatchSourceRead?

    /// Called on the main actor with raw PTY output bytes.
    var onOutput: (@MainActor (Data) -> Void)?
    /// Called on the main actor once, when the shell exits / PTY closes.
    var onExit: (@MainActor () -> Void)?

    private var didSignalExit = false

    /// When true, install the opt-in prompt-marker wrapper so the terminal can
    /// locate the prompt (foundation for suggestions). Defaults off.
    private let promptIntegration: Bool
    private var integrationDir: URL?

    init(repoPath: String, shellPath: String? = nil, promptIntegration: Bool = false) {
        self.repoPath = repoPath
        self.shellPath = shellPath
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        self.promptIntegration = promptIntegration
    }

    /// Build the child environment: inherit the user's environment, de-dupe by
    /// key, then force terminal-identifying variables. HOME/PATH/proxy/SSH_AUTH_SOCK
    /// and locale are preserved because they come from the inherited environment.
    static func buildEnvironment(base: [String: String]) -> [String] {
        var merged = base
        merged["TERM"] = "xterm-256color"
        merged["TERM_PROGRAM"] = "GitN"
        if merged["LANG"] == nil { merged["LANG"] = "en_US.UTF-8" }
        return merged.map { "\($0.key)=\($0.value)" }
    }

    func start(cols: UInt16, rows: UInt16) {
        let shellName = (shellPath as NSString).lastPathComponent
        var envDict = ProcessInfo.processInfo.environment
        var arguments = ["-l"]

        if promptIntegration, let shell = ShellPromptIntegration.shell(forExecutable: shellPath) {
            do {
                try configurePromptIntegration(shell: shell, envDict: &envDict, arguments: &arguments)
            } catch {
                // Integration is best-effort: fall back to a plain login shell.
                envDict = ProcessInfo.processInfo.environment
                arguments = ["-l"]
            }
        }

        let environment = Self.buildEnvironment(base: envDict)
        do {
            try pty.start(
                executable: shellPath,
                arguments: arguments,
                execName: "-" + shellName, // leading "-" → login shell
                environment: environment,
                directory: repoPath,
                cols: max(cols, 1),
                rows: max(rows, 1)
            )
        } catch {
            signalExit()
            return
        }
        startReadLoop()
    }

    /// Write the per-session wrapper files and adjust argv/env so the shell loads
    /// them. Never touches the user's real dotfiles.
    private func configurePromptIntegration(
        shell: ShellPromptIntegration.Shell,
        envDict: inout [String: String],
        arguments: inout [String]
    ) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitn-term-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        integrationDir = dir

        switch shell {
        case .zsh:
            // Preserve the user's ZDOTDIR so the wrapper can restore it, then
            // point zsh at our directory for startup only.
            if let userZDOTDIR = envDict["ZDOTDIR"] {
                envDict["GITN_USER_ZDOTDIR"] = userZDOTDIR
            }
            let zshrc = dir.appendingPathComponent(".zshrc")
            try ShellPromptIntegration.zdotdirZshrc().write(to: zshrc, atomically: true, encoding: .utf8)
            envDict["ZDOTDIR"] = dir.path

        case .bash:
            let rcfile = dir.appendingPathComponent("gitn-bashrc")
            try ShellPromptIntegration.bashRCFile().write(to: rcfile, atomically: true, encoding: .utf8)
            arguments = ["--rcfile", rcfile.path, "-i"]
        }
    }

    private func cleanupIntegrationDir() {
        if let dir = integrationDir {
            try? FileManager.default.removeItem(at: dir)
            integrationDir = nil
        }
    }

    private func startReadLoop() {
        guard pty.masterFD >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: pty.masterFD, queue: readQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            switch self.pty.read() {
            case .some(let data) where !data.isEmpty:
                let bytes = data
                Task { @MainActor in self.onOutput?(bytes) }
            case .some:
                break // EAGAIN: nothing right now
            case .none:
                self.signalExit()
            }
        }
        source.setCancelHandler { [weak self] in
            self?.pty.terminate()
        }
        readSource = source
        source.resume()
    }

    func write(_ data: Data) {
        readQueue.async { [weak self] in
            self?.pty.write(data)
        }
    }

    func resize(cols: UInt16, rows: UInt16) {
        readQueue.async { [weak self] in
            self?.pty.resize(cols: max(cols, 1), rows: max(rows, 1))
        }
    }

    func terminate() {
        if let source = readSource {
            readSource = nil
            source.cancel() // cancel handler terminates the PTY
        } else {
            pty.terminate()
        }
        cleanupIntegrationDir()
    }

    /// The directory the shell was launched in (fallback cwd for suggestions).
    var launchCwd: String { repoPath }

    /// Shell child PID (for cwd queries). -1 before start / after exit.
    var shellPID: pid_t { pty.childPID }
    /// PTY master FD (for foreground-group queries). -1 when closed.
    var masterFD: Int32 { pty.masterFD }
    /// Short name of the launched shell, e.g. "zsh".
    var shellName: String { (shellPath as NSString).lastPathComponent }

    private func signalExit() {
        Task { @MainActor [weak self] in
            guard let self, !self.didSignalExit else { return }
            self.didSignalExit = true
            self.onExit?()
        }
    }

    var isRunning: Bool { pty.isRunning }
}

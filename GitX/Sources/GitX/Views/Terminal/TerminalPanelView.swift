import SwiftUI
import AppKit

struct TerminalPanelView: View {
    let repoPath: String
    @Binding var isVisible: Bool
    var onCommandExecuted: (() -> Void)?

    @State private var commandInput: String = ""
    @State private var outputLines: [TerminalLine] = []
    @State private var isRunning = false
    @State private var focusTrigger = UUID()
    @State private var currentDirectory: String
    @State private var completionEngine: TabCompletionEngine
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    @State private var savedInput: String = ""

    init(repoPath: String, isVisible: Binding<Bool>, onCommandExecuted: (() -> Void)? = nil) {
        self.repoPath = repoPath
        self._isVisible = isVisible
        self.onCommandExecuted = onCommandExecuted
        self._currentDirectory = State(initialValue: repoPath)
        self._completionEngine = State(initialValue: TabCompletionEngine(workingDirectory: repoPath))
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            terminalOutput
            Divider()
            terminalInput
        }
        .background(Color(.black).opacity(0.9))
        .onAppear {
            outputLines.append(TerminalLine(
                text: "GitX Terminal — \(repoPath)",
                type: .info
            ))
        }
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(.green)
            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()

            Button(action: { outputLines.removeAll() }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Clear")

            Button(action: { isVisible = false }) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Hide Terminal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.black).opacity(0.95))
    }

    // MARK: - Output

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(outputLines) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.color)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: outputLines.count) {
                if let last = outputLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input

    private var terminalInput: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            TerminalTextField(
                text: $commandInput,
                isEnabled: !isRunning,
                focusTrigger: focusTrigger,
                onSubmit: executeCommand,
                onTab: handleTabCompletion,
                onUpArrow: historyUp,
                onDownArrow: historyDown
            )
            .frame(height: 16)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.black).opacity(0.95))
    }

    // MARK: - Tab Completion

    private func handleTabCompletion() {
        let result = completionEngine.complete(input: commandInput)

        switch result {
        case .none:
            break
        case .single(let completed):
            commandInput = completed
        case .multiple(let completed, let candidates):
            commandInput = completed
            let display = candidates.joined(separator: "  ")
            outputLines.append(TerminalLine(text: display, type: .info))
        }
    }

    // MARK: - History Navigation

    private func historyUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex == -1 {
            savedInput = commandInput
            historyIndex = commandHistory.count - 1
        } else if historyIndex > 0 {
            historyIndex -= 1
        }
        commandInput = commandHistory[historyIndex]
    }

    private func historyDown() {
        guard historyIndex >= 0 else { return }
        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            commandInput = commandHistory[historyIndex]
        } else {
            historyIndex = -1
            commandInput = savedInput
        }
    }

    // MARK: - Execution

    private func executeCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        commandHistory.append(cmd)
        historyIndex = -1
        savedInput = ""

        outputLines.append(TerminalLine(text: "$ \(cmd)", type: .command))
        commandInput = ""
        isRunning = true

        let cwd = currentDirectory
        Task.detached {
            let (result, newDir) = await Self.runShellCommand(cmd, in: cwd)
            await MainActor.run { [result, newDir] in
                if !result.isEmpty {
                    for line in result.components(separatedBy: "\n") {
                        outputLines.append(TerminalLine(text: line, type: .output))
                    }
                }
                if let newDir {
                    currentDirectory = newDir
                    completionEngine = TabCompletionEngine(workingDirectory: newDir)
                }
                isRunning = false
                focusTrigger = UUID()
                onCommandExecuted?()
            }
        }
    }

    /// Returns (output, newWorkingDirectory).
    /// `newWorkingDirectory` is non-nil only when the command changed it (e.g. `cd`).
    private static func runShellCommand(_ command: String, in directory: String) async -> (String, String?) {
        let wrappedCommand = "\(command)\necho __GITX_PWD__\npwd"

        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", wrappedCommand]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 && !err.isEmpty {
                return (err.trimmingCharacters(in: .whitespacesAndNewlines), nil)
            }

            let marker = "__GITX_PWD__"
            if let range = out.range(of: marker) {
                let visibleOutput = String(out[out.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let newDir = String(out[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let changedDir = newDir != directory ? newDir : nil
                return (visibleOutput, changedDir)
            }
            return (out.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        } catch {
            return ("Error: \(error.localizedDescription)", nil)
        }
    }
}

// MARK: - NSViewRepresentable TextField

/// Uses a real NSTextField for reliable focus and key event handling on macOS.
/// SwiftUI's TextField with .plain style is unreliable for first responder
/// inside HSplitView hierarchies.
struct TerminalTextField: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var focusTrigger: UUID
    var onSubmit: () -> Void
    var onTab: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void

    func makeNSView(context: Context) -> TerminalInputField {
        let field = TerminalInputField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = .white
        field.insertionPointColor = .green
        field.placeholderAttributedString = NSAttributedString(
            string: "Enter command...",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.3),
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: TerminalInputField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEnabled = isEnabled

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TerminalTextField
        var lastFocusTrigger: UUID

        init(_ parent: TerminalTextField) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            }
            return false
        }
    }
}

/// NSTextField subclass that properly handles window activation and focus.
///
/// Key fixes for macOS first responder behavior:
/// - `acceptsFirstMouse` returns true so clicks work even when the window
///   is not key (e.g. user switches from another app).
/// - `mouseDown` explicitly makes the window key before calling super,
///   ensuring keyboard events are routed to this window.
final class TerminalInputField: NSTextField {
    var insertionPointColor: NSColor = .green

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = insertionPointColor
        }
        return result
    }
}

// MARK: - Terminal Line

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType

    enum LineType {
        case command, output, error, info
    }

    var color: Color {
        switch type {
        case .command: return .green
        case .output: return .white.opacity(0.85)
        case .error: return .red
        case .info: return .cyan
        }
    }
}

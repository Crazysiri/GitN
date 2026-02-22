import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let repoPath: String
    @Binding var isVisible: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            SwiftTermView(repoPath: repoPath, isDark: theme.isDark)
        }
        .background(theme.isDark ? Color.black : Color(.textBackgroundColor))
    }

    // MARK: - Header

    private var terminalHeader: some View {
        HStack {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(theme.isDark ? .green : .accentColor)
            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.isDark ? .white.opacity(0.8) : .primary)
            Spacer()

            Button(action: { isVisible = false }) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(theme.isDark ? .white.opacity(0.5) : .secondary)
            }
            .buttonStyle(.plain)
            .help("Hide Terminal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.isDark ? Color.black.opacity(0.95) : Color(.controlBackgroundColor))
    }
}

// MARK: - SwiftTerm NSViewRepresentable

struct SwiftTermView: NSViewRepresentable {
    let repoPath: String
    let isDark: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let termView = LocalProcessTerminalView(frame: .zero)
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
        if isDark {
            termView.nativeBackgroundColor = .black
            termView.nativeForegroundColor = NSColor(white: 0.9, alpha: 1.0)
            termView.caretColor = .green
            termView.selectedTextBackgroundColor = NSColor(white: 0.3, alpha: 1.0)
            termView.appearance = NSAppearance(named: .darkAqua)
        } else {
            termView.nativeBackgroundColor = .white
            termView.nativeForegroundColor = NSColor(white: 0.15, alpha: 1.0)
            termView.caretColor = .systemBlue
            termView.selectedTextBackgroundColor = .selectedTextBackgroundColor
            termView.appearance = NSAppearance(named: .aqua)
        }
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

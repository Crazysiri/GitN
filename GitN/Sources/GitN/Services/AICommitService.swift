import Foundation

/// Calls the local `cursor-agent` CLI to generate commit messages from staged diffs.
enum AICommitService {

    private static let defaultPrompt = """
    Based on the following git diff, generate a concise and meaningful commit message.
    Follow the Conventional Commits format: type(scope): description
    Common types: feat, fix, refactor, docs, style, test, chore, perf, ci, build.
    The first line (title) should be no more than 72 characters.
    If needed, add a blank line followed by a more detailed description body.
    Output ONLY the commit message, nothing else.
    """

    // MARK: - User Settings

    static var userPrompt: String {
        get {
            UserDefaults.standard.string(forKey: "GitN.aiCommitPrompt") ?? defaultPrompt
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "GitN.aiCommitPrompt")
        }
    }

    static var apiKey: String {
        get {
            UserDefaults.standard.string(forKey: "GitN.cursorAPIKey") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "GitN.cursorAPIKey")
        }
    }

    /// Check if cursor-agent is installed
    static var isAgentInstalled: Bool {
        findAgentPath() != nil
    }

    /// Generate a commit message from the given diff text using `cursor-agent`.
    /// Returns (title, description) parsed from the AI response.
    static func generateCommitMessage(diff: String) async throws -> (title: String, description: String) {
        let prompt = userPrompt + "\n\n```diff\n" + diff.prefix(8000) + "\n```"

        let output = try await runCursorAgent(prompt: prompt)
        return parseCommitMessage(output)
    }

    // MARK: - Private

    private static func findAgentPath() -> String? {
        let home = NSHomeDirectory()
        let possiblePaths = [
            "\(home)/.local/bin/cursor-agent",
            "\(home)/.cursor/bin/cursor-agent",
            "/usr/local/bin/cursor-agent",
            "/opt/homebrew/bin/cursor-agent",
            "\(home)/Library/Application Support/Cursor/bin/cursor-agent",
        ]
        for p in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    private static func runCursorAgent(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            let home = NSHomeDirectory()

            // Resolve the effective API key: user setting > environment variable
            let effectiveAPIKey = {
                let stored = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stored.isEmpty { return stored }
                return ProcessInfo.processInfo.environment["CURSOR_API_KEY"] ?? ""
            }()

            if let found = findAgentPath() {
                proc.executableURL = URL(fileURLWithPath: found)
                var args = ["--print", "--trust", "--model", "composer-1"]
                if !effectiveAPIKey.isEmpty {
                    args = ["--api-key", effectiveAPIKey] + args
                }
                args.append(prompt)
                proc.arguments = args
            } else {
                // Fall back to PATH lookup via /bin/zsh -lc
                let apiArg = effectiveAPIKey.isEmpty ? "" : "--api-key '\(effectiveAPIKey)' "
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", "cursor-agent \(apiArg)--print --trust --model composer-1 \"$1\"", "--", prompt]
            }

            // Ensure user-level bin dirs are in PATH for child process
            var env = ProcessInfo.processInfo.environment
            let extraPaths = [
                "\(home)/.local/bin",
                "\(home)/.cursor/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            if !effectiveAPIKey.isEmpty {
                env["CURSOR_API_KEY"] = effectiveAPIKey
            }
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "cursor-agent failed"

                    // Detect specific errors for better guidance
                    if errMsg.localizedCaseInsensitiveContains("API_KEY") ||
                       errMsg.localizedCaseInsensitiveContains("auth") ||
                       errMsg.localizedCaseInsensitiveContains("401") ||
                       errMsg.localizedCaseInsensitiveContains("Unauthorized") {
                        continuation.resume(throwing: AICommitError.apiKeyMissing)
                    } else {
                        continuation.resume(throwing: AICommitError.agentFailed(errMsg))
                    }
                } else if output.isEmpty {
                    continuation.resume(throwing: AICommitError.emptyResponse)
                } else {
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: AICommitError.notFound)
            }
        }
    }

    private static func parseCommitMessage(_ raw: String) -> (title: String, description: String) {
        // Strip markdown code fences (```...```) that AI may wrap around output
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove opening ``` (with optional language tag like ```text, ```markdown, etc.)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
        }
        // Remove closing ```
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let lines = cleaned.components(separatedBy: "\n")
        let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleaned
        let rest = lines.dropFirst()
            .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, rest)
    }
}

enum AICommitError: LocalizedError {
    case notFound
    case apiKeyMissing
    case agentFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "cursor-agent not found. Install it via: npm install -g @anthropic-ai/cursor-agent, or install Cursor IDE."
        case .apiKeyMissing:
            return "CURSOR_API_KEY is not configured. Please set it in GitN → Settings → AI Commit."
        case .agentFailed(let msg):
            return "cursor-agent error: \(msg)"
        case .emptyResponse:
            return "cursor-agent returned an empty response."
        }
    }
}

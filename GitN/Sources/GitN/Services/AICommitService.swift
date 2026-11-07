import Foundation

enum AICommitTool: String, CaseIterable, Identifiable {
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var executableCandidates: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex:
            return [
                "\(home)/.local/bin/codex",
                "\(home)/.npm-global/bin/codex",
                "/usr/local/bin/codex",
                "/opt/homebrew/bin/codex",
            ]
        }
    }

    var installInstructions: [String] {
        switch self {
        case .codex:
            return [
                "1. Ensure `codex` is available in your terminal PATH",
                "2. Run `codex login` or complete the terminal authorization flow",
                "3. GitN calls Codex with a read-only sandbox and sends the diff through stdin.",
            ]
        }
    }
}

enum AICommitToolStatus: Equatable {
    case available
    case loginRequired
    case unavailable
}

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

    static var selectedTool: AICommitTool {
        get {
            let raw = UserDefaults.standard.string(forKey: "GitN.aiCommitTool") ?? ""
            return AICommitTool(rawValue: raw) ?? .codex
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "GitN.aiCommitTool")
        }
    }

    static var selectedToolInstalled: Bool {
        findExecutablePath(for: selectedTool) != nil
    }

    static func isToolInstalled(_ tool: AICommitTool) -> Bool {
        findExecutablePath(for: tool) != nil
    }

    static func toolStatus(_ tool: AICommitTool) -> AICommitToolStatus {
        guard findExecutablePath(for: tool) != nil else {
            return .unavailable
        }
        switch tool {
        case .codex:
            return isCodexLoggedIn() ? .available : .loginRequired
        }
    }

    static func toolStatusAsync(_ tool: AICommitTool) async -> AICommitToolStatus {
        guard findExecutablePath(for: tool) != nil else {
            return .unavailable
        }
        switch tool {
        case .codex:
            return await isCodexLoggedInAsync() ? .available : .loginRequired
        }
    }

    static func generateCommitMessage(diff: String) async throws -> (title: String, description: String) {
        let prompt = userPrompt + "\n\n```diff\n" + diff.prefix(8000) + "\n```"
        let output = try await runTool(selectedTool, prompt: prompt)
        return parseCommitMessage(output)
    }

    // MARK: - Private

    private static func findExecutablePath(for tool: AICommitTool) -> String? {
        for p in tool.executableCandidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    private static func runTool(_ tool: AICommitTool, prompt: String) async throws -> String {
        switch tool {
        case .codex:
            guard await isCodexLoggedInAsync() else {
                throw AICommitError.authorizationRequired(.codex)
            }
            return try await runCodex(prompt: prompt)
        }
    }

    private static func makeBaseEnvironment() -> [String: String] {
        let home = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        return env
    }

    private static func isCodexLoggedIn() -> Bool {
        // Kept for the existing synchronous status API; bound the helper off the UI thread.
        let semaphore = DispatchSemaphore(value: 0)
        let result = LoginStatusResult()
        Task.detached {
            result.set(await isCodexLoggedInAsync())
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 12) == .success else { return false }
        return result.get()
    }

    private final class LoginStatusResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set(_ value: Bool) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private static func isCodexLoggedInAsync() async -> Bool {
        guard let executable = findExecutablePath(for: .codex),
              let output = try? await BoundedProcessRunner.run(executable: executable,
                arguments: ["login", "status"], environment: makeBaseEnvironment(), timeout: 10),
              output.status == 0 else { return false }
        return codexStatusLooksAuthenticated(
            output: String(decoding: output.stdout, as: UTF8.self),
            errorOutput: String(decoding: output.stderr, as: UTF8.self))
    }

    private static func codexStatusLooksAuthenticated(output: String, errorOutput: String) -> Bool {
        let combined = [output, errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()

        return combined.contains("logged in") ||
            combined.contains("authenticated") ||
            combined.contains("using chatgpt")
    }

    static func generationArguments(directory: URL, output: URL) -> [String] {
        ["--ask-for-approval", "never", "exec", "--ignore-user-config", "--ignore-rules",
         "--disable", "shell_tool", "--disable", "multi_agent",
         "--ephemeral", "--sandbox", "read-only", "--skip-git-repo-check",
         "--config", "web_search=\"disabled\"", "--cd", directory.path,
         "--output-last-message", output.path, "-"]
    }

    private static func runCodex(prompt: String) async throws -> String {
        guard let executable = findExecutablePath(for: .codex) else { throw AICommitError.notFound(.codex) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gitn-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("message.txt")
        let result = try await BoundedProcessRunner.run(executable: executable,
            arguments: generationArguments(directory: directory, output: outputURL), directory: directory,
            environment: makeBaseEnvironment(), input: Data(prompt.utf8), timeout: 120, outputLimit: 1_048_576)
        if result.status != 0 {
            // Do not echo CLI stderr: it can contain prompts, diffs or credentials.
            let error = String(decoding: result.stderr, as: UTF8.self).lowercased()
            if error.contains("login") || error.contains("not authenticated") || error.contains("unauthorized") {
                throw AICommitError.authorizationRequired(.codex)
            }
            throw AICommitError.agentFailed(.codex, "Generation failed (exit \(result.status)). Ensure your Codex CLI supports --ignore-user-config and --ignore-rules.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 65_536 else {
            throw AICommitError.agentFailed(.codex, "Invalid or oversized commit message.")
        }
        let output = try String(contentsOf: outputURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw AICommitError.emptyResponse(.codex) }
        return output
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
    case notFound(AICommitTool)
    case authorizationRequired(AICommitTool)
    case agentFailed(AICommitTool, String)
    case emptyResponse(AICommitTool)

    var errorDescription: String? {
        switch self {
        case .notFound(let tool):
            switch tool {
            case .codex:
                return "codex not found. Make sure the `codex` CLI is installed and available in PATH."
            }
        case .authorizationRequired(let tool):
            switch tool {
            case .codex:
                return "codex is not logged in. Open Terminal and run `codex`, then complete the login flow before trying again."
            }
        case .agentFailed(let tool, let msg):
            return "\(tool.displayName) error: \(msg)"
        case .emptyResponse(let tool):
            return "\(tool.displayName) returned an empty response."
        }
    }
}

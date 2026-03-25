import Foundation

enum AICommitTool: String, CaseIterable, Identifiable {
    case cursorAgent = "cursor-agent"
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var requiresAPIKey: Bool {
        switch self {
        case .cursorAgent:
            return true
        case .codex:
            return false
        }
    }

    var executableCandidates: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .cursorAgent:
            return [
                "\(home)/.local/bin/cursor-agent",
                "\(home)/.cursor/bin/cursor-agent",
                "/usr/local/bin/cursor-agent",
                "/opt/homebrew/bin/cursor-agent",
                "\(home)/Library/Application Support/Cursor/bin/cursor-agent",
            ]
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
        case .cursorAgent:
            return [
                "1. Install Cursor IDE from cursor.com",
                "2. Run:  cursor-agent install-shell-integration",
                "3. Or:   cursor-agent login",
            ]
        case .codex:
            return [
                "1. Ensure `codex` is available in your terminal PATH",
                "2. Run `codex login` or complete the terminal authorization flow",
                "3. GitN will call: codex exec \"<prompt>\"",
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
            return AICommitTool(rawValue: raw) ?? .cursorAgent
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "GitN.aiCommitTool")
        }
    }

    static var cursorAPIKey: String {
        get {
            UserDefaults.standard.string(forKey: "GitN.cursorAPIKey") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "GitN.cursorAPIKey")
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
        case .cursorAgent:
            return .available
        case .codex:
            return isCodexLoggedIn() ? .available : .loginRequired
        }
    }

    static func toolStatusAsync(_ tool: AICommitTool) async -> AICommitToolStatus {
        guard findExecutablePath(for: tool) != nil else {
            return .unavailable
        }
        switch tool {
        case .cursorAgent:
            return .available
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
        case .cursorAgent:
            return try await runCursorAgent(prompt: prompt)
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
            "\(home)/.cursor/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        return env
    }

    private static func isCodexLoggedIn() -> Bool {
        let proc = Process()
        if let found = findExecutablePath(for: .codex) {
            proc.executableURL = URL(fileURLWithPath: found)
            proc.arguments = ["login", "status"]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "codex login status"]
        }

        proc.environment = makeBaseEnvironment()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return false }
            let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return codexStatusLooksAuthenticated(output: output, errorOutput: errOutput)
        } catch {
            return false
        }
    }

    private static func isCodexLoggedInAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            let proc = Process()
            if let found = findExecutablePath(for: .codex) {
                proc.executableURL = URL(fileURLWithPath: found)
                proc.arguments = ["login", "status"]
            } else {
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", "codex login status"]
            }

            proc.environment = makeBaseEnvironment()
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = FileHandle.nullDevice

            proc.terminationHandler = { process in
                let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isAuthenticated = process.terminationStatus == 0 &&
                    codexStatusLooksAuthenticated(output: output, errorOutput: errOutput)
                continuation.resume(returning: isAuthenticated)
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
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

    private static func runCursorAgent(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()

            // Resolve the effective API key: user setting > environment variable
            let effectiveAPIKey = {
                let stored = cursorAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stored.isEmpty { return stored }
                return ProcessInfo.processInfo.environment["CURSOR_API_KEY"] ?? ""
            }()

            if let found = findExecutablePath(for: .cursorAgent) {
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

            var env = makeBaseEnvironment()
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
                       errMsg.localizedCaseInsensitiveContains("401") ||
                       errMsg.localizedCaseInsensitiveContains("Unauthorized") {
                        continuation.resume(throwing: AICommitError.apiKeyMissing(.cursorAgent))
                    } else {
                        continuation.resume(throwing: AICommitError.agentFailed(.cursorAgent, errMsg))
                    }
                } else if output.isEmpty {
                    continuation.resume(throwing: AICommitError.emptyResponse(.cursorAgent))
                } else {
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: AICommitError.notFound(.cursorAgent))
            }
        }
    }

    private static func runCodex(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let proc = Process()

            if let found = findExecutablePath(for: .codex) {
                proc.executableURL = URL(fileURLWithPath: found)
                proc.arguments = ["exec", "--skip-git-repo-check", prompt]
            } else {
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", "codex exec --skip-git-repo-check \"$1\"", "--", prompt]
            }

            proc.environment = makeBaseEnvironment()

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
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "codex failed"

                    if errMsg.localizedCaseInsensitiveContains("login") ||
                       errMsg.localizedCaseInsensitiveContains("authenticate") ||
                       errMsg.localizedCaseInsensitiveContains("not logged in") ||
                       errMsg.localizedCaseInsensitiveContains("authorization") {
                        continuation.resume(throwing: AICommitError.authorizationRequired(.codex))
                    } else {
                        continuation.resume(throwing: AICommitError.agentFailed(.codex, errMsg))
                    }
                } else if output.isEmpty {
                    continuation.resume(throwing: AICommitError.emptyResponse(.codex))
                } else {
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: AICommitError.notFound(.codex))
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
    case notFound(AICommitTool)
    case apiKeyMissing(AICommitTool)
    case authorizationRequired(AICommitTool)
    case agentFailed(AICommitTool, String)
    case emptyResponse(AICommitTool)

    var errorDescription: String? {
        switch self {
        case .notFound(let tool):
            switch tool {
            case .cursorAgent:
                return "cursor-agent not found. Install it via Cursor IDE or make the CLI available in PATH."
            case .codex:
                return "codex not found. Make sure the `codex` CLI is installed and available in PATH."
            }
        case .apiKeyMissing(let tool):
            return "\(tool.displayName) requires an API key. Configure it in GitN → Settings → AI."
        case .authorizationRequired(let tool):
            switch tool {
            case .cursorAgent:
                return "\(tool.displayName) requires terminal authorization first. Run the login flow in your terminal, then try again."
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

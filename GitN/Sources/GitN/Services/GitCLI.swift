import Foundation

struct GitCLI: Sendable {
    let repoPath: String

    /// Extend PATH so git hooks (e.g. git-lfs pre-push) can find tools installed
    /// in locations not present in a GUI app's default environment.
    static func enrichedEnvironment(extra: [String: String]? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            NSHomeDirectory() + "/.local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }
        if let extra {
            for (key, value) in extra {
                env[key] = value
            }
        }
        return env
    }

    func run(_ args: [String], env: [String: String]? = nil) async throws {
        _ = try await execute(args, env: env, input: nil)
    }

    func output(_ args: [String], env: [String: String]? = nil) async throws -> String {
        let result = try await execute(args, env: env, input: nil)
        return String(data: result.stdout, encoding: .utf8) ?? ""
    }

    func output(_ args: [String], input: String, env: [String: String]? = nil) async throws -> String {
        let result = try await execute(args, env: env, input: input)
        return String(data: result.stdout, encoding: .utf8) ?? ""
    }

    func run(_ args: [String], input: String, env: [String: String]? = nil) async throws {
        _ = try await execute(args, env: env, input: input)
    }

    /// Full result of a captured git invocation: exit code plus raw stdout/stderr
    /// bytes. Used by capturing variants that must record output regardless of the
    /// exit status (operation history, Req 1.5).
    struct CaptureResult: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    /// Run one git command and return its exit code and raw output without throwing
    /// on a non-zero exit. Thin buffered counterpart to `GitStreamingExecutor`,
    /// reusing the same process/pipe/environment setup as `execute`; callers decide
    /// how to treat a non-zero exit. Output bytes are preserved verbatim (no string
    /// decoding here) so non-UTF-8 output is not lost.
    func capture(_ args: [String], env: [String: String]? = nil, input: String? = nil) async throws -> CaptureResult {
        let path = repoPath
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptureResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: path)
                process.environment = Self.enrichedEnvironment(extra: env)

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var stdinPipe: Pipe?
                if input != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    stdinPipe = pipe
                }

                do {
                    try process.run()

                    if let input, let stdinPipe, let data = input.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                        stdinPipe.fileHandleForWriting.closeFile()
                    }

                    // Drain pipes before waitUntilExit to prevent pipe buffer deadlock.
                    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    continuation.resume(returning: CaptureResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func execute(
        _ args: [String],
        env: [String: String]?,
        input: String?
    ) async throws -> (stdout: Data, stderr: Data) {
        let path = repoPath
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(stdout: Data, stderr: Data), Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: path)
                process.environment = Self.enrichedEnvironment(extra: env)

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var stdinPipe: Pipe?
                if input != nil {
                    let pipe = Pipe()
                    process.standardInput = pipe
                    stdinPipe = pipe
                }

                do {
                    try process.run()

                    if let input, let stdinPipe, let data = input.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                        stdinPipe.fileHandleForWriting.closeFile()
                    }

                    // Drain pipes before waitUntilExit to prevent pipe buffer deadlock.
                    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let preferred = stderr.isEmpty ? stdout : stderr
                        let message = String(data: preferred, encoding: .utf8) ?? "git \(args.first ?? "") failed"
                        continuation.resume(throwing: GitError.operationFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        continuation.resume(returning: (stdout, stderr))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

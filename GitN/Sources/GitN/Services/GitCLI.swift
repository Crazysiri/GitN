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
        guard let output = String(data: result.stdout, encoding: .utf8) else {
            throw GitError.operationFailed("git \(args.first ?? "command") produced non-UTF-8 text; read the raw output instead")
        }
        return output
    }

    /// Keep blob bytes intact for callers that decode according to file encoding.
    func outputData(_ args: [String], env: [String: String]? = nil) async throws -> Data {
        try await execute(args, env: env, input: nil).stdout
    }

    func output(_ args: [String], input: String, env: [String: String]? = nil) async throws -> String {
        let result = try await execute(args, env: env, input: input)
        guard let output = String(data: result.stdout, encoding: .utf8) else {
            throw GitError.operationFailed("git \(args.first ?? "command") produced non-UTF-8 text; read the raw output instead")
        }
        return output
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
        try await captureProcess(args, env: env, input: input)
    }

    private func execute(
        _ args: [String],
        env: [String: String]?,
        input: String?
    ) async throws -> (stdout: Data, stderr: Data) {
        let result = try await captureProcess(args, env: env, input: input)
        if result.exitCode != 0 {
            let preferred = result.stderr.isEmpty ? result.stdout : result.stderr
            let message = String(data: preferred, encoding: .utf8) ?? "git \(args.first ?? "") failed"
            throw GitError.operationFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (result.stdout, result.stderr)
    }

    private func captureProcess(
        _ args: [String], env: [String: String]?, input: String?
    ) async throws -> CaptureResult {
        let path = repoPath
        let cancellation = GitCLIProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CaptureResult, Error>) in
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
                    cancellation.setProcess(process)
                    let buffers = GitCLIPipeBuffers()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        buffers.setStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        buffers.setStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                        group.leave()
                    }
                    if let stdinPipe, let input {
                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                            try? stdinPipe.fileHandleForWriting.close()
                            group.leave()
                        }
                    }
                    process.waitUntilExit()
                    group.wait()
                    let result = buffers.result(exitCode: process.terminationStatus)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            }
        } onCancel: {
            cancellation.terminate()
        }
    }
}

private final class GitCLIPipeBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func setStdout(_ data: Data) {
        lock.lock()
        stdout = data
        lock.unlock()
    }

    func setStderr(_ data: Data) {
        lock.lock()
        stderr = data
        lock.unlock()
    }

    func result(exitCode: Int32) -> GitCLI.CaptureResult {
        lock.lock()
        defer { lock.unlock() }
        return GitCLI.CaptureResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}

private final class GitCLIProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func setProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            if process.isRunning { process.terminate() }
        } else {
            self.process = process
        }
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}

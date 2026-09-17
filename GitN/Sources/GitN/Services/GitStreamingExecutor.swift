import Foundation

/// Aggregated result of a streaming git invocation.
///
/// Output is carried as raw `Data` (never decoded to `String` in this layer) so
/// that non-UTF-8 bytes from git / hooks are preserved verbatim. Lossy decoding,
/// if any, happens only at the presentation layer.
struct GitStreamingResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

/// Focused streaming execution path in the `GitCLI` neighborhood.
///
/// Unlike `GitCLI.execute`, which buffers stdout/stderr with `readDataToEndOfFile()`
/// and only returns after `waitUntilExit()`, this executor reads incrementally via
/// `FileHandle.readabilityHandler` and relays each chunk to `onOutput` while the
/// process is still running. This enables real-time display of git progress and
/// git hook output (e.g. `git-lfs pre-push`) for push/pull/fetch.
///
/// Concurrency notes:
/// - The process runs on a background queue.
/// - Both readability handlers funnel through a single serial `sync` queue so the
///   two output streams are appended and forwarded without races; callers are
///   responsible for hopping back to the MainActor inside `onOutput`.
/// - Task cancellation terminates the process; `terminationHandler` still fires,
///   drains residual data, and resumes with whatever output was accumulated.
struct GitStreamingExecutor: Sendable {
    let repoPath: String

    /// Absolute path to the executable to run. Production always uses the git
    /// binary; this is only overridden by tests to drive short-lived shell
    /// commands (e.g. chunked `printf`, `sh -c 'exit N'`) so the streaming and
    /// failure-preservation behavior can be exercised without hitting a real
    /// network or a real git repository. Defaults to `/usr/bin/git`, so all
    /// production call sites keep their exact prior behavior.
    let executablePath: String

    init(repoPath: String) {
        self.repoPath = repoPath
        self.executablePath = "/usr/bin/git"
    }

    /// Test-only initializer allowing an arbitrary executable path. Not used by
    /// production code, which relies on the git-only `init(repoPath:)` above.
    init(repoPath: String, executablePath: String) {
        self.repoPath = repoPath
        self.executablePath = executablePath
    }

    /// Run `git <args>` streaming stdout/stderr incrementally.
    ///
    /// - Parameters:
    ///   - args: git arguments (without the leading `git`).
    ///   - env: extra environment overrides merged into `GitCLI.enrichedEnvironment`.
    ///   - onOutput: invoked on a background serial queue for each stdout/stderr
    ///     chunk. Exactly one of the two parameters is non-nil per call.
    /// - Returns: the aggregated `GitStreamingResult` (non-zero exit still carries
    ///   all accumulated output).
    func stream(
        _ args: [String],
        env: [String: String]? = nil,
        onOutput: @escaping @Sendable (_ stdout: Data?, _ stderr: Data?) -> Void
    ) async throws -> GitStreamingResult {
        let path = repoPath
        let executablePath = self.executablePath

        // Shared process reference so the cancellation handler can terminate it.
        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GitStreamingResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executablePath)
                    process.arguments = args
                    process.currentDirectoryURL = URL(fileURLWithPath: path)
                    // Reuse enrichedEnvironment so git hooks can resolve tools (3.5),
                    // consistent with GitCLI.execute.
                    process.environment = GitCLI.enrichedEnvironment(extra: env)

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe

                    // Serial queue serializes both handler callbacks and mutations of
                    // the accumulation buffers, avoiding cross-stream data races.
                    let sync = DispatchQueue(label: "com.gitn.opstream")
                    var outBuf = Data()
                    var errBuf = Data()

                    outPipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        sync.async {
                            outBuf.append(chunk)
                            onOutput(chunk, nil)
                        }
                    }
                    errPipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        sync.async {
                            errBuf.append(chunk)
                            onOutput(nil, chunk)
                        }
                    }

                    process.terminationHandler = { proc in
                        // Detach handlers and drain any residual buffered data.
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                        let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()

                        sync.async {
                            if !restOut.isEmpty {
                                outBuf.append(restOut)
                                onOutput(restOut, nil)
                            }
                            if !restErr.isEmpty {
                                errBuf.append(restErr)
                                onOutput(nil, restErr)
                            }
                            let result = GitStreamingResult(
                                exitCode: proc.terminationStatus,
                                stdout: outBuf,
                                stderr: errBuf
                            )
                            continuation.resume(returning: result)
                        }
                    }

                    do {
                        try process.run()
                        processBox.setProcess(process)
                    } catch {
                        // run() failed: no terminationHandler will fire, so resolve here.
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            // Task cancellation: terminate the process. The terminationHandler still
            // fires and resumes the continuation with accumulated output (5.2).
            processBox.terminate()
        }
    }
}

/// Thread-safe holder for the running process so the cancellation handler can
/// terminate it even if cancellation races with process startup.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func setProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            // Cancellation arrived before the process was recorded; terminate now.
            if process.isRunning {
                process.terminate()
            }
        } else {
            self.process = process
        }
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

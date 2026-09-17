import XCTest
@testable import GitN

/// Wiring integration tests for the operation-history streaming path.
///
/// **INTEGRATION 3.2** (Requirements 3.1, 3.2, 1.2)
///
/// These tests prove that pushing through the streaming path
/// (`GitStreamingExecutor`) captures a git hook's stdout/stderr into the
/// operation-history output, and that when that streamed output is recorded
/// through `OperationHistoryService` the resulting `OperationLogEntry` retains
/// the hook content along with a terminal result and exit code (1.2).
///
/// The setup is fully local (a bare repo used as `origin`) so no network is
/// required. A `pre-push` hook installed in the working repo prints a
/// recognizable marker to stderr; git runs the hook before contacting the
/// remote, so its output must appear in the streamed `stderr` regardless of the
/// push's ultimate outcome.
///
/// `GitStreamingExecutor` sets the child process environment via
/// `GitCLI.enrichedEnvironment` (PATH extended), so `/bin/sh` in the hook
/// shebang resolves without any extra wiring.
final class OperationHistoryIntegrationTests: XCTestCase {

    /// Recognizable marker the `pre-push` hook writes to stderr.
    private let hookMarker = "GITN_HOOK_MARKER pre-push running"

    // MARK: - INTEGRATION 3.2 (a): executor captures hook output

    /// **Validates: Requirements 3.1, 3.2**
    ///
    /// Driving `GitStreamingExecutor` against a repo that has a `pre-push` hook
    /// and pushing to a local bare remote must surface the hook's stderr in the
    /// aggregated streamed output (and in the collected chunks). This is the core
    /// of INTEGRATION 3.2: the streaming path captures git hook output.
    func testStreamingPushCapturesPrePushHookOutput() async throws {
        let fixture = try PushFixture(hookMarker: hookMarker)
        defer { fixture.cleanup() }

        let recorder = ChunkAggregator()
        let result = try await GitStreamingExecutor(repoPath: fixture.repo.path)
            .stream(["push", "-u", "origin", "HEAD"]) { stdout, stderr in
                recorder.record(stdout: stdout, stderr: stderr)
            }

        // The push to a bare local remote should succeed; either way the hook
        // runs before the transfer, so its marker must be present regardless.
        let aggregatedStderr = String(decoding: result.stderr, as: UTF8.self)
        let aggregatedStdout = String(decoding: result.stdout, as: UTF8.self)
        let combined = aggregatedStdout + aggregatedStderr

        XCTAssertTrue(combined.contains(hookMarker),
            "the aggregated streamed output must contain the pre-push hook marker; got stdout=<\(aggregatedStdout)> stderr=<\(aggregatedStderr)>")

        // The streamed chunks must reconstruct the aggregated buffers verbatim,
        // and the marker must be recoverable from the collected chunks alone.
        let joinedStderr = recorder.stderrData()
        XCTAssertEqual(joinedStderr, result.stderr,
            "concatenated stderr chunks must equal the aggregated stderr buffer")
        let chunkCombined = String(decoding: recorder.stdoutData(), as: UTF8.self)
            + String(decoding: joinedStderr, as: UTF8.self)
        XCTAssertTrue(chunkCombined.contains(hookMarker),
            "the streamed chunks alone must contain the pre-push hook marker")
    }

    // MARK: - INTEGRATION 3.2 (b): recorded entry retains hook output

    /// **Validates: Requirements 3.1, 3.2, 1.2**
    ///
    /// Wiring the streamed output through `OperationHistoryService` (as the
    /// `RepoViewModel` streaming path does) must produce an `OperationLogEntry`
    /// whose captured output contains the hook marker, and whose terminal result
    /// and exit code reflect the finished push (1.2).
    func testStreamingPushRecordsHookOutputInOperationHistory() async throws {
        let fixture = try PushFixture(hookMarker: hookMarker)
        defer { fixture.cleanup() }

        let service = await OperationHistoryService(
            repoContextID: fixture.repo.path,
            store: InMemoryHistoryStore()
        )

        let command = ["git", "push", "-u", "origin", "HEAD"]
        let entryID = await service.beginEntry(kind: .push, command: command)

        // Mirror the RepoViewModel wiring: aggregate streamed chunks as they
        // arrive, then apply them to the entry. Chunks are collected on the
        // executor's serial queue and, since we `await` the result, every
        // callback has executed by the time `stream` returns.
        let recorder = ChunkAggregator()
        let result = try await GitStreamingExecutor(repoPath: fixture.repo.path)
            .stream(["push", "-u", "origin", "HEAD"]) { stdout, stderr in
                recorder.record(stdout: stdout, stderr: stderr)
            }

        // Feed the incrementally collected output into the in-progress entry
        // (as streaming appendOutput would), then finish with the exit code.
        await service.appendOutput(
            entryID,
            stdout: recorder.stdoutData(),
            stderr: recorder.stderrData()
        )
        await service.finish(entryID, exitCode: result.exitCode, captured: nil)

        let entries = await service.state.entries
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return XCTFail("expected a recorded push entry")
        }

        // 1.2: terminal result + exit code recorded.
        XCTAssertTrue(entry.isTerminal, "a finished push entry must be terminal")
        XCTAssertEqual(entry.exitCode, result.exitCode,
            "the recorded exit code must match the process exit status")
        XCTAssertEqual(entry.result, result.exitCode == 0 ? .success : .failure,
            "the recorded result must be derived from the exit code")

        // 3.1/3.2: the hook marker is present in the recorded output.
        let recordedCombined = entry.output.stdoutText + entry.output.stderrText
        XCTAssertTrue(recordedCombined.contains(hookMarker),
            "the recorded operation-log output must contain the pre-push hook marker; got stdout=<\(entry.output.stdoutText)> stderr=<\(entry.output.stderrText)>")
    }
}

// MARK: - Test support

/// Builds a working `TemporaryGitRepository` wired to a local bare remote named
/// `origin`, with an initial commit and an executable `pre-push` hook that
/// prints a marker to stderr. Everything is local so no network is required.
private struct PushFixture {
    let repo: TemporaryGitRepository
    let bareURL: URL

    init(hookMarker: String) throws {
        repo = try TemporaryGitRepository()

        // Create a bare remote in its own temp directory.
        bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitNTests-bare-\(UUID().uuidString).git", isDirectory: true)
        try FileManager.default.createDirectory(at: bareURL, withIntermediateDirectories: true)
        try runGit(["init", "--bare", bareURL.path], in: bareURL.deletingLastPathComponent())

        // Wire origin -> bare remote.
        try repo.run(["remote", "add", "origin", bareURL.path])

        // Initial commit so there is something to push.
        try repo.writeFile("README.md", contents: "GitN push fixture\n")
        try repo.commitAll(message: "initial commit")

        // Install an executable pre-push hook that prints a marker to stderr,
        // following the git convention of writing progress/diagnostics to stderr.
        try installPrePushHook(marker: hookMarker)
    }

    private func installPrePushHook(marker: String) throws {
        let hooksDir = repo.url.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let hookURL = hooksDir.appendingPathComponent("pre-push", isDirectory: false)

        let script = """
        #!/bin/sh
        echo "\(marker)" 1>&2
        exit 0
        """
        try script.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path
        )
    }

    /// Removes the bare remote directory. The working repo cleans itself up via
    /// `TemporaryGitRepository.deinit`.
    func cleanup() {
        try? FileManager.default.removeItem(at: bareURL)
    }

    /// Runs a git command in an arbitrary directory (used only to `git init
    /// --bare` the remote, which lives outside the working repo).
    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(
                decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw NSError(
                domain: "OperationHistoryIntegrationTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " "))\n\(output)"]
            )
        }
    }
}

/// Thread-safe aggregator for the ordered stdout/stderr chunk callbacks the
/// executor delivers on its background serial queue.
private final class ChunkAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func record(stdout: Data?, stderr: Data?) {
        lock.lock()
        defer { lock.unlock() }
        if let stdout { out.append(stdout) }
        if let stderr { err.append(stderr) }
    }

    func stdoutData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return out
    }

    func stderrData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return err
    }
}

/// Minimal in-memory `OperationHistoryStoring` so the service can be exercised
/// without touching Application Support on disk.
private final class InMemoryHistoryStore: OperationHistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OperationLogEntry] = []

    func load() throws -> [OperationLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ entries: [OperationLogEntry]) throws {
        lock.lock()
        defer { lock.unlock() }
        stored = entries
    }
}

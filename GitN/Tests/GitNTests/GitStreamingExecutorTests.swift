import XCTest
@testable import GitN

/// Unit and property-based tests for `GitStreamingExecutor` — the focused
/// streaming execution path that reads a child process's stdout/stderr
/// incrementally via `FileHandle.readabilityHandler` and aggregates the result
/// (Requirements 3.1, 3.2, 3.5, 3.6).
///
/// Feature: git-operation-history-logs, Property 4 / Property 5
///
/// The production `GitStreamingExecutor` hardcodes the git binary. To exercise
/// the incremental-accumulation and failure-preservation behavior deterministically
/// — without a real network or a real git repository — these tests use the
/// test-only `init(repoPath:executablePath:)` initializer to run short-lived
/// `/bin/sh` commands (chunked `printf`, `exit N`). Production streaming behavior
/// for real git operations is unchanged: the git-only `init(repoPath:)` still
/// targets `/usr/bin/git`.
///
/// The repository ships no SwiftCheck / Hypothesis-style property framework and
/// the existing suite is pure XCTest (see `FileInspectorSelectionStateTests`), so
/// each property is realised as a deterministic seeded-RNG loop (≥100 iterations)
/// asserting the invariant on every generated case. The fixed seed keeps failures
/// reproducible.
final class GitStreamingExecutorTests: XCTestCase {

    // MARK: - Helpers

    /// A directory that always exists so `Process.currentDirectoryURL` is valid;
    /// the shell commands under test never touch the filesystem.
    private var scratchDirectory: String { NSTemporaryDirectory() }

    /// Builds an executor that runs `/bin/sh` instead of git, so arbitrary
    /// short-lived shell commands can drive the streaming path.
    private func shellExecutor() -> GitStreamingExecutor {
        GitStreamingExecutor(repoPath: scratchDirectory, executablePath: "/bin/sh")
    }

    /// Runs a `/bin/sh -c <script>` command through the executor, collecting the
    /// ordered sequence of stdout/stderr chunks alongside the aggregated result.
    ///
    /// Chunks are recorded under the executor's own serial queue (via `onOutput`),
    /// then read back here after the awaited result resolves, so no additional
    /// synchronization is required on the test side.
    private func runShell(_ script: String) async throws -> (result: GitStreamingResult, outChunks: [Data], errChunks: [Data]) {
        let recorder = ChunkRecorder()
        let result = try await shellExecutor().stream(["-c", script]) { out, err in
            recorder.record(stdout: out, stderr: err)
        }
        return (result, recorder.stdoutChunks(), recorder.stderrChunks())
    }

    // MARK: - Basic streaming sanity

    /// A simple command's stdout is streamed and aggregated verbatim, and the
    /// concatenation of the streamed chunks equals the aggregated buffer.
    func testStreamsStdoutAndAggregatesVerbatim() async throws {
        let payload = "hello streaming world\n"
        let (result, outChunks, errChunks) = try await runShell("printf '%s' '\(payload)'")

        XCTAssertEqual(result.exitCode, 0, "a successful command must report exit code 0")
        XCTAssertEqual(result.stdout, Data(payload.utf8),
            "aggregated stdout must equal the emitted payload verbatim")
        XCTAssertTrue(result.stderr.isEmpty, "no stderr was emitted")

        let joined = outChunks.reduce(Data(), +)
        XCTAssertEqual(joined, result.stdout,
            "concatenating the streamed stdout chunks must equal the aggregated stdout buffer")
        XCTAssertTrue(errChunks.reduce(Data(), +).isEmpty)
    }

    // MARK: - [PBT] Property 4 — incremental accumulation is split-invariant

    /// **Validates: Requirements 3.1, 3.2**
    /// Feature: git-operation-history-logs, Property 4
    ///
    /// Property: for an arbitrary payload emitted in an arbitrary sequence of
    /// chunks (arbitrary sizes, arbitrarily interleaved across stdout and stderr,
    /// with arbitrary flush boundaries), the executor's aggregated `stdout`/`stderr`
    /// buffers equal the in-order concatenation of the emitted bytes and lose no
    /// bytes. In other words, the accumulation is independent of how the byte
    /// stream is split into chunks.
    ///
    /// The command is a `printf` sequence separated by short `sleep`s so the OS
    /// delivers the bytes across multiple `readabilityHandler` callbacks, which is
    /// exactly the split we assert invariance over.
    func testPBTIncrementalAccumulationIsSplitInvariant() async throws {
        var rng = SeededGenerator(seed: 0x5713_4E33_C0DE_0004)

        for trial in 0..<120 {
            // Build an arbitrary expected stdout and stderr as an ordered list of
            // ASCII segments, then have the shell emit them chunk-by-chunk.
            let segmentCount = Int.random(in: 1...8, using: &rng)
            var stdoutSegments: [String] = []
            var stderrSegments: [String] = []
            var script = ""

            for _ in 0..<segmentCount {
                let segment = randomPrintfSafeSegment(using: &rng)
                // Route each segment to stdout or stderr arbitrarily.
                if Bool.random(using: &rng) {
                    stdoutSegments.append(segment)
                    script += "printf '%s' '\(segment)'; "
                } else {
                    stderrSegments.append(segment)
                    script += "printf '%s' '\(segment)' 1>&2; "
                }
                // Occasionally insert a tiny sleep to force a flush boundary so
                // the bytes arrive across multiple readability callbacks.
                if Bool.random(using: &rng) {
                    script += "sleep 0.005; "
                }
            }

            let expectedStdout = Data(stdoutSegments.joined().utf8)
            let expectedStderr = Data(stderrSegments.joined().utf8)

            let (result, outChunks, errChunks) = try await runShell(script)

            XCTAssertEqual(result.exitCode, 0, "trial \(trial): script must succeed")

            // Aggregated buffers equal the in-order concatenation of expected bytes.
            XCTAssertEqual(result.stdout, expectedStdout,
                "trial \(trial): aggregated stdout must equal the ordered concatenation of emitted segments")
            XCTAssertEqual(result.stderr, expectedStderr,
                "trial \(trial): aggregated stderr must equal the ordered concatenation of emitted segments")

            // The concatenation of the streamed chunks equals the aggregated
            // buffer — regardless of how the OS split the stream — with no byte
            // count change (nothing dropped, nothing duplicated).
            let joinedOut = outChunks.reduce(Data(), +)
            let joinedErr = errChunks.reduce(Data(), +)
            XCTAssertEqual(joinedOut, result.stdout,
                "trial \(trial): concatenated stdout chunks must equal aggregated stdout (split-invariant)")
            XCTAssertEqual(joinedErr, result.stderr,
                "trial \(trial): concatenated stderr chunks must equal aggregated stderr (split-invariant)")
            XCTAssertEqual(joinedOut.count, expectedStdout.count,
                "trial \(trial): no stdout bytes may be lost across chunk boundaries")
            XCTAssertEqual(joinedErr.count, expectedStderr.count,
                "trial \(trial): no stderr bytes may be lost across chunk boundaries")
        }
    }

    // MARK: - [PBT] Property 5 — failure preserves all collected output

    /// **Validates: Requirements 3.1, 3.2, 3.6**
    /// Feature: git-operation-history-logs, Property 5
    ///
    /// Property: when the command fails (non-zero exit), the executor still
    /// returns a `GitStreamingResult` whose `exitCode` is the process's non-zero
    /// status and whose `stdout`/`stderr` retain every byte collected before the
    /// failure. Output emitted prior to a non-zero `exit` is never discarded.
    func testPBTFailurePreservesAllCollectedOutput() async throws {
        var rng = SeededGenerator(seed: 0xBAD0_C0DE_F00D_0005)

        for trial in 0..<120 {
            let stdoutPayload = randomPrintfSafeSegment(using: &rng)
            let stderrPayload = randomPrintfSafeSegment(using: &rng)
            // A non-zero exit status in the POSIX range (1...255).
            let exitStatus = Int.random(in: 1...255, using: &rng)

            // Emit stdout and stderr, force a flush boundary, then fail.
            let script = "printf '%s' '\(stdoutPayload)'; "
                + "printf '%s' '\(stderrPayload)' 1>&2; "
                + "sleep 0.005; "
                + "exit \(exitStatus)"

            let (result, outChunks, errChunks) = try await runShell(script)

            // Non-zero exit code is surfaced (not swallowed).
            XCTAssertNotEqual(result.exitCode, 0,
                "trial \(trial): a failing command must report a non-zero exit code")
            XCTAssertEqual(result.exitCode, Int32(exitStatus),
                "trial \(trial): the reported exit code must match the process's exit status")

            // All output collected before the failure is fully preserved.
            XCTAssertEqual(result.stdout, Data(stdoutPayload.utf8),
                "trial \(trial): stdout collected before the failure must be preserved verbatim")
            XCTAssertEqual(result.stderr, Data(stderrPayload.utf8),
                "trial \(trial): stderr collected before the failure must be preserved verbatim")

            // And the streamed chunks reconstruct the preserved buffers exactly.
            XCTAssertEqual(outChunks.reduce(Data(), +), result.stdout,
                "trial \(trial): streamed stdout chunks must reconstruct the preserved stdout")
            XCTAssertEqual(errChunks.reduce(Data(), +), result.stderr,
                "trial \(trial): streamed stderr chunks must reconstruct the preserved stderr")
        }
    }

    // MARK: - SMOKE 3.5 — process environment uses GitCLI.enrichedEnvironment

    /// **SMOKE 3.5** (Requirements 3.5)
    ///
    /// The executor must set the child process environment via
    /// `GitCLI.enrichedEnvironment`, so git hooks can resolve tools installed in
    /// locations absent from a GUI app's default environment. We assert this by
    /// having the child print its own `PATH` and checking it contains the enriched
    /// entries (e.g. `/opt/homebrew/bin`) that `enrichedEnvironment` injects.
    func testProcessEnvironmentUsesEnrichedEnvironment() async throws {
        let (result, outChunks, _) = try await runShell("printf '%s' \"$PATH\"")

        XCTAssertEqual(result.exitCode, 0, "printing $PATH must succeed")

        let childPath = String(decoding: result.stdout, as: UTF8.self)
        XCTAssertEqual(String(decoding: outChunks.reduce(Data(), +), as: UTF8.self), childPath,
            "streamed chunks must reconstruct the child's PATH output")

        // enrichedEnvironment injects these entries if they are not already present.
        let enrichedPath = GitCLI.enrichedEnvironment()["PATH"] ?? ""
        XCTAssertFalse(enrichedPath.isEmpty, "enrichedEnvironment must define a PATH")

        // The child's PATH must reflect the enriched PATH, not the bare default.
        XCTAssertEqual(childPath, enrichedPath,
            "the child process PATH must match GitCLI.enrichedEnvironment()[PATH]")

        for expectedEntry in ["/opt/homebrew/bin", "/usr/local/bin"] {
            XCTAssertTrue(childPath.contains(expectedEntry),
                "the enriched child PATH must contain \(expectedEntry)")
        }
    }
}

// MARK: - Test support

/// Thread-safe recorder for the ordered chunk callbacks delivered by the
/// executor's `onOutput`, which fires on a background serial queue.
private final class ChunkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var out: [Data] = []
    private var err: [Data] = []

    func record(stdout: Data?, stderr: Data?) {
        lock.lock()
        defer { lock.unlock() }
        if let stdout { out.append(stdout) }
        if let stderr { err.append(stderr) }
    }

    func stdoutChunks() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return out
    }

    func stderrChunks() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return err
    }
}

/// Produces a short segment safe to embed inside a single-quoted `printf '%s'`
/// argument: alphanumerics plus a few benign punctuation characters, with no
/// single quotes, backslashes, or newlines that would break the shell script or
/// be reinterpreted by `printf`.
private func randomPrintfSafeSegment(using rng: inout SeededGenerator) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:-_/=+")
    let length = Int.random(in: 1...48, using: &rng)
    var chars: [Character] = []
    chars.reserveCapacity(length)
    for _ in 0..<length {
        let index = Int.random(in: 0..<alphabet.count, using: &rng)
        chars.append(alphabet[index])
    }
    return String(chars)
}

/// A small deterministic `RandomNumberGenerator` (SplitMix64) making the
/// property-based loops reproducible. The standard library ships no seedable
/// generator, so we provide one locally (mirrors the helper used elsewhere in
/// the test suite).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

import XCTest
@testable import GitN

/// Property-based tests for the focused service layer
/// (`OperationHistoryService` in `Services/OperationHistoryService.swift`).
///
/// The service is `@MainActor`, so the whole test case is annotated `@MainActor`
/// and drives the service directly on the main actor. State is inspected through
/// the observable projection (`service.state.entries` / `service.state.orderedEntries`).
///
/// A fake in-memory `OperationHistoryStoring` double is injected so the tests
/// never touch disk, and an injectable clock closure makes every timestamp
/// deterministic and assertable.
///
/// The repository ships no SwiftCheck / Hypothesis-style property framework and
/// the existing suite is pure XCTest, so each property below is realised as a
/// deterministic seeded-RNG loop (SplitMix64) over ≥100 generated inputs,
/// asserting the invariant on every iteration. The fixed seed keeps failures
/// reproducible. This mirrors `RepoReflogLoaderTests` /
/// `FileInspectorSelectionStateTests`.
@MainActor
final class OperationHistoryServiceTests: XCTestCase {

    // MARK: - [PBT] Property 1 — mutating operations are fully recorded on begin

    /// **Feature: git-operation-history-logs, Property 1**
    ///
    /// **Validates: Requirements 1.1, 1.3**
    ///
    /// Property: beginning a `Mutating_Operation` immediately records a complete
    /// in-progress entry — matching `kind`, `command`, and `repoContextID`, a
    /// `startedAt` sourced from the injected clock, `result == .running`, and no
    /// terminal fields — and grows the history by exactly one.
    ///
    /// Read-only aspect: `GitOperationKind` enumerates only mutating kinds, so a
    /// real read-only kind cannot be constructed here. The "read-only ops are
    /// never recorded" guarantee is asserted via the `isMutating(_:)` classifier
    /// contract — every declared kind classifies as mutating, and read-only
    /// operations (log/status/diff) never enter this enum and therefore never
    /// reach `beginEntry`.
    func testProperty1MutatingOperationsAreRecordedOnBegin() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_0001)

        // Classifier contract: every case the enum can produce is mutating.
        for kind in Self.allKinds {
            XCTAssertTrue(
                OperationHistoryService.isMutating(kind),
                "kind \(kind) must classify as mutating — only mutating kinds exist in GitOperationKind"
            )
        }

        for trial in 0..<200 {
            let contextID = "/tmp/repo-\(trial)"
            let clock = MutableClock(start: Date(timeIntervalSince1970: Double(trial) * 10))
            let store = InMemoryHistoryStore()
            let service = OperationHistoryService(
                repoContextID: contextID,
                store: store,
                clock: clock.now
            )

            let kind = Self.allKinds[Int.random(in: 0..<Self.allKinds.count, using: &rng)]
            let command = randomCommand(using: &rng)
            let expectedStart = clock.current

            let beforeCount = service.state.entries.count
            let id = service.beginEntry(kind: kind, command: command)

            // History grew by exactly one.
            XCTAssertEqual(service.state.entries.count, beforeCount + 1,
                "trial \(trial): a mutating begin must append exactly one entry")

            guard let entry = service.state.entries.first(where: { $0.id == id }) else {
                XCTFail("trial \(trial): begun entry \(id) must be present in history")
                continue
            }

            XCTAssertEqual(entry.kind, kind, "trial \(trial): recorded kind must match")
            XCTAssertEqual(entry.command, command, "trial \(trial): recorded command must match verbatim")
            XCTAssertEqual(entry.repoContextID, contextID, "trial \(trial): entry must be attributed to its repo context")
            XCTAssertEqual(entry.startedAt, expectedStart, "trial \(trial): startedAt must come from the injected clock")
            XCTAssertEqual(entry.result, .running, "trial \(trial): a freshly begun entry is running")
            XCTAssertNil(entry.finishedAt, "trial \(trial): a running entry has no finish time")
            XCTAssertNil(entry.exitCode, "trial \(trial): a running entry has no exit code")
            XCTAssertFalse(entry.isTerminal, "trial \(trial): a running entry is not terminal")
        }
    }

    // MARK: - [PBT] Property 2 — completion semantics are derived from the exit code

    /// **Feature: git-operation-history-logs, Property 2**
    ///
    /// **Validates: Requirements 1.2, 3.4**
    ///
    /// Property: after `finish(exitCode: c)` an entry has `exitCode == c`,
    /// `finishedAt >= startedAt`, and `result == (c == 0 ? .success : .failure)`.
    /// This is verified over BOTH completion paths:
    ///   - the captured-output path (local mutating ops pass their whole
    ///     stdout/stderr once via `finish(captured:)`), and
    ///   - the streaming path (remote ops `appendOutput` incrementally, then
    ///     `finish(captured: nil)` retaining the already-collected output).
    func testProperty2CompletionSemanticsFromExitCode() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_0002)

        for trial in 0..<200 {
            let contextID = "/tmp/repo-\(trial)"
            let clock = MutableClock(start: Date(timeIntervalSince1970: Double(trial) * 10))
            let store = InMemoryHistoryStore()
            let service = OperationHistoryService(
                repoContextID: contextID,
                store: store,
                clock: clock.now
            )

            // Randomly exercise a success (0) or failure (non-zero) exit code.
            let isSuccess = Bool.random(using: &rng)
            let exitCode: Int32 = isSuccess ? 0 : Int32.random(in: 1...255, using: &rng)
            let expectedResult: OperationResult = isSuccess ? .success : .failure

            // Choose which completion path to exercise this trial.
            if Bool.random(using: &rng) {
                // --- Captured-output path (local mutation) ---
                let kind = Self.localKinds[Int.random(in: 0..<Self.localKinds.count, using: &rng)]
                let startedAt = clock.current
                let id = service.beginEntry(kind: kind, command: randomCommand(using: &rng))

                let capturedOut = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
                let capturedErr = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
                let captured = OperationOutput(stdout: capturedOut, stderr: capturedErr)

                clock.advance(by: Double.random(in: 0...5, using: &rng))
                let finishedAt = clock.current
                service.finish(id, exitCode: exitCode, captured: captured)

                guard let entry = service.state.entries.first(where: { $0.id == id }) else {
                    XCTFail("trial \(trial): finished captured entry must exist")
                    continue
                }
                XCTAssertEqual(entry.exitCode, exitCode, "trial \(trial): captured path exit code must match")
                XCTAssertEqual(entry.result, expectedResult, "trial \(trial): captured path result derived from exit code")
                XCTAssertEqual(entry.finishedAt, finishedAt, "trial \(trial): captured path finishedAt from clock")
                XCTAssertGreaterThanOrEqual(entry.finishedAt!, startedAt,
                    "trial \(trial): finishedAt must be >= startedAt")
                XCTAssertTrue(entry.isTerminal, "trial \(trial): a finished entry is terminal")
                XCTAssertEqual(entry.output.stdout, capturedOut, "trial \(trial): captured stdout replaces buffer")
                XCTAssertEqual(entry.output.stderr, capturedErr, "trial \(trial): captured stderr replaces buffer")
            } else {
                // --- Streaming path (append then finish with nil captured) ---
                let kind = Self.streamingKinds[Int.random(in: 0..<Self.streamingKinds.count, using: &rng)]
                let startedAt = clock.current
                let id = service.beginEntry(kind: kind, command: randomCommand(using: &rng))

                // Incrementally stream stdout/stderr in arbitrary chunks.
                let streamedOut = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
                let streamedErr = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
                for chunk in arbitraryChunks(of: streamedOut, using: &rng) {
                    service.appendOutput(id, stdout: chunk, stderr: nil)
                }
                for chunk in arbitraryChunks(of: streamedErr, using: &rng) {
                    service.appendOutput(id, stdout: nil, stderr: chunk)
                }

                clock.advance(by: Double.random(in: 0...5, using: &rng))
                let finishedAt = clock.current
                service.finish(id, exitCode: exitCode, captured: nil)

                guard let entry = service.state.entries.first(where: { $0.id == id }) else {
                    XCTFail("trial \(trial): finished streaming entry must exist")
                    continue
                }
                XCTAssertEqual(entry.exitCode, exitCode, "trial \(trial): streaming path exit code must match")
                XCTAssertEqual(entry.result, expectedResult, "trial \(trial): streaming path result derived from exit code")
                XCTAssertEqual(entry.finishedAt, finishedAt, "trial \(trial): streaming path finishedAt from clock")
                XCTAssertGreaterThanOrEqual(entry.finishedAt!, startedAt,
                    "trial \(trial): finishedAt must be >= startedAt")
                XCTAssertTrue(entry.isTerminal, "trial \(trial): a finished entry is terminal")
                // finish(captured: nil) retains the incrementally streamed output.
                XCTAssertEqual(entry.output.stdout, streamedOut,
                    "trial \(trial): streaming path retains accumulated stdout when captured is nil")
                XCTAssertEqual(entry.output.stderr, streamedErr,
                    "trial \(trial): streaming path retains accumulated stderr when captured is nil")
            }
        }
    }

    // MARK: - [PBT] Property 9 — interruption preserves collected output and marks the interrupted state

    /// **Feature: git-operation-history-logs, Property 9**
    ///
    /// **Validates: Requirements 5.2**
    ///
    /// Property: after `markInterrupted`, an entry has `result == .interrupted`,
    /// a `finishedAt` sourced from the clock, no `exitCode`, and the output
    /// collected up to the point of interruption is preserved byte-for-byte.
    func testProperty9InterruptionPreservesOutputAndMarksInterrupted() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_0009)

        for trial in 0..<200 {
            let contextID = "/tmp/repo-\(trial)"
            let clock = MutableClock(start: Date(timeIntervalSince1970: Double(trial) * 10))
            let store = InMemoryHistoryStore()
            let service = OperationHistoryService(
                repoContextID: contextID,
                store: store,
                clock: clock.now
            )

            // Streaming operations are the ones that can be interrupted mid-flight.
            let kind = Self.streamingKinds[Int.random(in: 0..<Self.streamingKinds.count, using: &rng)]
            let startedAt = clock.current
            let id = service.beginEntry(kind: kind, command: randomCommand(using: &rng))

            // Collect some output before the interruption.
            let collectedOut = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
            let collectedErr = randomBytes(count: Int.random(in: 0...256, using: &rng), using: &rng)
            for chunk in arbitraryChunks(of: collectedOut, using: &rng) {
                service.appendOutput(id, stdout: chunk, stderr: nil)
            }
            for chunk in arbitraryChunks(of: collectedErr, using: &rng) {
                service.appendOutput(id, stdout: nil, stderr: chunk)
            }

            clock.advance(by: Double.random(in: 0...5, using: &rng))
            let interruptedAt = clock.current
            service.markInterrupted(id)

            guard let entry = service.state.entries.first(where: { $0.id == id }) else {
                XCTFail("trial \(trial): interrupted entry must exist")
                continue
            }
            XCTAssertEqual(entry.result, .interrupted, "trial \(trial): result must be .interrupted")
            XCTAssertEqual(entry.finishedAt, interruptedAt, "trial \(trial): interrupt time from clock")
            XCTAssertGreaterThanOrEqual(entry.finishedAt!, startedAt,
                "trial \(trial): interrupt finishedAt must be >= startedAt")
            XCTAssertNil(entry.exitCode, "trial \(trial): an interrupted entry retains no exit code")
            XCTAssertTrue(entry.isTerminal, "trial \(trial): an interrupted entry is terminal")

            // Output collected before the interruption is preserved exactly.
            XCTAssertEqual(entry.output.stdout, collectedOut,
                "trial \(trial): stdout collected before interruption must be preserved")
            XCTAssertEqual(entry.output.stderr, collectedErr,
                "trial \(trial): stderr collected before interruption must be preserved")
        }
    }

    // MARK: - Kind fixtures

    /// Local (captured-output) mutating kinds.
    static let localKinds: [GitOperationKind] = [
        .commit, .merge, .rebase, .checkout, .reset, .stash,
    ]

    /// Streaming (remote/network) mutating kinds.
    static let streamingKinds: [GitOperationKind] = [
        .fetch, .fetchPrune, .pull, .pullFF, .pullRebase, .pullForce,
        .push, .pushForce, .pushTag,
    ]

    /// Every kind the enum can produce (all are mutating).
    static let allKinds: [GitOperationKind] = streamingKinds + localKinds

    // MARK: - Generators

    /// Produces a plausible `git` command line as an argument vector.
    private func randomCommand(using rng: inout SeededGenerator) -> [String] {
        let verbs = ["push", "pull", "fetch", "commit", "merge", "rebase", "checkout", "reset", "stash"]
        let flags = ["--force", "--prune", "--ff-only", "--rebase", "-m", "origin", "main", "HEAD~1"]
        var command = ["git", verbs[Int.random(in: 0..<verbs.count, using: &rng)]]
        for _ in 0..<Int.random(in: 0...4, using: &rng) {
            command.append(flags[Int.random(in: 0..<flags.count, using: &rng)])
        }
        return command
    }

    /// Produces `count` uniformly random bytes.
    private func randomBytes(count: Int, using rng: inout SeededGenerator) -> Data {
        var data = Data(capacity: count)
        for _ in 0..<count {
            data.append(UInt8.random(in: 0...255, using: &rng))
        }
        return data
    }

    /// Splits `data` into an arbitrary sequence of contiguous chunks whose
    /// ordered concatenation equals `data` (may yield empty chunks).
    private func arbitraryChunks(of data: Data, using rng: inout SeededGenerator) -> [Data] {
        var chunks: [Data] = []
        var index = data.startIndex

        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            chunks.append(Data())
        }

        while index < data.endIndex {
            let remaining = data.distance(from: index, to: data.endIndex)
            let take = Int.random(in: 0...remaining, using: &rng)
            let end = data.index(index, offsetBy: take)
            chunks.append(data.subdata(in: index..<end))
            index = end
        }
        return chunks
    }
}

// MARK: - Test doubles

/// An in-memory `OperationHistoryStoring` double so the service never touches
/// disk. `save` simply retains the last snapshot; `load` replays it. Conforms to
/// `Sendable` (final class with locked storage) because the service persists on
/// a detached background task.
private final class InMemoryHistoryStore: OperationHistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OperationLogEntry] = []

    init(initial: [OperationLogEntry] = []) {
        self.stored = initial
    }

    func load() throws -> [OperationLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ entries: [OperationLogEntry]) throws {
        lock.lock(); defer { lock.unlock() }
        stored = entries
    }
}

/// A deterministic, advanceable clock. `now` is passed to the service as its
/// injected clock closure so every recorded timestamp is exact and assertable.
private final class MutableClock {
    private(set) var current: Date

    init(start: Date) {
        self.current = start
    }

    /// Advances the clock by `seconds` and returns the new value.
    @discardableResult
    func advance(by seconds: TimeInterval) -> Date {
        current = current.addingTimeInterval(seconds)
        return current
    }

    /// The closure handed to `OperationHistoryService(clock:)`.
    func now() -> Date { current }
}

/// A small deterministic `RandomNumberGenerator` (SplitMix64) used to make the
/// property-based loops reproducible. The standard library ships no seedable
/// generator, so we provide one locally, matching the pattern in
/// `OperationLogEntryTests` / `FileInspectorSelectionStateTests`.
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

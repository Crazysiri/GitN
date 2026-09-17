import XCTest
@testable import GitN

/// Rendering-field and bypass-invariant tests for `OperationHistoryService` /
/// `OperationHistoryState` (Requirements 4.2, 4.3, 4.4, 4.6, 5.1, 5.4, 2.5).
///
/// These live in a **separate** file from `OperationHistoryServiceTests.swift`
/// (task 3.3) to avoid a write conflict; task 3.4 owns this file exclusively.
///
/// `OperationHistoryService` is `@MainActor`, so the whole suite is annotated
/// `@MainActor`. The repository ships no SwiftCheck / Hypothesis-style property
/// framework and the existing suite is pure XCTest, so each `[PBT]` property is
/// realised as a deterministic seeded-RNG loop (≥100 iterations) that asserts
/// the invariant on every generated case. The fixed seed keeps failures
/// reproducible, mirroring `FileInspectorSelectionStateTests`.
///
/// Feature: git-operation-history-logs
@MainActor
final class OperationHistoryServiceRenderingTests: XCTestCase {

    // MARK: - Property 7: history rendering exposes all required fields

    /// **Validates: Requirements 4.2, 4.3, 4.4**
    ///
    /// Feature: git-operation-history-logs, Property 7
    ///
    /// Property: for arbitrary recorded entries, the row view model exposes a
    /// non-empty type / start-time / result display, and the detail view model
    /// exposes the joined command line, an exit-code display, and stdout/stderr
    /// text that reflects the entry's captured output.
    func testPBTHistoryRenderingIncludesAllRequiredFields() {
        var rng = SeededGenerator(seed: 0x0FE7_7000_0000_0007)

        for trial in 0..<200 {
            let store = SpyStore()
            let service = OperationHistoryService(
                repoContextID: "/tmp/repo-\(trial)",
                store: store,
                clock: { Date() }
            )

            let kind = arbitraryKind(using: &rng)
            let command = arbitraryCommand(kind: kind, using: &rng)
            let id = service.beginEntry(kind: kind, command: command)

            // Optionally stream some output before finishing, so stdout/stderr
            // exercise the non-empty rendering path too.
            let stdoutBytes = arbitraryBytes(using: &rng)
            let stderrBytes = arbitraryBytes(using: &rng)
            if !stdoutBytes.isEmpty || !stderrBytes.isEmpty {
                service.appendOutput(
                    id,
                    stdout: stdoutBytes.isEmpty ? nil : Data(stdoutBytes),
                    stderr: stderrBytes.isEmpty ? nil : Data(stderrBytes)
                )
            }

            // Roughly half the time drive the entry to a terminal state.
            let exitCode = Int32.random(in: 0...5, using: &rng)
            let finishIt = Bool.random(using: &rng)
            if finishIt {
                service.finish(id, exitCode: exitCode, captured: nil)
            }

            let entry = try! XCTUnwrap(
                service.state.entries.first(where: { $0.id == id }),
                "trial \(trial): recorded entry must be present in state"
            )

            let row = service.state.rowViewModel(for: entry)
            XCTAssertFalse(row.kindDisplay.isEmpty,
                "trial \(trial): kindDisplay (type) must be non-empty")
            XCTAssertFalse(row.startedAtDisplay.isEmpty,
                "trial \(trial): startedAtDisplay (start time) must be non-empty")
            XCTAssertFalse(row.resultDisplay.isEmpty,
                "trial \(trial): resultDisplay must be non-empty")

            let detail = service.state.detailViewModel(for: entry)
            XCTAssertEqual(detail.commandLine, command.joined(separator: " "),
                "trial \(trial): commandLine must be the joined full command")
            XCTAssertFalse(detail.exitCodeDisplay.isEmpty,
                "trial \(trial): exitCodeDisplay must be non-empty (placeholder or code)")
            if finishIt {
                XCTAssertEqual(detail.exitCodeDisplay, String(exitCode),
                    "trial \(trial): a finished entry must render its numeric exit code")
            }
            // stdout/stderr text must reflect the entry output (lossy decode).
            XCTAssertEqual(detail.stdoutText, entry.output.stdoutText,
                "trial \(trial): stdoutText must reflect entry output")
            XCTAssertEqual(detail.stderrText, entry.output.stderrText,
                "trial \(trial): stderrText must reflect entry output")
        }
    }

    // MARK: - Property 10: history ordered by time, most recent identifiable

    /// **Validates: Requirements 4.3**
    ///
    /// Feature: git-operation-history-logs, Property 10
    ///
    /// Property: `orderedEntries` is monotonically sorted by `startedAt`. The
    /// implementation sorts **descending** (most recent first), so adjacent
    /// pairs must satisfy `earlier.startedAt >= later.startedAt`, and the head
    /// is the maximum `startedAt` (the most recent, stably identifiable).
    func testPBTOrderedEntriesAreMonotonicallySortedByStartedAtDescending() {
        var rng = SeededGenerator(seed: 0x0DE7_A11_0000_000A)

        for trial in 0..<200 {
            let store = SpyStore()
            // Injected clock returns arbitrary (out-of-order) timestamps so the
            // sort has real work to do rather than trivially-ordered inputs.
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            var pending: [Date] = []
            let count = Int.random(in: 1...40, using: &rng)
            for _ in 0..<count {
                pending.append(base.addingTimeInterval(Double.random(in: -100_000...100_000, using: &rng)))
            }
            var cursor = 0
            let service = OperationHistoryService(
                repoContextID: "/tmp/order-\(trial)",
                store: store,
                clock: {
                    defer { cursor += 1 }
                    return pending[min(cursor, pending.count - 1)]
                }
            )

            for _ in 0..<count {
                _ = service.beginEntry(kind: arbitraryKind(using: &rng), command: ["git", "op"])
            }

            let ordered = service.state.orderedEntries
            XCTAssertEqual(ordered.count, count,
                "trial \(trial): every recorded entry must appear in orderedEntries")

            // Monotonic (descending) by startedAt across adjacent pairs.
            for i in 1..<ordered.count {
                XCTAssertGreaterThanOrEqual(
                    ordered[i - 1].startedAt, ordered[i].startedAt,
                    "trial \(trial): orderedEntries must be sorted by startedAt descending"
                )
            }

            // The head is the most recent (maximum) startedAt.
            let maxStartedAt = try! XCTUnwrap(service.state.entries.map(\.startedAt).max())
            XCTAssertEqual(ordered.first?.startedAt, maxStartedAt,
                "trial \(trial): the first ordered entry must be the most recent")
        }
    }

    // MARK: - Property 8: recording/persistence is a bypass; git result unchanged

    /// **Validates: Requirements 5.1, 5.4**
    ///
    /// Feature: git-operation-history-logs, Property 8
    ///
    /// Property: with a store whose `save()` and `load()` always throw, none of
    /// the mutation entry points (`beginEntry`/`appendOutput`/`finish`/
    /// `markInterrupted`) throw — they are `Void` — and the in-memory history
    /// still retains the entries. Persistence failure is a bypass side effect
    /// and never propagates to the caller.
    func testPBTMutationEntryPointsNeverThrowAndRetainInMemoryHistoryWhenStoreFails() {
        var rng = SeededGenerator(seed: 0x0B7_9A55_0000_0008)

        for trial in 0..<200 {
            let store = AlwaysFailingStore()
            let service = OperationHistoryService(
                repoContextID: "/tmp/bypass-\(trial)",
                store: store,
                clock: { Date() }
            )

            var expectedIDs: [UUID] = []
            let opCount = Int.random(in: 1...25, using: &rng)
            for _ in 0..<opCount {
                let kind = arbitraryKind(using: &rng)
                // beginEntry must not throw (it is Void-returning UUID).
                let id = service.beginEntry(kind: kind, command: ["git", "x"])
                expectedIDs.append(id)

                // Exercise the remaining Void, non-throwing entry points.
                service.appendOutput(id, stdout: Data([0x61]), stderr: nil)
                switch Int.random(in: 0...2, using: &rng) {
                case 0:
                    service.finish(id, exitCode: 0, captured: nil)
                case 1:
                    service.finish(id, exitCode: 1, captured: OperationOutput(stdout: Data([0x62])))
                default:
                    service.markInterrupted(id)
                }
            }

            // In-memory history retained despite every persistence attempt failing.
            XCTAssertEqual(service.state.entries.count, opCount,
                "trial \(trial): all entries must remain in memory when the store fails")
            for id in expectedIDs {
                XCTAssertTrue(service.state.entries.contains(where: { $0.id == id }),
                    "trial \(trial): entry \(id) must be retained in memory")
            }
        }
    }

    // MARK: - EXAMPLE 3.3: appendOutput to a running streaming entry bumps version

    /// **Validates: Requirements 4.6 (version-driven refresh, 3.3)**
    ///
    /// Feature: git-operation-history-logs, Property 7
    ///
    /// EXAMPLE 3.3: appending output to an in-progress streaming entry must
    /// increment `state.version` so SwiftUI observers refresh live.
    func testAppendOutputToRunningStreamingEntryIncrementsStateVersion() {
        let store = SpyStore()
        let service = OperationHistoryService(
            repoContextID: "/tmp/streaming",
            store: store,
            clock: { Date() }
        )

        let id = service.beginEntry(kind: .fetch, command: ["git", "fetch"])
        XCTAssertTrue(GitOperationKind.fetch.isStreaming, "fetch must be a streaming kind")

        let versionBefore = service.state.version
        service.appendOutput(id, stdout: Data("remote: counting\n".utf8), stderr: nil)
        XCTAssertGreaterThan(service.state.version, versionBefore,
            "appendOutput on a running streaming entry must increment state.version")

        // A second append bumps it again (monotonic per streaming chunk).
        let versionMid = service.state.version
        service.appendOutput(id, stdout: nil, stderr: Data("From origin\n".utf8))
        XCTAssertGreaterThan(service.state.version, versionMid,
            "each streaming chunk must further increment state.version")

        // And the entry is still running (not terminal) after appends.
        let entry = try! XCTUnwrap(service.state.entries.first(where: { $0.id == id }))
        XCTAssertEqual(entry.result, .running, "streaming entry must remain running after appendOutput")
    }

    // MARK: - EDGE_CASE 2.5: corrupt store -> empty history, diagnostic, no crash

    /// **Validates: Requirements 2.5, 5.1**
    ///
    /// EDGE_CASE 2.5: when the injected store's `load()` throws
    /// `OperationHistoryStoreError.decodeFailed`, `loadFromDisk()` must leave
    /// the history empty and continue without crashing (a diagnostic is logged).
    func testLoadFromDiskWithCorruptStoreContinuesWithEmptyHistory() async {
        let store = CorruptStore()
        let service = OperationHistoryService(
            repoContextID: "/tmp/corrupt",
            store: store,
            clock: { Date() }
        )

        await service.loadFromDisk()

        XCTAssertTrue(store.loadWasCalled, "loadFromDisk must attempt to read the store")
        XCTAssertTrue(service.state.isEmpty,
            "a corrupt store must result in an empty in-memory history")
        XCTAssertEqual(service.state.entries.count, 0,
            "no entries should be loaded from a corrupt store")

        // Service remains usable after a corrupt load (no crash, still records).
        let id = service.beginEntry(kind: .commit, command: ["git", "commit"])
        XCTAssertTrue(service.state.entries.contains(where: { $0.id == id }),
            "service must remain usable and record entries after a corrupt load")
    }

    // MARK: - Generators

    private func arbitraryKind(using rng: inout SeededGenerator) -> GitOperationKind {
        let all: [GitOperationKind] = [
            .fetch, .fetchPrune, .pull, .pullFF, .pullRebase, .pullForce,
            .push, .pushForce, .pushTag,
            .commit, .merge, .rebase, .checkout, .reset, .stash
        ]
        return all[Int.random(in: 0..<all.count, using: &rng)]
    }

    private func arbitraryCommand(kind: GitOperationKind, using rng: inout SeededGenerator) -> [String] {
        var command = ["git"]
        let argCount = Int.random(in: 1...4, using: &rng)
        for _ in 0..<argCount {
            let token = ["fetch", "pull", "push", "--force", "origin", "main", "HEAD~1", "--prune"]
            command.append(token[Int.random(in: 0..<token.count, using: &rng)])
        }
        return command
    }

    /// Produces an arbitrary byte buffer (possibly empty, possibly non-UTF-8).
    private func arbitraryBytes(using rng: inout SeededGenerator) -> [UInt8] {
        let length = Int.random(in: 0...16, using: &rng)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(length)
        for _ in 0..<length {
            bytes.append(UInt8.random(in: 0...255, using: &rng))
        }
        return bytes
    }
}

// MARK: - Test doubles

/// A store that records interactions and behaves like an empty on-disk history.
private final class SpyStore: OperationHistoryStoring, @unchecked Sendable {
    func load() throws -> [OperationLogEntry] { [] }
    func save(_ entries: [OperationLogEntry]) throws {}
}

/// A store whose `save()` and `load()` always throw, used to prove the
/// recording layer is a bypass (Property 8 / Req 5.4).
private struct AlwaysFailingStore: OperationHistoryStoring {
    struct InjectedFailure: Error {}
    func load() throws -> [OperationLogEntry] { throw InjectedFailure() }
    func save(_ entries: [OperationLogEntry]) throws { throw InjectedFailure() }
}

/// A store whose `load()` throws a recognizable decode error (EDGE_CASE 2.5).
private final class CorruptStore: OperationHistoryStoring, @unchecked Sendable {
    private(set) var loadWasCalled = false
    struct Corruption: Error {}
    func load() throws -> [OperationLogEntry] {
        loadWasCalled = true
        throw OperationHistoryStoreError.decodeFailed(underlying: Corruption())
    }
    func save(_ entries: [OperationLogEntry]) throws {}
}

/// A small deterministic `RandomNumberGenerator` (SplitMix64) used to make the
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

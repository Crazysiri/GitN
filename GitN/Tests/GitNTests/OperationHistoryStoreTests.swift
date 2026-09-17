import XCTest
@testable import GitN

/// Unit and property-based tests for `OperationHistoryStore` — the per-Repo
/// JSON persistence layer for git operation history (Requirements 1.4, 2.1,
/// 2.2, 2.3, 4.5).
///
/// These tests exercise the store directly against real temporary files via
/// the `init(fileURL:)` initializer, so each store instance points at an
/// isolated file under `FileManager.default.temporaryDirectory`. Temp files are
/// cleaned up in `tearDown`.
///
/// The repository ships no SwiftCheck / Hypothesis-style property framework and
/// the existing suite is pure XCTest, so the property below is realised as a
/// deterministic seeded-RNG loop over many generated event sequences, asserting
/// the invariant on every iteration. The fixed seed keeps failures reproducible.
///
/// Note: `OperationLogEntry.output` stores stdout/stderr as `Data` (encoded as
/// base64 in JSON), so the round-trip must be byte-for-byte identical.
///
/// Tag: Feature: git-operation-history-logs, Property 3
final class OperationHistoryStoreTests: XCTestCase {

    // MARK: - Temp directory lifecycle

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OperationHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeStore(named name: String = UUID().uuidString) -> OperationHistoryStore {
        let fileURL = tempDirectory.appendingPathComponent("\(name).json", isDirectory: false)
        return OperationHistoryStore(fileURL: fileURL)
    }

    // MARK: - Example: simple round-trip

    /// A saved-then-loaded entry list is field-for-field equal, including the
    /// raw stdout/stderr bytes (R2.1, R2.3).
    func testSaveThenLoadRoundTripsEntriesFieldForField() throws {
        let store = makeStore()
        let entries = [
            makeEntry(repoContextID: "/repo/a", kindIndex: 0, byteSeed: 1),
            makeEntry(repoContextID: "/repo/a", kindIndex: 3, byteSeed: 2)
        ]

        try store.save(entries)
        let loaded = try store.load()

        XCTAssertEqual(loaded, entries, "loaded entries must equal saved entries field-for-field")
        for (saved, roundTripped) in zip(entries, loaded) {
            XCTAssertEqual(roundTripped.output.stdout, saved.output.stdout,
                "stdout bytes must round-trip byte-for-byte")
            XCTAssertEqual(roundTripped.output.stderr, saved.output.stderr,
                "stderr bytes must round-trip byte-for-byte")
        }
    }

    // MARK: - [PBT] Property 3: per-Repo round-trip and isolation

    /// **Validates: Requirements 1.4, 2.1, 2.2, 2.3, 4.5**
    ///
    /// Property: two distinct Repo_Contexts, each backed by its own store file,
    /// can each write an arbitrary sequence of events. Loading each store from
    /// disk yields exactly the entries written for that Repo_Context — equal
    /// field-for-field (including raw output bytes) — and neither store contains
    /// any entry belonging to the other.
    ///
    /// Implemented as a deterministic seeded-RNG loop (no external PBT framework
    /// available); the invariant is asserted on every generated case (≥100
    /// iterations).
    func testPBTPerRepoRoundTripAndIsolation() throws {
        var rng = SeededGenerator(seed: 0x0FE7_A710_1015_7003)

        for trial in 0..<200 {
            // Fresh, isolated stores per trial so state never leaks across trials.
            let storeA = makeStore(named: "repoA-\(trial)")
            let storeB = makeStore(named: "repoB-\(trial)")

            let repoContextA = "/tmp/repoA/\(trial)"
            let repoContextB = "/tmp/repoB/\(trial)"

            let entriesA = makeArbitraryEntries(repoContextID: repoContextA, using: &rng)
            let entriesB = makeArbitraryEntries(repoContextID: repoContextB, using: &rng)

            try storeA.save(entriesA)
            try storeB.save(entriesB)

            let loadedA = try storeA.load()
            let loadedB = try storeB.load()

            // Round-trip: each store yields its own entries, field-for-field.
            XCTAssertEqual(loadedA, entriesA,
                "trial \(trial): repo A must round-trip its own entries field-for-field")
            XCTAssertEqual(loadedB, entriesB,
                "trial \(trial): repo B must round-trip its own entries field-for-field")

            // Byte-for-byte output check (base64 round-trip through JSON).
            for (saved, loaded) in zip(entriesA, loadedA) {
                XCTAssertEqual(loaded.output.stdout, saved.output.stdout,
                    "trial \(trial): repo A stdout bytes must round-trip byte-for-byte")
                XCTAssertEqual(loaded.output.stderr, saved.output.stderr,
                    "trial \(trial): repo A stderr bytes must round-trip byte-for-byte")
            }
            for (saved, loaded) in zip(entriesB, loadedB) {
                XCTAssertEqual(loaded.output.stdout, saved.output.stdout,
                    "trial \(trial): repo B stdout bytes must round-trip byte-for-byte")
                XCTAssertEqual(loaded.output.stderr, saved.output.stderr,
                    "trial \(trial): repo B stderr bytes must round-trip byte-for-byte")
            }

            // Isolation: neither store contains any of the other's entry ids,
            // and every loaded entry carries only its own Repo_Context id.
            let idsA = Set(loadedA.map(\.id))
            let idsB = Set(loadedB.map(\.id))
            XCTAssertTrue(idsA.isDisjoint(with: idsB),
                "trial \(trial): the two stores must not share any entry ids")

            for entry in loadedA {
                XCTAssertEqual(entry.repoContextID, repoContextA,
                    "trial \(trial): repo A store must only contain repo A entries")
                XCTAssertFalse(idsB.contains(entry.id),
                    "trial \(trial): repo A store must not contain any repo B entry")
            }
            for entry in loadedB {
                XCTAssertEqual(entry.repoContextID, repoContextB,
                    "trial \(trial): repo B store must only contain repo B entries")
                XCTAssertFalse(idsA.contains(entry.id),
                    "trial \(trial): repo B store must not contain any repo A entry")
            }
        }
    }

    // MARK: - Generators

    private let allKinds: [GitOperationKind] = [
        .fetch, .fetchPrune, .pull, .pullFF, .pullRebase, .pullForce,
        .push, .pushForce, .pushTag,
        .commit, .merge, .rebase, .checkout, .reset, .stash
    ]

    private let allResults: [OperationResult] = [.running, .success, .failure, .interrupted]

    /// Deterministic entry builder used by the example test.
    private func makeEntry(repoContextID: String, kindIndex: Int, byteSeed: UInt8) -> OperationLogEntry {
        var output = OperationOutput()
        output.appendStdout(Data([byteSeed, byteSeed &+ 1, 0x00, 0xFF]))
        output.appendStderr(Data([byteSeed &+ 2, 0x80]))
        return OperationLogEntry(
            id: UUID(),
            kind: allKinds[kindIndex % allKinds.count],
            command: ["git", "op", "\(byteSeed)"],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_010),
            exitCode: 0,
            result: .success,
            output: output,
            repoContextID: repoContextID
        )
    }

    /// Builds an arbitrary-length sequence of arbitrary entries for a single
    /// Repo_Context using the seeded RNG.
    private func makeArbitraryEntries(
        repoContextID: String,
        using rng: inout SeededGenerator
    ) -> [OperationLogEntry] {
        let count = Int.random(in: 0...12, using: &rng)
        return (0..<count).map { _ in makeArbitraryEntry(repoContextID: repoContextID, using: &rng) }
    }

    private func makeArbitraryEntry(
        repoContextID: String,
        using rng: inout SeededGenerator
    ) -> OperationLogEntry {
        let kind = allKinds[Int.random(in: 0..<allKinds.count, using: &rng)]
        let result = allResults[Int.random(in: 0..<allResults.count, using: &rng)]

        // Arbitrary command tokens.
        let argCount = Int.random(in: 0...5, using: &rng)
        var command = ["git"]
        for _ in 0..<argCount {
            command.append(randomToken(using: &rng))
        }

        // Arbitrary timestamps.
        let start = Date(timeIntervalSince1970: Double(Int.random(in: 0...2_000_000_000, using: &rng)))
        let hasFinished = Bool.random(using: &rng)
        let finishedAt = hasFinished
            ? start.addingTimeInterval(Double(Int.random(in: 0...10_000, using: &rng)))
            : nil
        let exitCode: Int32? = hasFinished
            ? Int32(Int.random(in: -1...255, using: &rng))
            : nil

        // Arbitrary raw output bytes, including non-UTF-8 bytes, to stress the
        // base64 round-trip.
        var output = OperationOutput()
        output.appendStdout(randomBytes(using: &rng))
        output.appendStderr(randomBytes(using: &rng))

        return OperationLogEntry(
            id: UUID(),
            kind: kind,
            command: command,
            startedAt: start,
            finishedAt: finishedAt,
            exitCode: exitCode,
            result: result,
            output: output,
            repoContextID: repoContextID
        )
    }

    private func randomToken(using rng: inout SeededGenerator) -> String {
        let length = Int.random(in: 0...8, using: &rng)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789-/.")
        var token = ""
        for _ in 0..<length {
            token.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)])
        }
        return token
    }

    /// Arbitrary bytes including values that are not valid UTF-8, exercising the
    /// byte-preserving (base64) persistence path.
    private func randomBytes(using rng: inout SeededGenerator) -> Data {
        let length = Int.random(in: 0...32, using: &rng)
        var bytes = [UInt8]()
        bytes.reserveCapacity(length)
        for _ in 0..<length {
            bytes.append(UInt8(Int.random(in: 0...255, using: &rng)))
        }
        return Data(bytes)
    }
}

/// A small deterministic `RandomNumberGenerator` (SplitMix64) used to make the
/// property-based loop reproducible. The standard library ships no seedable
/// generator, so we provide one locally for the tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero state, which would weaken the mixing.
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

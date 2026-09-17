import XCTest
@testable import GitN

/// Property-based tests for the pure operation-log data models
/// (`OperationOutput` / `OperationLogEntry` / `GitOperationKind` /
/// `OperationResult`) defined in `Models/OperationLogEntry.swift`.
///
/// These are plain value types with no I/O or SwiftUI dependencies, so the
/// tests exercise them directly and MUST NOT instantiate any SwiftUI view
/// bodies or perform disk access.
///
/// The repository ships no SwiftCheck / Hypothesis-style property framework and
/// the existing suite is pure XCTest, so each property below is realised as a
/// deterministic seeded-RNG loop (SplitMix64) over ≥100 generated inputs,
/// asserting the invariant on every iteration. The fixed seed keeps failures
/// reproducible. This mirrors `FileInspectorSelectionStateTests`.
final class OperationLogEntryTests: XCTestCase {

    // MARK: - [PBT] Property 4 — streaming incremental accumulation is chunking-independent

    /// **Feature: git-operation-history-logs, Property 4**
    ///
    /// **Validates: Requirements 3.1, 3.2**
    ///
    /// Property: appending a byte stream to `OperationOutput` via any arbitrary
    /// partition into `appendStdout`/`appendStderr` chunks yields the same
    /// accumulated buffer as concatenating the whole stream in order. In other
    /// words the incremental accumulation is independent of how the underlying
    /// stream happens to be sliced by the streaming executor.
    func testProperty4StreamingAccumulationIsChunkingIndependent() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_0004)

        for trial in 0..<400 {
            // Build the authoritative expected streams for stdout and stderr.
            let stdoutBytes = randomBytes(count: Int.random(in: 0...4_096, using: &rng), using: &rng)
            let stderrBytes = randomBytes(count: Int.random(in: 0...4_096, using: &rng), using: &rng)

            // Slice each stream into an arbitrary sequence of chunks (including
            // possible empty chunks) and append them in order.
            var output = OperationOutput()
            for chunk in arbitraryChunks(of: stdoutBytes, using: &rng) {
                output.appendStdout(chunk)
            }
            for chunk in arbitraryChunks(of: stderrBytes, using: &rng) {
                output.appendStderr(chunk)
            }

            XCTAssertEqual(output.stdout, stdoutBytes,
                "trial \(trial): stdout accumulation must equal the ordered concatenation regardless of chunking")
            XCTAssertEqual(output.stderr, stderrBytes,
                "trial \(trial): stderr accumulation must equal the ordered concatenation regardless of chunking")

            // A second, differently-sliced accumulation of the same streams must
            // produce a value equal to the first — accumulation depends only on
            // the byte order, not on the partition.
            var reslicedOutput = OperationOutput()
            for chunk in arbitraryChunks(of: stdoutBytes, using: &rng) {
                reslicedOutput.appendStdout(chunk)
            }
            for chunk in arbitraryChunks(of: stderrBytes, using: &rng) {
                reslicedOutput.appendStderr(chunk)
            }
            XCTAssertEqual(reslicedOutput, output,
                "trial \(trial): two arbitrary chunkings of the same streams must accumulate to equal outputs")
        }
    }

    /// A single-shot append and a byte-by-byte append of the same stream must
    /// yield identical buffers — the extreme ends of the chunking spectrum.
    func testProperty4SingleShotEqualsByteByByte() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_1004)

        for trial in 0..<200 {
            let bytes = randomBytes(count: Int.random(in: 0...512, using: &rng), using: &rng)

            var whole = OperationOutput()
            whole.appendStdout(bytes)

            var perByte = OperationOutput()
            for byte in bytes {
                perByte.appendStdout(Data([byte]))
            }

            XCTAssertEqual(whole.stdout, bytes, "trial \(trial): single-shot append must preserve all bytes")
            XCTAssertEqual(perByte.stdout, bytes, "trial \(trial): byte-by-byte append must preserve all bytes")
            XCTAssertEqual(whole, perByte, "trial \(trial): single-shot and byte-by-byte must be equal")
        }
    }

    // MARK: - [PBT] Property 6 — non-UTF-8 bytes are preserved and never crash

    /// **Feature: git-operation-history-logs, Property 6**
    ///
    /// **Validates: Requirements 3.1, 3.2, 5.3**
    ///
    /// Property: `OperationOutput` stores raw bytes, so `Data` containing
    /// invalid UTF-8 sequences is preserved byte-for-byte (no record is lost or
    /// mutated), and the lossy `stdoutText`/`stderrText` decoding views never
    /// crash. Additionally a full `OperationLogEntry` round-trips through JSON
    /// `Codable` without losing the non-UTF-8 bytes.
    func testProperty6NonUTF8BytesArePreservedAndDecodingIsSafe() {
        var rng = SeededGenerator(seed: 0x0A11_C0DE_5EED_0006)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for trial in 0..<400 {
            let outBytes = bytesContainingInvalidUTF8(using: &rng)
            let errBytes = bytesContainingInvalidUTF8(using: &rng)

            var output = OperationOutput()
            // Append via arbitrary chunking to also exercise the streaming path
            // with non-UTF-8 data straddling chunk boundaries.
            for chunk in arbitraryChunks(of: outBytes, using: &rng) {
                output.appendStdout(chunk)
            }
            for chunk in arbitraryChunks(of: errBytes, using: &rng) {
                output.appendStderr(chunk)
            }

            // Raw bytes are preserved exactly — nothing is dropped or altered.
            XCTAssertEqual(output.stdout, outBytes,
                "trial \(trial): invalid-UTF-8 stdout bytes must be preserved exactly")
            XCTAssertEqual(output.stderr, errBytes,
                "trial \(trial): invalid-UTF-8 stderr bytes must be preserved exactly")

            // Lossy decoding must not crash and must be non-nil for any input.
            let stdoutText = output.stdoutText
            let stderrText = output.stderrText
            XCTAssertEqual(stdoutText, String(decoding: outBytes, as: UTF8.self),
                "trial \(trial): stdoutText must be the lossy UTF-8 decode of the raw bytes")
            XCTAssertEqual(stderrText, String(decoding: errBytes, as: UTF8.self),
                "trial \(trial): stderrText must be the lossy UTF-8 decode of the raw bytes")

            // Full entry Codable round-trip preserves the non-UTF-8 bytes.
            let entry = OperationLogEntry(
                id: UUID(),
                kind: .push,
                command: ["git", "push", "origin", "main"],
                startedAt: Date(timeIntervalSince1970: Double(trial)),
                finishedAt: Date(timeIntervalSince1970: Double(trial) + 1),
                exitCode: 0,
                result: .success,
                output: output,
                repoContextID: "/tmp/repo-\(trial)"
            )

            do {
                let data = try encoder.encode(entry)
                let decoded = try decoder.decode(OperationLogEntry.self, from: data)
                XCTAssertEqual(decoded, entry,
                    "trial \(trial): entry must round-trip through JSON without losing non-UTF-8 bytes")
                XCTAssertEqual(decoded.output.stdout, outBytes,
                    "trial \(trial): decoded stdout must retain the exact raw bytes")
                XCTAssertEqual(decoded.output.stderr, errBytes,
                    "trial \(trial): decoded stderr must retain the exact raw bytes")
            } catch {
                XCTFail("trial \(trial): Codable round-trip must not throw, got \(error)")
            }
        }
    }

    // MARK: - Generators

    /// Produces `count` uniformly random bytes.
    private func randomBytes(count: Int, using rng: inout SeededGenerator) -> Data {
        var data = Data(capacity: count)
        for _ in 0..<count {
            data.append(UInt8.random(in: 0...255, using: &rng))
        }
        return data
    }

    /// Splits `data` into an arbitrary sequence of contiguous chunks whose
    /// ordered concatenation equals `data`. May yield empty chunks and, for
    /// empty input, an arbitrary run of empty chunks — all valid partitions.
    private func arbitraryChunks(of data: Data, using rng: inout SeededGenerator) -> [Data] {
        var chunks: [Data] = []
        var index = data.startIndex

        // Occasionally emit leading empty chunks to stress boundary handling.
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

    /// Builds a `Data` blob that is guaranteed to contain at least one invalid
    /// UTF-8 byte sequence, interleaved with valid ASCII/multibyte content, so
    /// the lossy decode path is genuinely exercised.
    private func bytesContainingInvalidUTF8(using rng: inout SeededGenerator) -> Data {
        var data = Data()

        // Some valid ASCII/UTF-8 lead-in.
        let ascii = "commit ".utf8
        data.append(contentsOf: ascii)

        // Guaranteed invalid sequences: lone continuation bytes and truncated
        // multibyte leads are never valid UTF-8.
        let invalidPatterns: [[UInt8]] = [
            [0x80],             // lone continuation byte
            [0xC0, 0x80],       // overlong / invalid 2-byte
            [0xE0, 0x80],       // truncated 3-byte lead
            [0xF5],             // out-of-range 4-byte lead
            [0xFF, 0xFE],       // never-valid bytes
            [0xED, 0xA0, 0x80], // UTF-16 surrogate encoded as UTF-8 (invalid)
        ]
        let pattern = invalidPatterns[Int.random(in: 0..<invalidPatterns.count, using: &rng)]
        data.append(contentsOf: pattern)

        // Some more random bytes (which themselves may be valid or invalid).
        let tailCount = Int.random(in: 0...64, using: &rng)
        for _ in 0..<tailCount {
            data.append(UInt8.random(in: 0...255, using: &rng))
        }

        // Trailing valid UTF-8 to ensure invalid bytes appear mid-stream.
        data.append(contentsOf: "✓ done".utf8)
        return data
    }
}

/// A small deterministic `RandomNumberGenerator` (SplitMix64) used to make the
/// property-based loops reproducible. The standard library ships no seedable
/// generator, so we provide one locally for the tests, matching the pattern in
/// `FileInspectorSelectionStateTests`.
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

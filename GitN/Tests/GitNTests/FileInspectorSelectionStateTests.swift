import XCTest
@testable import GitN

/// Unit and property-based tests for `FileInspectorSelectionState` — the pure
/// generation-token value type that gates which asynchronous diff/preview load
/// is allowed to write back into the file inspector (Requirements 3.2, 3.6, 3.7).
///
/// `FileInspectorSelectionState` is a plain value type with no SwiftUI or
/// service dependencies, so these tests exercise it directly and MUST NOT
/// instantiate any SwiftUI view bodies.
///
/// The repository ships no SwiftCheck / Hypothesis-style property framework and
/// the existing suite is pure XCTest, so the `[PBT]` property below is realised
/// as a deterministic seeded-RNG loop over many generated token sequences,
/// asserting the invariant on every iteration. The fixed seed keeps failures
/// reproducible.
final class FileInspectorSelectionStateTests: XCTestCase {

    // MARK: - beginSelection strict monotonicity

    /// `beginSelection()` must return a strictly larger token on every call so
    /// later selections always supersede earlier ones (R3.2).
    func testBeginSelectionIsStrictlyMonotonicallyIncreasing() {
        var state = FileInspectorSelectionState()
        XCTAssertEqual(state.generation, 0, "generation should start at zero before any selection")

        var previous = state.generation
        for _ in 0..<10_000 {
            let token = state.beginSelection()
            XCTAssertGreaterThan(token, previous,
                "each beginSelection() call must return a value strictly greater than the previous token")
            XCTAssertEqual(token, state.generation,
                "beginSelection() must return the same value it stored as the current generation")
            previous = token
        }
    }

    // MARK: - Only the most recent token can apply

    /// After a run of consecutive `beginSelection()` calls, only the most recent
    /// token is applicable; every prior token is stale and must be rejected (R3.6).
    func testOnlyMostRecentTokenCanApplyAfterConsecutiveBeginSelections() {
        var state = FileInspectorSelectionState()
        var tokens: [Int] = []
        for _ in 0..<500 {
            tokens.append(state.beginSelection())
        }

        let mostRecent = try! XCTUnwrap(tokens.last)
        XCTAssertTrue(state.canApply(token: mostRecent),
            "the most recent token must be applicable")

        for stale in tokens.dropLast() {
            XCTAssertFalse(state.canApply(token: stale),
                "every token prior to the most recent must be rejected as stale")
        }
    }

    /// A token captured before a later selection becomes stale the moment the
    /// next `beginSelection()` runs — the classic rapid-re-selection race (R3.6).
    func testEarlierTokenBecomesInapplicableAfterNextSelection() {
        var state = FileInspectorSelectionState()
        let first = state.beginSelection()
        XCTAssertTrue(state.canApply(token: first),
            "a freshly issued token must be applicable before any newer selection")

        let second = state.beginSelection()
        XCTAssertFalse(state.canApply(token: first),
            "the earlier token must stop being applicable once a newer selection begins")
        XCTAssertTrue(state.canApply(token: second),
            "the newer token must be applicable")
    }

    // MARK: - [PBT] canApply(token) <=> token == generation

    /// **Validates: Requirements 3.2, 3.6, 3.7**
    ///
    /// Property: for an arbitrary sequence of selections and arbitrary probe
    /// tokens, `canApply(token)` is true **if and only if** `token` equals the
    /// current `generation`. Equivalently: only the live token applies, and any
    /// older/stale (or otherwise-unequal) token is never applicable.
    ///
    /// Implemented as a deterministic seeded-RNG loop (no external PBT
    /// framework available); the invariant is asserted on every generated case.
    func testPBTCanApplyHoldsIffTokenEqualsCurrentGeneration() {
        var rng = SeededGenerator(seed: 0xF11E_5E1E_C710_0001)

        for trial in 0..<2_000 {
            var state = FileInspectorSelectionState()
            var issuedTokens: [Int] = []

            // Drive an arbitrary-length run of selections, validating the
            // invariant after every individual begin (interleaved checks).
            let selectionCount = Int.random(in: 1...60, using: &rng)
            for _ in 0..<selectionCount {
                let token = state.beginSelection()
                issuedTokens.append(token)

                // The just-issued token is, by definition, the live one.
                XCTAssertTrue(state.canApply(token: token),
                    "trial \(trial): the token just returned by beginSelection() must be applicable")
                XCTAssertEqual(state.canApply(token: token), token == state.generation,
                    "trial \(trial): canApply must agree with (token == generation) for the live token")
            }

            let generation = state.generation

            // Every token ever issued in this trial: applicable iff it equals
            // the current generation (i.e. only the final one).
            for token in issuedTokens {
                XCTAssertEqual(state.canApply(token: token), token == generation,
                    "trial \(trial): canApply(\(token)) must equal (\(token) == \(generation))")
            }

            // Arbitrary probe tokens — including negatives, zero, the boundary
            // values around the live generation, and far-future values — must
            // obey the same biconditional. This stresses the "iff" in both
            // directions across the whole input space, not just issued tokens.
            for _ in 0..<40 {
                let probe = arbitraryProbeToken(generation: generation, using: &rng)
                XCTAssertEqual(state.canApply(token: probe), probe == generation,
                    "trial \(trial): canApply(\(probe)) must be true iff \(probe) == generation \(generation)")
            }
        }
    }

    /// Produces a probe token spanning the interesting parts of the input space:
    /// stale low values, the boundary neighbours of the live generation, the
    /// live generation itself, and far-future values that were never issued.
    private func arbitraryProbeToken(generation: Int, using rng: inout SeededGenerator) -> Int {
        switch Int.random(in: 0...6, using: &rng) {
        case 0: return generation              // exact live token
        case 1: return generation - 1          // immediately stale
        case 2: return generation + 1          // never-issued future token
        case 3: return 0                       // pre-selection sentinel
        case 4: return Int.random(in: -1_000_000 ... -1, using: &rng)   // negative
        case 5: return Int.random(in: 1...max(1, generation), using: &rng) // some issued/stale value
        default: return Int.random(in: (generation + 1)...(generation + 1_000_000), using: &rng) // far future
        }
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

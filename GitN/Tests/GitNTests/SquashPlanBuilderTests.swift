import XCTest
@testable import GitN

/// Unit and property-based tests for `SquashPlanBuilder` / `SquashPlan` —
/// the pure in-memory rebase-todo generator (Requirements 4.1–4.3, 4.7, 4.9).
///
/// None of these tests instantiate SwiftUI view bodies or spawn a git process.
/// All invariants are exercised directly on the pure value types.
final class SquashPlanBuilderTests: XCTestCase {

    // MARK: - Fixed test cases (R4.9)

    // Test 1: Contiguous selection from the oldest end
    func testContiguousSelectionFromOldest() throws {
        // range: H1(oldest) … H6(HEAD)
        let range = ["H1", "H2", "H3", "H4", "H5", "H6"]
        let selected: Set<String> = ["H1", "H2", "H3"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "H1")
        XCTAssertEqual(plan.todo, [
            SquashTodoLine(action: .pick,   hash: "H1"),
            SquashTodoLine(action: .squash, hash: "H2"),
            SquashTodoLine(action: .squash, hash: "H3"),
            SquashTodoLine(action: .pick,   hash: "H4"),
            SquashTodoLine(action: .pick,   hash: "H5"),
            SquashTodoLine(action: .pick,   hash: "H6"),
        ])
        XCTAssertTrue(plan.nonSelectedOrderIsPreserved(in: range))
    }

    // Test 2: Non-contiguous selection — {C2, C5} out of C2..C6 (HEAD=C6)
    //
    // Caller already computed the range starting from the anchor (C2).
    // Non-selected commits C3, C4, C6 must retain their relative order.
    func testNonContiguousSelection() throws {
        let range = ["C2", "C3", "C4", "C5", "C6"]
        let selected: Set<String> = ["C2", "C5"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "C2")
        XCTAssertEqual(plan.todo, [
            SquashTodoLine(action: .pick,   hash: "C2"),
            SquashTodoLine(action: .squash, hash: "C5"),
            SquashTodoLine(action: .pick,   hash: "C3"),
            SquashTodoLine(action: .pick,   hash: "C4"),
            SquashTodoLine(action: .pick,   hash: "C6"),
        ])
        XCTAssertTrue(plan.nonSelectedOrderIsPreserved(in: range))
    }

    // Test 3: Full-range selection — all commits become anchor + squash block,
    // no non-selected picks at the end.
    func testFullRangeSelection() throws {
        let range = ["C1", "C2", "C3"]
        let selected: Set<String> = ["C1", "C2", "C3"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "C1")
        XCTAssertEqual(plan.todo, [
            SquashTodoLine(action: .pick,   hash: "C1"),
            SquashTodoLine(action: .squash, hash: "C2"),
            SquashTodoLine(action: .squash, hash: "C3"),
        ])
        XCTAssertTrue(plan.nonSelectedOrderIsPreserved(in: range))
    }

    // Test 4: tooFewCommits — exactly one commit selected
    func testTooFewCommits_oneSelected() {
        let range = ["C1", "C2", "C3"]
        let selected: Set<String> = ["C1"]

        XCTAssertThrowsError(
            try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)
        ) { error in
            XCTAssertEqual(error as? SquashPlanError, .tooFewCommits(count: 1))
        }
    }

    // Test 5: tooFewCommits — empty selection
    func testTooFewCommits_emptySelected() {
        let range = ["C1", "C2", "C3"]
        let selected: Set<String> = []

        XCTAssertThrowsError(
            try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)
        ) { error in
            XCTAssertEqual(error as? SquashPlanError, .tooFewCommits(count: 0))
        }
    }

    // MARK: - Additional fixed edge cases

    // Minimum valid input: exactly 2 commits selected, both in a 2-commit range
    func testMinimumValidSelection_twoOfTwo() throws {
        let range = ["A", "B"]
        let selected: Set<String> = ["A", "B"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "A")
        XCTAssertEqual(plan.todo, [
            SquashTodoLine(action: .pick,   hash: "A"),
            SquashTodoLine(action: .squash, hash: "B"),
        ])
    }

    // Anchor is determined by position in range, not lexicographic order.
    // "Z" comes before "A" in the range, so "Z" must be anchor.
    func testAnchorIsEarliestInRange_notLexicographic() throws {
        let range = ["Z", "A", "M"]
        let selected: Set<String> = ["Z", "M"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "Z",
            "anchor must be the first selected element in range order, not alphabetical order")
        XCTAssertEqual(plan.todo.first, SquashTodoLine(action: .pick, hash: "Z"))
        XCTAssertEqual(plan.todo[1], SquashTodoLine(action: .squash, hash: "M"))
        XCTAssertEqual(plan.todo[2], SquashTodoLine(action: .pick, hash: "A"))
    }

    // Squash block relative order must match range order even when the input
    // Set has a different internal hash-based ordering.
    func testSquashBlockPreservesRangeOrder() throws {
        let range = ["A", "B", "C", "D", "E"]
        // "E" and "C" and "A" selected; in range order: A, C, E
        let selected: Set<String> = ["A", "C", "E"]

        let plan = try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: selected)

        XCTAssertEqual(plan.anchor, "A")
        // squash block: C then E (range order)
        XCTAssertEqual(plan.todo[1], SquashTodoLine(action: .squash, hash: "C"))
        XCTAssertEqual(plan.todo[2], SquashTodoLine(action: .squash, hash: "E"))
        // non-selected: B then D (range order)
        XCTAssertEqual(plan.todo[3], SquashTodoLine(action: .pick, hash: "B"))
        XCTAssertEqual(plan.todo[4], SquashTodoLine(action: .pick, hash: "D"))
    }

    // MARK: - [PBT] Invariants over random inputs

    /// **Validates: Requirements 4.1, 4.2, 4.3, 4.7**
    ///
    /// For any valid `(rangeOldestToNewest, selected)` pair with
    /// `|selected| >= 2`, the produced `SquashPlan` must satisfy all of:
    ///
    /// 1. **Anchor invariant**: first todo line is `pick anchor` where anchor
    ///    is the first element of range that is in selected.
    /// 2. **Squash block contiguous**: lines immediately after anchor are all
    ///    `.squash` for exactly the `squashSet` hashes, before any non-selected
    ///    `.pick`.
    /// 3. **Squash block relative order = range order**: the squash-block hashes
    ///    appear in the same relative order as in `rangeOldestToNewest`.
    /// 4. **Non-selected relative order preserved** (R4.7 observable form).
    /// 5. **Hash set conservation**: no hash added or dropped.
    /// 6. **Correct actions**: anchor → `.pick`; squashSet → all `.squash`;
    ///    non-selected → all `.pick`.
    /// 7. **R4.7 invariant method agrees** for every valid trial.
    ///
    /// Also verifies: `|selected| < 2` always throws `.tooFewCommits`.
    ///
    /// Implemented as a deterministic seeded-RNG loop — same approach as
    /// `FileInspectorSelectionStateTests` — to keep failures reproducible
    /// without an external PBT framework.
    func testPBTSquashPlanInvariants() throws {
        var rng = SeededGenerator(seed: 0xACE0_CAFE_B00B_5EED)

        for trial in 0..<2_000 {
            // Generate a range of N distinct hashes, oldest-first.
            let n = Int.random(in: 2...20, using: &rng)
            let range = (1...n).map { "H\($0)" }   // "H1" … "HN", already unique

            // Pick k >= 2 elements as selected.
            let k = Int.random(in: 2...n, using: &rng)
            let selected = Set(range.shuffled(using: &rng).prefix(k))

            guard let plan = try? SquashPlanBuilder.build(
                rangeOldestToNewest: range,
                selected: selected
            ) else {
                XCTFail("trial \(trial): build threw unexpectedly for |selected|=\(k) >= 2")
                continue
            }

            // ── 1. Anchor invariant ──────────────────────────────────────────
            let expectedAnchor = range.first(where: { selected.contains($0) })!
            XCTAssertEqual(plan.anchor, expectedAnchor,
                "trial \(trial): anchor must be first selected element in range order")
            XCTAssertEqual(plan.todo.first?.action, .pick,
                "trial \(trial): first todo line must be .pick")
            XCTAssertEqual(plan.todo.first?.hash, expectedAnchor,
                "trial \(trial): first todo line must pick the anchor")

            // ── 2. Squash block contiguous right after anchor ────────────────
            let squashSet = selected.subtracting([expectedAnchor])
            // Lines 1..<(1+squashSet.count) must all be .squash hashes from squashSet
            let squashBlock = Array(plan.todo.dropFirst().prefix(squashSet.count))
            XCTAssertTrue(squashBlock.allSatisfy { $0.action == .squash },
                "trial \(trial): all lines in the squash block must be .squash")
            XCTAssertEqual(Set(squashBlock.map(\.hash)), squashSet,
                "trial \(trial): squash block must contain exactly the squashSet hashes")

            // No non-selected picks appear before the squash block ends
            let linesAfterAnchorBeforeBlock = plan.todo
                .dropFirst()        // skip anchor
                .prefix(squashSet.count)
            XCTAssertTrue(
                linesAfterAnchorBeforeBlock.allSatisfy { squashSet.contains($0.hash) },
                "trial \(trial): squash block must not be interrupted by non-selected picks"
            )

            // ── 3. Squash block relative order = range order ─────────────────
            let squashBlockHashes = squashBlock.map(\.hash)
            let squashRangeOrder = range.filter { squashSet.contains($0) }
            XCTAssertEqual(squashBlockHashes, squashRangeOrder,
                "trial \(trial): squash block must be in the same relative order as the range")

            // ── 4. Non-selected relative order preserved (R4.7) ──────────────
            let nonSelectedInTodo = plan.todo
                .filter { !selected.contains($0.hash) }
                .map(\.hash)
            let nonSelectedInRange = range.filter { !selected.contains($0) }
            XCTAssertEqual(nonSelectedInTodo, nonSelectedInRange,
                "trial \(trial): non-selected commits must preserve their range-relative order")

            // ── 5. Hash set conservation ─────────────────────────────────────
            XCTAssertEqual(
                Set(plan.todo.map(\.hash)), Set(range),
                "trial \(trial): todo must contain exactly the hashes from the range — no additions or drops"
            )
            XCTAssertEqual(plan.todo.count, range.count,
                "trial \(trial): todo length must equal range length")

            // ── 6. Correct actions ────────────────────────────────────────────
            for line in plan.todo {
                let expectedAction: SquashTodoLine.Action
                if line.hash == expectedAnchor {
                    expectedAction = .pick
                } else if squashSet.contains(line.hash) {
                    expectedAction = .squash
                } else {
                    expectedAction = .pick
                }
                XCTAssertEqual(line.action, expectedAction,
                    "trial \(trial): hash \(line.hash) has wrong action")
            }

            // ── 7. R4.7 invariant method ──────────────────────────────────────
            XCTAssertTrue(
                plan.nonSelectedOrderIsPreserved(in: range),
                "trial \(trial): nonSelectedOrderIsPreserved must return true for every valid plan"
            )
        }
    }

    /// **Validates: Requirement 4.5 (cardinality < 2 always throws)**
    ///
    /// For any range and any `|selected| < 2`, `build` must throw
    /// `.tooFewCommits(count:)` with the exact count that was passed.
    func testPBTTooFewCommitsThrowsForAllSubTwoInputs() {
        var rng = SeededGenerator(seed: 0xDEAD_BEEF_0000_0001)

        for trial in 0..<1_000 {
            let n = Int.random(in: 1...20, using: &rng)
            let range = (1...n).map { "H\($0)" }

            // Test with 0 selected
            XCTAssertThrowsError(
                try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: []),
                "trial \(trial): empty selected must throw tooFewCommits"
            ) { error in
                XCTAssertEqual(error as? SquashPlanError, .tooFewCommits(count: 0),
                    "trial \(trial): error must be tooFewCommits(count: 0)")
            }

            // Test with exactly 1 selected (pick any element from range)
            let singleHash = range[Int.random(in: 0..<n, using: &rng)]
            XCTAssertThrowsError(
                try SquashPlanBuilder.build(rangeOldestToNewest: range, selected: [singleHash]),
                "trial \(trial): single-element selected must throw tooFewCommits"
            ) { error in
                XCTAssertEqual(error as? SquashPlanError, .tooFewCommits(count: 1),
                    "trial \(trial): error must be tooFewCommits(count: 1)")
            }
        }
    }
}

// MARK: - SeededGenerator (SplitMix64)

/// Deterministic seedable `RandomNumberGenerator` (SplitMix64 algorithm).
/// Mirrors the implementation in `FileInspectorSelectionStateTests` to keep
/// the seeded-loop PBT pattern consistent across test files.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Guard against the all-zero state, which weakens the mixing.
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

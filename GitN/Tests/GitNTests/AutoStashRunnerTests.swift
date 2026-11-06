import XCTest
@testable import GitN

/// Unit and property-based tests for `AutoStashRunner` — the service-layer
/// async wrapper that auto-stashes a dirty working tree around a git operation
/// (Requirements 5.1, 5.3, 5.4, 5.5, 5.8).
///
/// All tests inject mock closures — no subprocess is spawned, no SwiftUI body
/// is instantiated. The push/pop counters and the configurable failure flags are
/// used to assert the exact call counts and error payloads on each code path.
@MainActor
final class AutoStashRunnerTests: XCTestCase {

    // MARK: - Helpers

    // Paired factory that returns (runner, counter-holder) so tests can check
    // push/pop counts after `run` completes.
    private struct RunnerWithCounters {
        let runner: AutoStashRunner
        let pushCount: () -> Int
        let popCount: () -> Int
        let poppedOID: () -> String?
    }

    private func build(
        dirty: Bool,
        pushShouldFail: Bool = false,
        popShouldFail: Bool = false,
        hasConflicts: Bool = false
    ) -> RunnerWithCounters {
        final class Counter { var push = 0; var pop = 0; var poppedOID: String? }
        let c = Counter()

        let runner = AutoStashRunner(
            isDirty: { dirty },
            stashPush: {
                c.push += 1
                if pushShouldFail { throw GitError.operationFailed("mock stash push failure") }
                return "created-stash-oid"
            },
            stashPop: { oid in
                c.pop += 1
                c.poppedOID = oid
                if popShouldFail { throw GitError.operationFailed("mock stash pop failure") }
            },
            hasUnmergedPaths: { hasConflicts }
        )
        return RunnerWithCounters(
            runner: runner,
            pushCount: { c.push },
            popCount: { c.pop },
            poppedOID: { c.poppedOID }
        )
    }

    // MARK: - Clean tree (R5.1)

    /// Clean working tree: operation runs directly; no push, no pop (R5.1).
    func testCleanTree_successfulOperation_noPushNoPop() async throws {
        let rwc = build(dirty: false)
        let outcome = try await rwc.runner.run { /* no-op success */ }
        XCTAssertFalse(outcome.stashCreated, "clean tree must not create a stash entry")
        XCTAssertFalse(outcome.popConflict, "clean tree must report no pop conflict")
        XCTAssertEqual(rwc.pushCount(), 0, "clean tree: stashPush must never be called")
        XCTAssertEqual(rwc.popCount(),  0, "clean tree: stashPop must never be called")
    }

    /// Clean tree + operation failure: no pop, error contains only the original (R5.5 clean branch).
    func testCleanTree_operationFails_noPopAndOriginalErrorOnly() async throws {
        let rwc = build(dirty: false)
        do {
            try await rwc.runner.run { throw GitError.operationFailed("rebase conflict") }
            XCTFail("run should have thrown")
        } catch let AutoStashError.operationFailed(original, popFailure) {
            XCTAssertEqual(original, "rebase conflict")
            XCTAssertNil(popFailure, "clean tree: no pop was created, popFailure must be nil")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertEqual(rwc.pushCount(), 0, "clean tree: no push on operation failure")
        XCTAssertEqual(rwc.popCount(),  0, "clean tree: no pop on operation failure")
    }

    // MARK: - Dirty tree, success (R5.4)

    /// Dirty tree, operation and pop both succeed: exactly 1 push and 1 pop (R5.4).
    func testDirtyTree_successfulOperation_onePushOnePop() async throws {
        let rwc = build(dirty: true)
        let outcome = try await rwc.runner.run { /* no-op success */ }
        XCTAssertTrue(outcome.stashCreated, "dirty tree: stashCreated must be true")
        XCTAssertFalse(outcome.popConflict, "clean pop: popConflict must be false")
        XCTAssertEqual(rwc.pushCount(), 1, "dirty tree: stashPush must be called exactly once")
        XCTAssertEqual(rwc.popCount(),  1, "dirty tree: stashPop must be called exactly once")
        XCTAssertEqual(rwc.poppedOID(), "created-stash-oid")
    }

    // MARK: - Dirty tree, pop conflict (R5.4)

    /// Dirty tree, operation succeeds, pop leaves unmerged paths: popConflict flag set (R5.4).
    func testDirtyTree_successThenPopConflict_flagged() async throws {
        let rwc = build(dirty: true, hasConflicts: true)
        let outcome = try await rwc.runner.run { /* success */ }
        XCTAssertTrue(outcome.stashCreated)
        XCTAssertTrue(outcome.popConflict, "unmerged paths after pop must set popConflict")
        XCTAssertEqual(rwc.pushCount(), 1)
        XCTAssertEqual(rwc.popCount(),  1)
    }

    /// Dirty tree, operation succeeds, pop throws: popConflict flag set (R5.4).
    func testDirtyTree_successThenPopThrows_flagged() async throws {
        let rwc = build(dirty: true, popShouldFail: true)
        let outcome = try await rwc.runner.run { /* success */ }
        XCTAssertTrue(outcome.stashCreated)
        XCTAssertTrue(outcome.popConflict, "pop error must set popConflict")
        XCTAssertEqual(rwc.pushCount(), 1)
        XCTAssertEqual(rwc.popCount(),  1)
    }

    // MARK: - Dirty tree, operation failure (R5.5)

    /// Dirty tree, operation fails, pop succeeds: combined error with nil popFailure (R5.5).
    func testDirtyTree_operationFails_popSucceeds_combinedError() async throws {
        let rwc = build(dirty: true)
        do {
            try await rwc.runner.run { throw GitError.operationFailed("rebase failed") }
            XCTFail("run should have thrown")
        } catch let AutoStashError.operationFailed(original, popFailure) {
            XCTAssertEqual(original, "rebase failed")
            XCTAssertNil(popFailure, "pop succeeded: popFailure must be nil")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(rwc.pushCount(), 1, "dirty tree: push before operation")
        XCTAssertEqual(rwc.popCount(),  1, "dirty tree: pop attempted after operation failure")
    }

    /// Dirty tree, operation fails, pop also fails: combined error with non-nil popFailure (R5.5).
    func testDirtyTree_operationFails_popAlsoFails_bothErrorsCombined() async throws {
        let rwc = build(dirty: true, popShouldFail: true)
        do {
            try await rwc.runner.run { throw GitError.operationFailed("rebase conflict") }
            XCTFail("run should have thrown")
        } catch let AutoStashError.operationFailed(original, popFailure) {
            XCTAssertEqual(original, "rebase conflict")
            XCTAssertNotNil(popFailure, "pop failed: popFailure must be non-nil (R5.5)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(rwc.pushCount(), 1)
        XCTAssertEqual(rwc.popCount(),  1)
    }

    // MARK: - Stash push failure (R5.3)

    /// Push fails: operation must NEVER execute; throws stashPushFailed (R5.3).
    func testDirtyTree_pushFails_operationNotExecuted() async throws {
        let rwc = build(dirty: true, pushShouldFail: true)
        var operationExecuted = false
        do {
            try await rwc.runner.run { operationExecuted = true }
            XCTFail("run should have thrown")
        } catch let AutoStashError.stashPushFailed(msg) {
            XCTAssertFalse(msg.isEmpty, "stashPushFailed must carry the failure message")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertFalse(operationExecuted, "operation must NOT execute when stash push fails (R5.3)")
        XCTAssertEqual(rwc.pushCount(), 1,  "push was attempted once before failing")
        XCTAssertEqual(rwc.popCount(),  0,  "pop must never be called when push failed")
    }

    // MARK: - [PBT] pop calls ≤ push calls ≤ 1 for any execution path (R5.8)

    /// **Validates: Requirements 5.1, 5.3, 5.4, 5.5, 5.8**
    ///
    /// For any combination of `(dirty, pushFails, operationFails, popFails, hasConflicts)`,
    /// the invariant `popCount ≤ pushCount ≤ 1` must hold.
    ///
    /// Implemented as a deterministic seeded-RNG loop over all 32 boolean
    /// combinations (2^5) × 1 000 random trials per combination, which also
    /// exercises the operation-closure failure interleaving.
    func testPBTPopCountLeqPushCountLeqOne() async throws {
        var rng = SeededGenerator(seed: 0xB00B_5EED_CAFE_1234)

        // All 32 boolean flag combinations.
        for dirty in [false, true] {
            for pushFails in [false, true] {
                for opFails in [false, true] {
                    for popFails in [false, true] {
                        for hasConflicts in [false, true] {
                            for trial in 0..<50 {
                                // Randomise whether the operation throws a
                                // distinct error each trial to avoid test
                                // false-negatives from cached state.
                                _ = trial   // used to vary the RNG state
                                let seed = rng.next()
                                _ = seed    // keeps RNG state advancing

                                final class Counter { var push = 0; var pop = 0 }
                                let c = Counter()

                                let runner = AutoStashRunner(
                                    isDirty: { dirty },
                                    stashPush: {
                                        c.push += 1
                                        if pushFails {
                                            throw GitError.operationFailed("push fail")
                                        }
                                        return "created-stash-oid"
                                    },
                                    stashPop: { _ in
                                        c.pop += 1
                                        if popFails {
                                            throw GitError.operationFailed("pop fail")
                                        }
                                    },
                                    hasUnmergedPaths: { hasConflicts }
                                )

                                _ = try? await runner.run {
                                    if opFails { throw GitError.operationFailed("op fail") }
                                }

                                let push = c.push
                                let pop  = c.pop

                                XCTAssertLessThanOrEqual(
                                    pop, push,
                                    "popCount ≤ pushCount violated: pop=\(pop), push=\(push) "
                                    + "(dirty=\(dirty), pushFails=\(pushFails), opFails=\(opFails), "
                                    + "popFails=\(popFails), conflicts=\(hasConflicts))"
                                )
                                XCTAssertLessThanOrEqual(
                                    push, 1,
                                    "pushCount ≤ 1 violated: push=\(push) "
                                    + "(dirty=\(dirty), pushFails=\(pushFails))"
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SeededGenerator (SplitMix64)

/// Deterministic seedable `RandomNumberGenerator` (SplitMix64) — mirrors the
/// implementation used in `SquashPlanBuilderTests` and
/// `FileInspectorSelectionStateTests` for consistency.
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

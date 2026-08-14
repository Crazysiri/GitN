import Foundation

// MARK: - SquashTodoLine

/// One line in the interactive-rebase todo list.
struct SquashTodoLine: Equatable {
    enum Action: String, Equatable {
        case pick
        case squash
    }

    let action: Action
    let hash: String
}

// MARK: - SquashPlan

/// The full rebase plan produced by `SquashPlanBuilder`. Pure in-memory value
/// type: no subprocess spawning, no disk I/O, no `GIT_SEQUENCE_EDITOR`.
///
/// `todo` is ordered oldest-first and its first line is always
/// `pick <anchor>`. All hashes are the full hashes supplied by the caller.
struct SquashPlan: Equatable {
    /// The anchor commit — oldest selected commit, first todo line, pick'd.
    let anchor: String

    /// Ordered oldest-first rebase todo. First entry is always `pick anchor`.
    let todo: [SquashTodoLine]

    // MARK: R4.7 Invariant

    /// Returns `true` when the relative order of non-selected commits in `todo`
    /// exactly matches their relative order in `rangeOldestToNewest`.
    ///
    /// This is the observable form of the R4.7 precondition: only commits in
    /// `Squash_Set` may be moved; non-selected commits must preserve their
    /// original first-parent order. Unit tests call this method directly.
    func nonSelectedOrderIsPreserved(in rangeOldestToNewest: [String]) -> Bool {
        // Collect the non-anchor, non-squash hashes from todo (i.e. the picks
        // that are NOT the anchor).
        let selectedHashes: Set<String> = {
            var s = Set(todo.filter { $0.action == .squash }.map(\.hash))
            s.insert(anchor)
            return s
        }()

        let nonSelectedInTodo = todo
            .filter { !selectedHashes.contains($0.hash) }
            .map(\.hash)

        let nonSelectedInRange = rangeOldestToNewest
            .filter { !selectedHashes.contains($0) }

        return nonSelectedInTodo == nonSelectedInRange
    }
}

// MARK: - SquashPlanError

/// Errors thrown by `SquashPlanBuilder.build`.
enum SquashPlanError: Error, Equatable {
    /// Fewer than 2 commits were selected; squash requires at least 2.
    case tooFewCommits(count: Int)
}

// MARK: - SquashPlanBuilder

/// Pure in-memory builder that converts a first-parent commit range and a set
/// of selected hashes into a `SquashPlan` ready for `git rebase -i`.
///
/// The builder never spawns a subprocess, reads the filesystem, or sets
/// `GIT_SEQUENCE_EDITOR`, making it fully exercisable in unit tests without a
/// real git repository.
enum SquashPlanBuilder {

    /// Builds a `SquashPlan` from a first-parent commit range and user selection.
    ///
    /// - Parameters:
    ///   - rangeOldestToNewest: The inclusive sequence of commits from
    ///     `Anchor_Commit` up to and including HEAD along the first-parent
    ///     chain, **oldest first**. The caller is responsible for computing
    ///     this range before calling the builder.
    ///   - selected: The set of commit hashes chosen by the user (order-
    ///     independent; must contain at least 2 elements).
    ///
    /// - Returns: A `SquashPlan` whose todo satisfies Requirements 4.1–4.3
    ///   and whose R4.7 invariant is verified before returning.
    ///
    /// - Throws: `SquashPlanError.tooFewCommits` when `selected.count < 2`.
    static func build(
        rangeOldestToNewest: [String],
        selected: Set<String>
    ) throws -> SquashPlan {

        // R4.5 cardinality guard
        guard selected.count >= 2 else {
            throw SquashPlanError.tooFewCommits(count: selected.count)
        }

        // R4.2: anchor = first element of range that is in `selected`
        guard let anchor = rangeOldestToNewest.first(where: { selected.contains($0) }) else {
            // selected contains hashes not present in range at all; treat as
            // too-few since no anchor can be determined from the given range.
            throw SquashPlanError.tooFewCommits(count: selected.count)
        }

        // R4.3: squashSet = selected − {anchor}
        let squashSet = selected.subtracting([anchor])

        // Build todo by a single traversal of rangeOldestToNewest:
        //   1. anchor           → pick  (first line)
        //   2. squashSet items  → squash (in range order, right after anchor)
        //   3. non-selected     → pick  (in range order, after squash block)
        var todo: [SquashTodoLine] = []

        // First line: pick anchor
        todo.append(SquashTodoLine(action: .pick, hash: anchor))

        // Squash block: squashSet in range order
        for hash in rangeOldestToNewest where squashSet.contains(hash) {
            todo.append(SquashTodoLine(action: .squash, hash: hash))
        }

        // Remaining non-selected picks: everything in range that is neither
        // anchor nor in squashSet, in range order.
        for hash in rangeOldestToNewest where !selected.contains(hash) {
            todo.append(SquashTodoLine(action: .pick, hash: hash))
        }

        let plan = SquashPlan(anchor: anchor, todo: todo)

        // R4.7: assert the non-selected order invariant. The check is exposed
        // as a method so tests can call it independently; here we guard on it
        // to catch any future regressions in the builder algorithm itself.
        assert(
            plan.nonSelectedOrderIsPreserved(in: rangeOldestToNewest),
            "SquashPlanBuilder invariant violated: non-selected commits were reordered"
        )

        return plan
    }
}

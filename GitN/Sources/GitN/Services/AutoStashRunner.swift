// MARK: - AutoStashRunner
//
// Service-layer wrapper that protects a git operation from dirty working-tree
// interference by automatically stashing before and restoring after (R5).
//
// All dependencies are injected as closures so the runner is fully testable
// without spawning a real git process (R5.8).

import Foundation

// MARK: - Outcome

/// Result of a successful `AutoStashRunner.run(_:)` call.
struct AutoStashOutcome: Equatable {
    /// Whether the runner created a stash entry for this invocation (R5.1).
    let stashCreated: Bool
    /// Whether `stash pop` introduced unmerged paths (R5.4).
    let popConflict: Bool
}

// MARK: - Error

/// Errors that `AutoStashRunner.run(_:)` can throw.
enum AutoStashError: Error, Equatable {
    /// `git stash push` failed before the operation started (R5.3).
    /// The operation was **not** executed.
    case stashPushFailed(String)

    /// The wrapped operation failed.
    /// `popFailure` is non-nil if a stash was created and the subsequent
    /// `git stash pop` attempt also failed (R5.5).
    case operationFailed(original: String, popFailure: String?)
}

// MARK: - Runner

/// Wraps an `async` git operation with automatic stash push / pop.
///
/// All four dependencies are injected as `async` closures so the struct is
/// fully testable with mocks and never spawns a subprocess itself.
///
/// **Invariant (PBT, R5.8):** for any execution path,
/// `pop calls ≤ push calls ≤ 1`.
@MainActor
struct AutoStashRunner {
    /// Returns `true` when the working tree is dirty (`git status --porcelain` non-empty).
    let isDirty: () async -> Bool
    /// Saves the working tree to a new stash entry. Throws on failure.
    let stashPush: () async throws -> Void
    /// Pops `stash@{0}`. Throws on failure (including merge conflicts).
    let stashPop: () async throws -> Void
    /// Returns `true` when unmerged paths exist in the index after a pop.
    let hasUnmergedPaths: () async -> Bool

    /// Runs `operation`, surrounding it with stash push/pop when the working
    /// tree is dirty. Returns an `AutoStashOutcome` on success, or throws an
    /// `AutoStashError`.
    ///
    /// Flow:
    /// - **Clean tree** → run operation directly. On success return
    ///   `stashCreated: false`. On failure throw `operationFailed(original, nil)`.
    /// - **Dirty tree** → push stash. Push failure → throw `stashPushFailed`,
    ///   never call operation. On push success → run operation. On operation
    ///   success → pop; if pop errors or leaves unmerged paths, return
    ///   `stashCreated: true, popConflict: true`. On operation failure → attempt
    ///   pop; throw `operationFailed(original, popFailure?)`.
    func run(_ operation: () async throws -> Void) async throws -> AutoStashOutcome {
        let dirty = await isDirty()

        guard dirty else {
            // R5.1: clean tree — skip stash entirely.
            do {
                try await operation()
                return AutoStashOutcome(stashCreated: false, popConflict: false)
            } catch {
                throw AutoStashError.operationFailed(
                    original: error.localizedDescription,
                    popFailure: nil
                )
            }
        }

        // R5.3: dirty tree — push first.
        do {
            try await stashPush()
        } catch {
            // Push failed: do NOT proceed to operation (R5.3).
            throw AutoStashError.stashPushFailed(error.localizedDescription)
        }

        // Stash created — run operation.
        do {
            try await operation()
        } catch {
            // R5.5: operation failed after stash was created — try to pop.
            let opError = error.localizedDescription
            var popFailureMessage: String?
            do {
                try await stashPop()
            } catch let popError {
                popFailureMessage = popError.localizedDescription
            }
            throw AutoStashError.operationFailed(
                original: opError,
                popFailure: popFailureMessage
            )
        }

        // R5.4: operation succeeded — pop and check for unmerged paths.
        var hadPopError = false
        do {
            try await stashPop()
        } catch {
            hadPopError = true
        }

        let unmerged = await hasUnmergedPaths()
        let conflicted = hadPopError || unmerged
        return AutoStashOutcome(stashCreated: true, popConflict: conflicted)
    }
}

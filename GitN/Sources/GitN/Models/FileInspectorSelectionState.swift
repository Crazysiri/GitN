import Foundation

/// Tracks file-inspector selection ordering using a monotonically increasing
/// generation token. Each time the user selects a different file the caller
/// calls `beginSelection()` to obtain a fresh token, then performs its
/// synchronous state reset. When an asynchronous load eventually returns, the
/// caller uses `canApply(token:)` to decide whether the payload still belongs
/// to the current selection, discarding any payload from a superseded one.
///
/// This is a pure value type with no SwiftUI or service dependencies so it can
/// be exercised directly in unit tests.
struct FileInspectorSelectionState {
    /// The current selection token. Monotonically increasing; only ever
    /// mutated through `beginSelection()`.
    private(set) var generation: Int = 0

    /// Begins a new selection: increments `generation` and returns the new
    /// token. The caller should pass this token to any asynchronous load it
    /// kicks off and later validate it with `canApply(token:)`.
    mutating func beginSelection() -> Int {
        generation += 1
        return generation
    }

    /// Returns `true` when `token` matches the current `generation`, i.e. the
    /// selection that produced `token` is still the active one. Any older token
    /// returns `false` and its payload must be discarded.
    func canApply(token: Int) -> Bool {
        token == generation
    }
}

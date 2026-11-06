import Foundation

/// Shell context for one terminal session: current working directory and the
/// foreground process name, each with an explicit trust state.
///
/// Per SPEC §6.2, context must degrade to `.unknown` rather than guessing. A
/// stale cwd is kept for display only and marked, never presented as current.
struct TerminalContext: Equatable {
    enum Confidence: Equatable {
        case known      // freshly observed
        case stale      // last known value; the live query failed this cycle
        case unknown    // never observed, or not trustworthy
    }

    var cwd: String?
    var cwdConfidence: Confidence
    var foregroundProcess: String?

    static let empty = TerminalContext(cwd: nil, cwdConfidence: .unknown, foregroundProcess: nil)

    /// Fold a fresh observation into the previous context.
    ///
    /// - A successful cwd read becomes `.known`.
    /// - A failed read keeps the previous cwd but downgrades it to `.stale`
    ///   (or stays `.unknown` if nothing was ever known).
    /// - The foreground process is only meaningful when freshly observed; a
    ///   failed read clears it rather than showing a stale command.
    func merging(observedCwd: String?, observedForeground: String?) -> TerminalContext {
        var next = self

        if let observedCwd, !observedCwd.isEmpty {
            next.cwd = observedCwd
            next.cwdConfidence = .known
        } else if cwd != nil {
            next.cwdConfidence = .stale
        } else {
            next.cwdConfidence = .unknown
        }

        next.foregroundProcess = observedForeground
        return next
    }

    /// Whether suggestions may run: only when we trust the current directory.
    var isTrustworthyForSuggestions: Bool {
        cwdConfidence == .known
    }
}

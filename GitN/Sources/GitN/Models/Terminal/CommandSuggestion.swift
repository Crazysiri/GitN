import Foundation

/// A single completion candidate. `insertText` replaces exactly the active
/// token's range; accepting never executes the command (SPEC §7.2).
struct CommandSuggestion: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case command
        case subcommand
        case option
        case argument
        case path
        case branch
        case file
        case script
        case remote
        case tag
    }

    let id: String
    let displayName: String
    let insertText: String
    let detail: String?
    let kind: Kind

    init(id: String, displayName: String, insertText: String, detail: String? = nil, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.insertText = insertText
        self.detail = detail
        self.kind = kind
    }
}

/// Request context for producing suggestions. Carries everything a provider
/// needs to produce correct, cancelable results keyed to one input state.
struct SuggestionRequest: Equatable {
    let sessionID: UUID
    let cwd: String
    let line: String
    let cursor: Int
    let promptGeneration: Int
    let inputRevision: Int
}

enum ShellWordEscaping {
    /// Escape a value for safe insertion as a single shell token. Prefers no
    /// quoting for simple values, single-quotes when needed.
    static func escape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" +
            "._-/=:@,+%"
        )
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        // Single-quote and escape embedded single quotes.
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'" + escaped + "'"
    }
}

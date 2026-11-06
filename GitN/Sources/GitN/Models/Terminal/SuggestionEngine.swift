import Foundation

/// Pure suggestion logic: given a tokenized line, decides which static
/// candidates apply and what dynamic data (if any) a provider must fetch. No
/// I/O, no shell execution — fully unit-testable (SPEC §7.2).
enum SuggestionEngine {
    /// What dynamic data the active token needs, resolved by async providers.
    enum DynamicNeed: Equatable {
        case none
        case directories      // cd / path argument
        case gitBranches      // git checkout/switch/merge/rebase/branch <ref>
        case gitFiles         // git add/restore/diff/reset <file>
        case packageScripts   // npm run / yarn run <script>
    }

    struct Plan: Equatable {
        /// Static suggestions computable without I/O.
        let staticSuggestions: [CommandSuggestion]
        /// Dynamic data to fetch and filter by the active token prefix.
        let dynamicNeed: DynamicNeed
        /// The active token's replacement range (Character offsets), or nil when
        /// it cannot be safely determined (then no custom insertion happens).
        let replacementRange: Range<Int>?
        /// The prefix of the active token to match against.
        let prefix: String
    }

    static func plan(line: String, cursor: Int) -> Plan {
        let analysis = CommandLineTokenizer.analyze(line, cursor: cursor)

        let activeToken = analysis.activeTokenIndex.flatMap { analysis.tokens[$0] }
        let prefix = activeToken?.value ?? ""
        let range: Range<Int>? = activeToken.map { $0.start..<$0.end } ?? (cursor..<cursor)

        // Position 0 (command word) or a brand-new first token → suggest commands.
        let position = analysis.activeArgumentPosition ?? 0
        guard let command = analysis.commandWord, position > 0 else {
            let matches = CommandSchema.commands
                .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
                .map {
                    CommandSuggestion(
                        id: "cmd:\($0)",
                        displayName: $0,
                        insertText: $0,
                        detail: nil,
                        kind: .command
                    )
                }
            return Plan(staticSuggestions: matches, dynamicNeed: .none, replacementRange: range, prefix: prefix)
        }

        switch command {
        case "cd":
            return Plan(staticSuggestions: [], dynamicNeed: .directories, replacementRange: range, prefix: prefix)

        case "git":
            return planGit(analysis: analysis, position: position, prefix: prefix, range: range)

        case "npm", "yarn":
            return planPackageManager(command: command, analysis: analysis, position: position, prefix: prefix, range: range)

        default:
            return Plan(staticSuggestions: [], dynamicNeed: .none, replacementRange: range, prefix: prefix)
        }
    }

    private static func planGit(
        analysis: CommandLineTokenizer.Analysis,
        position: Int,
        prefix: String,
        range: Range<Int>?
    ) -> Plan {
        // Position 1 → git subcommand.
        if position == 1 {
            let subs = CommandSchema.gitSubcommands
                .filter { prefix.isEmpty || $0.name.hasPrefix(prefix) }
                .map {
                    CommandSuggestion(
                        id: "git:\($0.name)",
                        displayName: $0.name,
                        insertText: $0.name,
                        detail: $0.detail,
                        kind: .subcommand
                    )
                }
            return Plan(staticSuggestions: subs, dynamicNeed: .none, replacementRange: range, prefix: prefix)
        }

        // Position 2+ → depends on the subcommand.
        let subcommand = analysis.tokens.count > 1 ? analysis.tokens[1].value : ""
        if prefix.hasPrefix("-") {
            return Plan(staticSuggestions: [], dynamicNeed: .none, replacementRange: range, prefix: prefix)
        }
        if CommandSchema.gitBranchArgSubcommands.contains(subcommand) {
            return Plan(staticSuggestions: [], dynamicNeed: .gitBranches, replacementRange: range, prefix: prefix)
        }
        if CommandSchema.gitFileArgSubcommands.contains(subcommand) {
            return Plan(staticSuggestions: [], dynamicNeed: .gitFiles, replacementRange: range, prefix: prefix)
        }
        return Plan(staticSuggestions: [], dynamicNeed: .none, replacementRange: range, prefix: prefix)
    }

    private static func planPackageManager(
        command: String,
        analysis: CommandLineTokenizer.Analysis,
        position: Int,
        prefix: String,
        range: Range<Int>?
    ) -> Plan {
        if position == 1 {
            let subs = CommandSchema.subcommands(for: command)
                .filter { prefix.isEmpty || $0.name.hasPrefix(prefix) }
                .map {
                    CommandSuggestion(
                        id: "\(command):\($0.name)",
                        displayName: $0.name,
                        insertText: $0.name,
                        detail: $0.detail,
                        kind: .subcommand
                    )
                }
            return Plan(staticSuggestions: subs, dynamicNeed: .none, replacementRange: range, prefix: prefix)
        }
        // `npm run <script>` / `yarn run <script>`.
        let subcommand = analysis.tokens.count > 1 ? analysis.tokens[1].value : ""
        if subcommand == "run", position == 2 {
            return Plan(staticSuggestions: [], dynamicNeed: .packageScripts, replacementRange: range, prefix: prefix)
        }
        return Plan(staticSuggestions: [], dynamicNeed: .none, replacementRange: range, prefix: prefix)
    }
}

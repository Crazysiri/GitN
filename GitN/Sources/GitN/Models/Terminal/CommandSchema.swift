import Foundation

/// Static, structured command schema for the first suggestion delivery:
/// cd / git / npm / yarn. This is GitN's own schema (SPEC §7.1), not a copy of
/// any reference catalog. Dynamic content (branches, files, scripts, dirs) is
/// supplied by providers, not this table.
enum CommandSchema {
    struct Subcommand: Equatable {
        let name: String
        let detail: String
    }

    /// Known top-level commands that have suggestions.
    static let commands: [String] = ["cd", "git", "npm", "yarn"]

    /// git subcommands covered by the first delivery (SPEC §7.1 common set).
    static let gitSubcommands: [Subcommand] = [
        .init(name: "status", detail: "Show working tree status"),
        .init(name: "add", detail: "Stage changes"),
        .init(name: "restore", detail: "Restore working tree files"),
        .init(name: "reset", detail: "Reset current HEAD"),
        .init(name: "commit", detail: "Record changes"),
        .init(name: "log", detail: "Show commit logs"),
        .init(name: "diff", detail: "Show changes"),
        .init(name: "show", detail: "Show an object"),
        .init(name: "branch", detail: "List or manage branches"),
        .init(name: "checkout", detail: "Switch branches or restore files"),
        .init(name: "switch", detail: "Switch branches"),
        .init(name: "merge", detail: "Join development histories"),
        .init(name: "rebase", detail: "Reapply commits"),
        .init(name: "fetch", detail: "Download objects and refs"),
        .init(name: "pull", detail: "Fetch and integrate"),
        .init(name: "push", detail: "Update remote refs"),
        .init(name: "remote", detail: "Manage remotes"),
        .init(name: "tag", detail: "Manage tags"),
        .init(name: "stash", detail: "Stash changes"),
        .init(name: "cherry-pick", detail: "Apply existing commits"),
        .init(name: "revert", detail: "Revert existing commits"),
    ]

    /// git subcommands whose first argument is a branch/ref.
    static let gitBranchArgSubcommands: Set<String> = [
        "checkout", "switch", "merge", "rebase", "branch",
    ]

    /// git subcommands whose arguments are working-tree files.
    static let gitFileArgSubcommands: Set<String> = [
        "add", "restore", "diff", "reset",
    ]

    static let npmSubcommands: [Subcommand] = [
        .init(name: "install", detail: "Install dependencies"),
        .init(name: "run", detail: "Run a package script"),
        .init(name: "test", detail: "Run tests"),
        .init(name: "start", detail: "Start the package"),
        .init(name: "build", detail: "Run the build script"),
        .init(name: "ci", detail: "Clean install"),
        .init(name: "update", detail: "Update packages"),
        .init(name: "uninstall", detail: "Remove a package"),
        .init(name: "publish", detail: "Publish the package"),
    ]

    static let yarnSubcommands: [Subcommand] = [
        .init(name: "install", detail: "Install dependencies"),
        .init(name: "add", detail: "Add a dependency"),
        .init(name: "remove", detail: "Remove a dependency"),
        .init(name: "run", detail: "Run a script"),
        .init(name: "test", detail: "Run tests"),
        .init(name: "start", detail: "Start the package"),
        .init(name: "build", detail: "Run the build script"),
        .init(name: "upgrade", detail: "Upgrade dependencies"),
    ]

    static func subcommands(for command: String) -> [Subcommand] {
        switch command {
        case "git": return gitSubcommands
        case "npm": return npmSubcommands
        case "yarn": return yarnSubcommands
        default: return []
        }
    }
}

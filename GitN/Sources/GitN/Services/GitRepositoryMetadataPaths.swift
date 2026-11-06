import Foundation

/// Git stores linked-worktree HEAD/index in a per-worktree gitdir while refs can
/// live in a separate common directory. A worktree's .git is often a pointer file.
struct GitRepositoryMetadataPaths: Equatable, Sendable {
    let workTreePath: String
    let gitDirPath: String
    let commonDirPath: String

    init(repoPath: String) {
        let root = (repoPath as NSString).standardizingPath
        let dotGit = (root as NSString).appendingPathComponent(".git")
        let gitDir: String
        if let firstLine = try? String(contentsOfFile: dotGit, encoding: .utf8)
            .components(separatedBy: .newlines).first,
           firstLine.hasPrefix("gitdir: ") {
            gitDir = Self.resolve(String(firstLine.dropFirst("gitdir: ".count)), relativeTo: root)
        } else {
            gitDir = (dotGit as NSString).standardizingPath
        }

        let commonPointer = (gitDir as NSString).appendingPathComponent("commondir")
        let commonDir: String
        if let raw = try? String(contentsOfFile: commonPointer, encoding: .utf8),
           let firstLine = raw.components(separatedBy: .newlines).first,
           !firstLine.isEmpty {
            commonDir = Self.resolve(firstLine, relativeTo: gitDir)
        } else {
            commonDir = gitDir
        }

        workTreePath = root
        gitDirPath = gitDir
        commonDirPath = commonDir
    }

    var watchPaths: [String] {
        var seen = Set<String>()
        return [workTreePath, gitDirPath, commonDirPath].filter { seen.insert($0).inserted }
    }

    /// Returns nil for siblings with a matching textual prefix.
    static func relativePath(_ path: String, inside directory: String) -> String? {
        if path == directory { return "" }
        let prefix = directory + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private static func resolve(_ path: String, relativeTo directory: String) -> String {
        let absolute = path.hasPrefix("/") ? path : (directory as NSString).appendingPathComponent(path)
        return (absolute as NSString).standardizingPath
    }
}

import Foundation

struct BranchInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let shortHash: String
    let upstream: String?
    let isCurrent: Bool
    let isRemote: Bool
}

struct RemoteInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: String
}

struct StashInfo: Identifiable, Equatable {
    var id: String { index }
    let index: String
    let message: String
    let date: String
}

struct CommitInfo: Identifiable, Equatable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let parentHashes: [String]
    let authorName: String
    let authorEmail: String
    let date: String
    let message: String
    let refs: [String]

    var isMerge: Bool { parentHashes.count > 1 }

    static let uncommittedHash = "__uncommitted__"
    var isUncommitted: Bool { hash == Self.uncommittedHash }

    static func uncommittedEntry(parentHash: String?, stagedCount: Int, unstagedCount: Int) -> CommitInfo {
        let summary: String
        if stagedCount > 0 && unstagedCount > 0 {
            summary = "\(stagedCount) staged, \(unstagedCount) unstaged"
        } else if stagedCount > 0 {
            summary = "\(stagedCount) staged"
        } else {
            summary = "\(unstagedCount) changed"
        }

        return CommitInfo(
            hash: uncommittedHash,
            shortHash: "",
            parentHashes: parentHash.map { [$0] } ?? [],
            authorName: "",
            authorEmail: "",
            date: "",
            message: summary,
            refs: []
        )
    }
}

struct DiffFile: Identifiable, Equatable {
    var id: String { path }
    let additions: Int
    let deletions: Int
    let path: String
}

struct FileStatus: Identifiable, Equatable {
    var id: String { path }
    let statusCode: String
    let path: String

    var isStaged: Bool {
        let idx = statusCode.first ?? " "
        return idx != " " && idx != "?"
    }

    var hasStagedChanges: Bool {
        let idx = statusCode.first ?? " "
        return idx != " " && idx != "?"
    }

    var hasUnstagedChanges: Bool {
        let wt = statusCode.count >= 2 ? statusCode[statusCode.index(after: statusCode.startIndex)] : Character(" ")
        return wt != " "
    }

    var stagedDescription: String {
        switch statusCode.first {
        case "A": return "Added"
        case "M": return "Modified"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "C": return "Copied"
        default: return "Unknown"
        }
    }

    var unstagedDescription: String {
        let wt = statusCode.count >= 2 ? statusCode[statusCode.index(after: statusCode.startIndex)] : Character(" ")
        switch wt {
        case "M": return "Modified"
        case "D": return "Deleted"
        case "?": return "Untracked"
        case "R": return "Renamed"
        default: return "Unknown"
        }
    }

    var statusDescription: String {
        if hasStagedChanges { return stagedDescription }
        return unstagedDescription
    }
}

struct SubmoduleInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let hash: String
}

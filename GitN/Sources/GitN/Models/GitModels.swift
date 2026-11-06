import Foundation
import UniformTypeIdentifiers

struct BranchInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let shortHash: String
    let upstream: String?
    let isCurrent: Bool
    let isRemote: Bool
    let ahead: Int
    let behind: Int

    init(name: String, shortHash: String, upstream: String?, isCurrent: Bool, isRemote: Bool, ahead: Int = 0, behind: Int = 0) {
        self.name = name
        self.shortHash = shortHash
        self.upstream = upstream
        self.isCurrent = isCurrent
        self.isRemote = isRemote
        self.ahead = ahead
        self.behind = behind
    }
}

struct RemoteInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: String
}

struct StashInfo: Identifiable, Equatable {
    var id: String { oid }
    let index: String
    let oid: String
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

struct FileLogEntry: Equatable {
    let commit: CommitInfo
    let pathAtCommit: String
}

enum ReflogEntryKind: String, Equatable, CaseIterable {
    case checkout
    case reset
    case rebase
    case amend
    case commit
    case merge
    case branchMove
    case fetch
    case unknown

    var label: String {
        switch self {
        case .checkout: return "checkout"
        case .reset: return "reset"
        case .rebase: return "rebase"
        case .amend: return "amend"
        case .commit: return "commit"
        case .merge: return "merge"
        case .branchMove: return "branch"
        case .fetch: return "fetch"
        case .unknown: return "reflog"
        }
    }
}

struct ReflogEntryInfo: Identifiable, Equatable {
    let refName: String
    let index: Int
    let oldOID: String?
    let newOID: String?
    let message: String
    let kind: ReflogEntryKind
    let committerName: String
    let committerEmail: String
    let date: String

    var id: String {
        "\(refName)#\(index):\(oldOID ?? "nil")->\(newOID ?? "nil")"
    }

    var shortOldOID: String {
        oldOID.map { String($0.prefix(7)) } ?? "0000000"
    }

    var shortNewOID: String {
        newOID.map { String($0.prefix(7)) } ?? "0000000"
    }
}

struct ReflogSourceOption: Identifiable, Equatable {
    let refName: String
    let title: String

    var id: String { refName }
}

enum GraphDisplayMode: String, CaseIterable, Equatable {
    case all
    case current

    var title: String { rawValue }
}

enum DiffChangeKind: Sendable, Equatable {
    case added
    case deleted
    case modified
    case renamed
    case copied
    case untracked
    case unknown
}

struct DiffFile: Identifiable, Equatable {
    var id: String { path }
    let additions: Int
    let deletions: Int
    let path: String
    /// Non-nil when the file was renamed; contains the original path.
    let oldPath: String?
    let changeKind: DiffChangeKind
    let isLFSTracked: Bool

    var isRenamed: Bool { oldPath != nil }
    var isPureRename: Bool { isRenamed && additions == 0 && deletions == 0 }

    /// Whether the standalone "renamed" badge should appear in the file list row.
    /// False for image files: their `imageStatusLabel` ("renamed image") already conveys
    /// the rename, so showing a separate "renamed" badge would produce "renamed image renamed".
    var showsRenamedBadge: Bool { isPureRename && !path.isImageFile }

    /// Short status label shown for image files in the diff file list row.
    /// Non-image files return nil; the row falls back to numeric +/- stats.
    var imageStatusText: String? {
        guard path.isImageFile else { return nil }
        switch changeKind {
        case .added, .untracked: return "+ image"
        case .deleted:           return "- image"
        case .renamed:           return "renamed image"
        case .modified:          return "modified image"
        case .copied:            return "copied image"
        case .unknown:           return nil
        }
    }

    var lfsBadgeText: String? { isLFSTracked ? "LFS" : nil }

    init(additions: Int, deletions: Int, path: String, oldPath: String? = nil, changeKind: DiffChangeKind = .modified, isLFSTracked: Bool = false) {
        self.additions = additions
        self.deletions = deletions
        self.path = path
        self.oldPath = oldPath
        self.changeKind = changeKind
        self.isLFSTracked = isLFSTracked
    }
}

enum FileRenderableKind: Sendable, Equatable {
    case text
    case image
    case video
    case binary
}

struct VisualFileContent: Sendable, Equatable {
    let kind: FileRenderableKind
    let oldData: Data?
    let newData: Data?
    let message: String?

    var currentData: Data? { newData ?? oldData }
    var isImage: Bool { kind == .image }
    var isVideo: Bool { kind == .video }
    var isBinary: Bool { kind == .binary }
}

extension String {
    private static let knownImageExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg",
        "png", "svg", "tif", "tiff", "webp"
    ]

    var isImageFile: Bool {
        let ext = (self as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if Self.knownImageExtensions.contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    static let knownVideoExtensions: Set<String> = ["mp4", "m4v", "mov", "m4a"]

    var isVideoFile: Bool {
        let ext = (self as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if Self.knownVideoExtensions.contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audiovisualContent)
    }
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

    var diffChangeKind: DiffChangeKind {
        if statusCode == "??" { return .untracked }
        switch statusCode.first {
        case "A":
            return .added
        case "D":
            return .deleted
        case "R":
            return .renamed
        case "C":
            return .copied
        case "M":
            return .modified
        default:
            switch statusCode.dropFirst().first {
            case "D":
                return .deleted
            case "R":
                return .renamed
            case "M":
                return .modified
            case "?":
                return .untracked
            default:
                return .unknown
            }
        }
    }
}

struct SubmoduleInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let hash: String
}

// MARK: - Conflict Types

enum ConflictType: Equatable {
    case rebase
    case merge(branch: String)
    case stashApply

    var title: String {
        switch self {
        case .rebase: return "Rebase conflicts detected"
        case .merge: return "Merge conflicts detected"
        case .stashApply: return "Stash apply conflicts detected"
        }
    }

    var abortLabel: String {
        switch self {
        case .rebase: return "Abort Rebase"
        case .merge: return "Abort Merge"
        case .stashApply: return "Abort (Reset)"
        }
    }

    var continueLabel: String {
        switch self {
        case .rebase: return "Continue Rebase"
        case .merge: return "Commit Merge"
        case .stashApply: return "Done"
        }
    }
}

// MARK: - Rebase State

struct RebaseState: Equatable {
    let sourceBranch: String
    let targetBranch: String
    let currentStep: Int
    let totalSteps: Int
    var conflictedFiles: [ConflictFile]
    var resolvedFiles: [ConflictFile]
}

struct ConflictFile: Identifiable, Equatable {
    var id: String { path }
    let path: String
    var conflictCount: Int
}

struct ConflictSides: Equatable {
    let oursLabel: String
    let theirsLabel: String
    let baseLines: [String]
    let outputLines: [String]
    let oursLines: [String]
    let theirsLines: [String]
    let mergedText: String
    let markers: [ConflictRegion]
}

/// Identity of the conflict inputs and working-tree file presented to the user.
/// A missing worktree file is distinct from an empty file.
struct ConflictFileSnapshot: Equatable, Sendable {
    let ancestorOID: String?
    let currentOID: String?
    let incomingOID: String?
    let workingTreeSHA256: String?
}

struct ConflictRegion: Identifiable, Equatable {
    let id: Int
    let oursRange: Range<Int>
    let theirsRange: Range<Int>
    let baseRange: Range<Int>
    let outputRange: Range<Int>
    let currentLines: [String]
    let baseLines: [String]
    let incomingLines: [String]
    let rawConflictLines: [String]
}

struct MergedLine: Identifiable, Equatable {
    let id: Int
    let content: String
    let origin: MergedLineOrigin
}

enum MergedLineOrigin: Equatable {
    case common
    case ours
    case theirs
    case conflictHeader
}

enum ConflictSide {
    case ours, theirs
}

// MARK: - Toast Notification

struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let style: ToastStyle

    enum ToastStyle: Equatable {
        case error, warning, success, info
    }

    init(title: String, detail: String = "", style: ToastStyle = .error) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.style = style
    }
}

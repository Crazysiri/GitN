import Foundation

struct WorktreeInfo: Identifiable, Equatable, Sendable {
    let path: String
    let headOID: String?
    let branchRef: String?
    let isBare: Bool
    let isDetached: Bool
    let lockedReason: String?
    let prunableReason: String?
    let isMain: Bool

    var id: String { path }
    var branchName: String? {
        guard let branchRef, branchRef.hasPrefix("refs/heads/") else { return nil }
        return String(branchRef.dropFirst("refs/heads/".count))
    }
    var isLocked: Bool { lockedReason != nil }
    var isPrunable: Bool { prunableReason != nil }
}

enum WorktreePorcelainParser {
    static func parse(_ data: Data) throws -> [WorktreeInfo] {
        guard !data.isEmpty else { return [] }
        var records: [[String]] = []
        var fields: [String] = []
        for raw in data.split(separator: 0, omittingEmptySubsequences: false) {
            if raw.isEmpty {
                if !fields.isEmpty { records.append(fields); fields = [] }
                continue
            }
            guard let field = String(bytes: raw, encoding: .utf8) else {
                throw GitError.operationFailed("Invalid UTF-8 in worktree listing")
            }
            fields.append(field)
        }
        if !fields.isEmpty { records.append(fields) }

        return try records.enumerated().map { index, fields in
            guard let first = fields.first, first.hasPrefix("worktree "),
                  first.count > "worktree ".count else {
                throw GitError.operationFailed("Malformed worktree listing")
            }
            let path = String(first.dropFirst("worktree ".count))
            var headOID: String?
            var branchRef: String?
            var isBare = false
            var isDetached = false
            var lockedReason: String?
            var prunableReason: String?
            for field in fields.dropFirst() {
                if field.hasPrefix("HEAD ") { headOID = String(field.dropFirst(5)) }
                else if field.hasPrefix("branch ") { branchRef = String(field.dropFirst(7)) }
                else if field == "bare" { isBare = true }
                else if field == "detached" { isDetached = true }
                else if field == "locked" { lockedReason = "" }
                else if field.hasPrefix("locked ") { lockedReason = String(field.dropFirst(7)) }
                else if field == "prunable" { prunableReason = "" }
                else if field.hasPrefix("prunable ") { prunableReason = String(field.dropFirst(9)) }
            }
            return WorktreeInfo(
                path: path, headOID: headOID, branchRef: branchRef, isBare: isBare,
                isDetached: isDetached, lockedReason: lockedReason,
                prunableReason: prunableReason, isMain: index == 0
            )
        }
    }
}

struct WorktreeService: Sendable {
    let repoPath: String
    private var cli: GitCLI { GitCLI(repoPath: repoPath) }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    func list() async throws -> [WorktreeInfo] {
        let data = try await cli.outputData(["worktree", "list", "--porcelain", "-z"])
        return try WorktreePorcelainParser.parse(data)
    }

    func add(path: String, branch: String, createBranch: Bool) async throws {
        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repoPath)
        let token = try await gate.acquire()
        do {
            try Task.checkCancellation()
            try await addUnqueued(path: path, branch: branch, createBranch: createBranch)
            await gate.release(token)
        } catch {
            await gate.release(token)
            throw error
        }
    }

    private func addUnqueued(path: String, branch: String, createBranch: Bool) async throws {
        let destination = (path as NSString).standardizingPath
        let name = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard destination.hasPrefix("/"), !name.isEmpty else {
            throw GitError.operationFailed("Choose an absolute worktree path and branch name")
        }
        try await cli.run(["check-ref-format", "--branch", name])
        if createBranch {
            try await cli.run(["worktree", "add", "-b", name, "--", destination, "HEAD"])
        } else {
            try await cli.run(["worktree", "add", "--", destination, name])
        }
    }

    func remove(_ worktree: WorktreeInfo) async throws {
        let gate = RepositoryMutationRegistry.shared.gate(repoPath: repoPath)
        let token = try await gate.acquire()
        do {
            try Task.checkCancellation()
            try await removeUnqueued(worktree)
            await gate.release(token)
        } catch {
            await gate.release(token)
            throw error
        }
    }

    private func removeUnqueued(_ worktree: WorktreeInfo) async throws {
        let current = try await list().first {
            Self.canonicalPath($0.path) == Self.canonicalPath(worktree.path)
        }
        guard let current else { throw GitError.operationFailed("Worktree no longer exists") }
        guard !current.isMain,
              Self.canonicalPath(current.path) != Self.canonicalPath(repoPath) else {
            throw GitError.operationFailed("Cannot remove the main or current worktree")
        }
        guard !current.isLocked, !current.isPrunable else {
            throw GitError.operationFailed("Locked or prunable worktree requires manual recovery")
        }
        // No --force: Git refuses removal when the worktree has local changes.
        try await cli.run(["worktree", "remove", "--", current.path])
    }
}

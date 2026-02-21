import SwiftUI
import Combine

@Observable @MainActor
final class RepoViewModel {
    let repoPath: String
    let repoName: String
    private let git: GitService

    var localBranches: [BranchInfo] = []
    var remoteBranches: [BranchInfo] = []
    var remotes: [RemoteInfo] = []
    var tags: [String] = []
    var stashes: [StashInfo] = []
    var submodules: [SubmoduleInfo] = []
    var currentBranch: String = ""

    var commits: [CommitInfo] = []
    var graphEntries: [String: CommitGraphEntry] = [:]
    private var headCommitHash: String?

    var selectedCommit: CommitInfo?
    var diffFiles: [DiffFile] = []
    var fileDiffContent: String = ""
    var parsedDiff: ParsedDiff?
    var selectedDiffFile: DiffFile?

    var fileStatuses: [FileStatus] = []
    var commitSummary: String = ""
    var commitDescription: String = ""

    var commitMessage: String {
        if commitDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return commitSummary
        }
        return commitSummary + "\n\n" + commitDescription
    }

    var showTerminal = true
    var isLoading = false
    var collapsedSections: Set<String> = []

    var remoteBranchGroups: [String: [BranchInfo]] {
        Dictionary(grouping: remoteBranches) { branch in
            let parts = branch.name.split(separator: "/", maxSplits: 1)
            return parts.first.map(String.init) ?? branch.name
        }
    }

    init(path: String, name: String) {
        self.repoPath = path
        self.repoName = name
        self.git = GitService(repoPath: path)
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let b = git.localBranches()
            async let rb = git.remoteBranches()
            async let r = git.remotes()
            async let t = git.tags()
            async let st = git.stashes()
            async let sub = git.submodules()
            async let c = git.commitLog()
            async let cur = git.currentBranch()
            async let stat = git.status()
            async let hch = git.headCommitHash()

            let (lb, rbs, rms, tgs, sth, subs, cms, cb, sts, hc) = try await (
                b, rb, r, t, st, sub, c, cur, stat, hch
            )
            localBranches = lb
            remoteBranches = rbs
            remotes = rms
            tags = tgs
            stashes = sth
            submodules = subs
            currentBranch = cb
            fileStatuses = sts
            headCommitHash = hc

            var allEntries = cms
            if !sts.isEmpty {
                let staged = sts.filter(\.hasStagedChanges).count
                let unstaged = sts.filter(\.hasUnstagedChanges).count
                let uncommitted = CommitInfo.uncommittedEntry(
                    parentHash: hc,
                    stagedCount: staged,
                    unstagedCount: unstaged
                )
                allEntries.insert(uncommitted, at: 0)
            }
            commits = allEntries
            graphEntries = GraphLayoutEngine.computeEntries(for: allEntries)
        } catch {
            print("Error loading repo data: \(error)")
        }
    }

    func selectCommit(_ commit: CommitInfo) async {
        selectedCommit = commit
        selectedDiffFile = nil
        fileDiffContent = ""
        do {
            if commit.isUncommitted {
                diffFiles = try await git.uncommittedDiffFiles()
            } else {
                diffFiles = try await git.diffDetail(hash: commit.hash)
            }
        } catch {
            diffFiles = []
        }
    }

    enum DiffContext { case staged, unstaged, committed }
    var currentDiffContext: DiffContext = .committed

    func selectDiffFile(_ file: DiffFile, context: DiffContext = .committed) async {
        guard let commit = selectedCommit else { return }
        selectedDiffFile = file
        currentDiffContext = context
        do {
            if commit.isUncommitted {
                let status = fileStatuses.first(where: { $0.path == file.path })
                let statusCode = status?.statusCode ?? "M "

                switch context {
                case .staged:
                    fileDiffContent = try await git.stagedFileDiff(path: file.path)
                case .unstaged:
                    if statusCode == "??" {
                        fileDiffContent = try await git.readFullFileContent(path: file.path)
                    } else {
                        fileDiffContent = try await git.unstagedFileDiff(path: file.path)
                    }
                case .committed:
                    fileDiffContent = try await git.uncommittedFileDiff(path: file.path, statusCode: statusCode)
                }
            } else {
                fileDiffContent = try await git.fileDiff(hash: commit.hash, path: file.path)
            }
            parsedDiff = DiffParserEngine.parse(fileDiffContent)
        } catch {
            fileDiffContent = "Failed to load diff"
            parsedDiff = nil
        }
    }

    var isAmend = false

    func performCommit() async {
        guard !commitSummary.isEmpty else { return }
        do {
            if isAmend {
                try await git.commitAmend(message: commitMessage)
            } else {
                try await git.commit(message: commitMessage)
            }
            commitSummary = ""
            commitDescription = ""
            isAmend = false
            await loadAll()
        } catch {
            operationError = "Commit failed: \(error.localizedDescription)"
        }
    }

    func loadHeadCommitMessage() async {
        do {
            let msg = try await git.headCommitMessage()
            let parts = msg.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            commitSummary = String(parts.first ?? "")
            if parts.count > 1 {
                commitDescription = String(parts[1]).trimmingCharacters(in: .newlines)
            } else {
                commitDescription = ""
            }
        } catch {}
    }

    func stageFile(_ path: String) async {
        do {
            try await git.stageFile(path)
            fileStatuses = try await git.status()
        } catch {}
    }

    func unstageFile(_ path: String) async {
        do {
            try await git.unstageFile(path)
            fileStatuses = try await git.status()
        } catch {}
    }

    func stageAllFiles() async {
        let unstaged = fileStatuses.filter(\.hasUnstagedChanges)
        for file in unstaged {
            do { try await git.stageFile(file.path) } catch {}
        }
        do { fileStatuses = try await git.status() } catch {}
    }

    func unstageAllFiles() async {
        let staged = fileStatuses.filter(\.hasStagedChanges)
        for file in staged {
            do { try await git.unstageFile(file.path) } catch {}
        }
        do { fileStatuses = try await git.status() } catch {}
    }

    // MARK: - Hunk / Line Staging & Discarding

    func stageAllHunks() async {
        guard let diff = parsedDiff, let file = selectedDiffFile else { return }
        if diff.isNewFile {
            await stageFile(file.path)
        } else {
            for i in 0..<diff.hunks.count {
                let patch = diff.patchForHunk(i)
                guard !patch.isEmpty else { continue }
                do { try await git.applyPatch(patch, cached: true) }
                catch { print("Stage hunk \(i) failed: \(error)") }
            }
        }
        await refreshAfterPatchAction()
    }

    func discardAllHunks() async {
        guard let diff = parsedDiff else { return }
        for i in 0..<diff.hunks.count {
            let patch = diff.patchForHunk(i)
            guard !patch.isEmpty else { continue }
            do { try await git.applyPatch(patch, reverse: true) }
            catch { print("Discard hunk \(i) failed: \(error)") }
        }
        await refreshAfterPatchAction()
    }

    func stageHunk(_ hunkIndex: Int) async {
        guard let diff = parsedDiff, let file = selectedDiffFile else { return }
        if diff.isNewFile {
            await stageFile(file.path)
        } else {
            let patch = diff.patchForHunk(hunkIndex)
            guard !patch.isEmpty else { return }
            do {
                try await git.applyPatch(patch, cached: true)
            } catch { print("Stage hunk failed: \(error)"); return }
        }
        await refreshAfterPatchAction()
    }

    func discardHunk(_ hunkIndex: Int) async {
        guard let diff = parsedDiff else { return }
        let patch = diff.patchForHunk(hunkIndex)
        guard !patch.isEmpty else { return }
        do {
            try await git.applyPatch(patch, reverse: true)
        } catch { print("Discard hunk failed: \(error)"); return }
        await refreshAfterPatchAction()
    }

    func stageLines(_ hunkIndex: Int, lineIndices: Set<Int>) async {
        guard let diff = parsedDiff else { return }
        let patch = diff.patchForLines(hunkIndex, lineIndices: lineIndices)
        guard !patch.isEmpty else { return }
        do {
            try await git.applyPatch(patch, cached: true)
        } catch { print("Stage lines failed: \(error)"); return }
        await refreshAfterPatchAction()
    }

    func discardLines(_ hunkIndex: Int, lineIndices: Set<Int>) async {
        guard let diff = parsedDiff else { return }
        let patch = diff.patchForLines(hunkIndex, lineIndices: lineIndices)
        guard !patch.isEmpty else { return }
        do {
            try await git.applyPatch(patch, reverse: true)
        } catch { print("Discard lines failed: \(error)"); return }
        await refreshAfterPatchAction()
    }

    func unstageAllHunks() async {
        guard let diff = parsedDiff, let file = selectedDiffFile else { return }
        if diff.isNewFile {
            await unstageFile(file.path)
        } else {
            for i in 0..<diff.hunks.count {
                let patch = diff.patchForHunk(i)
                guard !patch.isEmpty else { continue }
                do { try await git.applyPatch(patch, cached: true, reverse: true) }
                catch { print("Unstage hunk \(i) failed: \(error)") }
            }
        }
        await refreshAfterPatchAction()
    }

    func unstageLines(_ hunkIndex: Int, lineIndices: Set<Int>) async {
        guard let diff = parsedDiff else { return }
        let patch = diff.patchForLines(hunkIndex, lineIndices: lineIndices)
        guard !patch.isEmpty else { return }
        do {
            try await git.applyPatch(patch, cached: true, reverse: true)
        } catch { print("Unstage lines failed: \(error)"); return }
        await refreshAfterPatchAction()
    }

    private func refreshAfterPatchAction() async {
        do {
            fileStatuses = try await git.status()
        } catch {}
        if let file = selectedDiffFile {
            await selectDiffFile(file, context: currentDiffContext)
        }
        // Refresh commits graph (uncommitted entry counts may change)
        do {
            let cms = try await git.commitLog()
            let hc = try await git.headCommitHash()
            headCommitHash = hc
            var allEntries = cms
            if !fileStatuses.isEmpty {
                let staged = fileStatuses.filter(\.hasStagedChanges).count
                let unstaged = fileStatuses.filter(\.hasUnstagedChanges).count
                let uncommitted = CommitInfo.uncommittedEntry(
                    parentHash: hc, stagedCount: staged, unstagedCount: unstaged
                )
                allEntries.insert(uncommitted, at: 0)
            }
            commits = allEntries
            graphEntries = GraphLayoutEngine.computeEntries(for: allEntries)
        } catch {}
    }

    // MARK: - Remote Operations

    var operationInProgress = false
    var operationError: String?

    func performFetch() async {
        await performRemoteOperation { try await $0.git.fetch() }
    }

    func performPull() async {
        await performRemoteOperation { try await $0.git.pull() }
    }

    func performPush() async {
        await performRemoteOperation { try await $0.git.push() }
    }

    func performStashSave(message: String? = nil) async {
        await performRemoteOperation { try await $0.git.stashSave(message: message) }
    }

    func performStashPop() async {
        await performRemoteOperation { try await $0.git.stashPop() }
    }

    private func performRemoteOperation(_ op: (RepoViewModel) async throws -> Void) async {
        operationInProgress = true
        operationError = nil
        do {
            try await op(self)
            await loadAll()
        } catch {
            operationError = error.localizedDescription
        }
        operationInProgress = false
    }

    func toggleSection(_ section: String) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func isSectionCollapsed(_ section: String) -> Bool {
        collapsedSections.contains(section)
    }
}

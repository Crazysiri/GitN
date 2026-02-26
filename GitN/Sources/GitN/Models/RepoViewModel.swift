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
    var isDetachedHead: Bool = false

    var commits: [CommitInfo] = []
    private(set) var headCommitHash: String?
    private(set) var currentBranchHashes: Set<String> = []

    // MARK: - Pagination (pull-based via CommitWalker)
    private var commitWalker: CommitWalker?
    private(set) var allCommitsLoaded = false
    private(set) var isLoadingMore = false
    private let commitPageSize = 2000

    var selectedCommit: CommitInfo?
    var diffFiles: [DiffFile] = []
    var fileDiffContent: String = ""
    var parsedDiff: ParsedDiff?
    var selectedDiffFile: DiffFile?

    var fileStatuses: [FileStatus] = []
    var selectedFilePaths: Set<String> = []
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

    private var collapsedSectionsKey: String { "SidebarCollapsedSections.\(repoPath)" }

    private func loadCollapsedSections() {
        let saved = UserDefaults.standard.stringArray(forKey: collapsedSectionsKey) ?? []
        collapsedSections = Set(saved)
        // MR section 默认折叠
        if !UserDefaults.standard.bool(forKey: collapsedSectionsKey + ".initialized") {
            collapsedSections.insert("mergeRequests")
            UserDefaults.standard.set(true, forKey: collapsedSectionsKey + ".initialized")
            saveCollapsedSections()
        }
    }

    private func saveCollapsedSections() {
        UserDefaults.standard.set(Array(collapsedSections), forKey: collapsedSectionsKey)
    }

    // MARK: - File Context Menu Actions

    func discardChanges(paths: [String]) async {
        for path in paths {
            do { try await git.discardFileChanges(path: path) } catch {}
        }
        do { fileStatuses = try await git.status() } catch {}
        if let file = selectedDiffFile {
            await selectDiffFile(file, context: currentDiffContext)
        }
    }

    func addToGitignore(pattern: String) async {
        do {
            try await git.addToGitignore(pattern: pattern)
            await loadAll()
        } catch {
            showToast(title: "Ignore failed", detail: error.localizedDescription, style: .error)
        }
    }

    func deleteFiles(paths: [String]) async {
        for path in paths {
            let fullPath = (repoPath as NSString).appendingPathComponent(path)
            try? FileManager.default.removeItem(atPath: fullPath)
        }
        do { fileStatuses = try await git.status() } catch {}
        await refreshAfterPatchAction()
    }

    func showInFinder(path: String) {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        NSWorkspace.shared.selectFile(fullPath, inFileViewerRootedAtPath: "")
    }

    func openInEditor(path: String) {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        let url = URL(fileURLWithPath: fullPath)
        NSWorkspace.shared.open(url)
    }

    func getFileDiff(hash: String, path: String) async throws -> String {
        try await git.fileDiff(hash: hash, path: path)
    }

    func copyFilePaths(_ paths: [String]) {
        let text = paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func createPatch(paths: [String]) async {
        var patchContent = ""
        for path in paths {
            do {
                let diff = try await git.unstagedFileDiff(path: path)
                if !diff.isEmpty { patchContent += diff + "\n" }
            } catch {}
        }
        guard !patchContent.isEmpty else {
            showToast(title: "No changes", detail: "No diff to create patch from", style: .info)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(patchContent, forType: .string)
        showToast(title: "Patch copied", detail: "\(paths.count) file(s) patch copied to clipboard", style: .success)
    }

    func stageFiles(_ paths: [String]) async {
        for path in paths { do { try await git.stageFile(path) } catch {} }
        do { fileStatuses = try await git.status() } catch {}
    }

    func unstageFiles(_ paths: [String]) async {
        for path in paths { do { try await git.unstageFile(path) } catch {} }
        do { fileStatuses = try await git.status() } catch {}
    }

    func toggleFileSelection(_ path: String, isMulti: Bool) {
        if isMulti {
            if selectedFilePaths.contains(path) {
                selectedFilePaths.remove(path)
            } else {
                selectedFilePaths.insert(path)
            }
        } else {
            selectedFilePaths = [path]
        }
    }

    // MARK: - File History
    var showFileHistory = false
    var fileHistoryPath: String = ""
    var fileHistoryCommits: [CommitInfo] = []
    var fileHistorySelectedCommit: CommitInfo?
    var fileHistoryDiff: String = ""
    var fileHistoryParsedDiff: ParsedDiff?

    func openFileHistory(path: String) async {
        fileHistoryPath = path
        fileHistoryCommits = []
        fileHistorySelectedCommit = nil
        fileHistoryDiff = ""
        fileHistoryParsedDiff = nil
        showFileHistory = true
        do {
            fileHistoryCommits = try await git.fileLog(path: path)
        } catch {
            showToast(title: "Failed to load file history", detail: error.localizedDescription, style: .error)
        }
    }

    func selectFileHistoryCommit(_ commit: CommitInfo) async {
        fileHistorySelectedCommit = commit
        do {
            let diff = try await git.fileLogDiff(hash: commit.hash, path: fileHistoryPath)
            fileHistoryDiff = diff
            fileHistoryParsedDiff = DiffParserEngine.parse(diff)
        } catch {
            fileHistoryDiff = ""
            fileHistoryParsedDiff = nil
        }
    }

    func closeFileHistory() {
        showFileHistory = false
        fileHistoryPath = ""
        fileHistoryCommits = []
        fileHistorySelectedCommit = nil
        fileHistoryDiff = ""
        fileHistoryParsedDiff = nil
    }

    // MARK: - GitLab MR
    var mergeRequests: [GitLabMR] = []
    var mrStateFilter: MRStateFilter = .opened
    var isMRLoading = false
    var mrError: String?
    var isMRMerging = false
    var mrMergingStatus: String = ""
    private var gitlabService: GitLabService?

    // MARK: - Conflict State (Rebase / Merge / Stash)
    var conflictType: ConflictType?
    var rebaseState: RebaseState?
    var isRebaseConflict: Bool { rebaseState != nil }
    var isInConflict: Bool { conflictType != nil }
    var hasUnresolvedConflicts: Bool { currentConflictedFiles.isEmpty == false }
    var conflictMergeFile: ConflictFile?
    var conflictSides: ConflictSides?
    var conflictOutputLines: [String] = []
    var showConflictMergeView = false
    var rebaseCommitMessage = ""
    // Merge/Stash conflict files (rebase uses rebaseState.conflictedFiles)
    var mergeConflictedFiles: [ConflictFile] = []
    var mergeResolvedFiles: [ConflictFile] = []
    var mergeCommitMessage = ""

    /// Unified access to conflicted files regardless of conflict type.
    var currentConflictedFiles: [ConflictFile] {
        switch conflictType {
        case .rebase: return rebaseState?.conflictedFiles ?? []
        case .merge, .stashApply: return mergeConflictedFiles
        case nil: return []
        }
    }

    /// Unified access to resolved files regardless of conflict type.
    var currentResolvedFiles: [ConflictFile] {
        switch conflictType {
        case .rebase: return rebaseState?.resolvedFiles ?? []
        case .merge, .stashApply: return mergeResolvedFiles
        case nil: return []
        }
    }

    // MARK: - Push Upstream Prompt
    var showPushUpstreamPrompt = false
    var pushUpstreamRemote = "origin"
    var pushUpstreamBranch = ""

    // MARK: - Force Delete Branch Prompt
    var showForceDeleteBranchPrompt = false
    var forceDeleteBranchName = ""

    // MARK: - SSH Host Key Prompt
    var showHostKeyPrompt = false
    var hostKeyHost = ""
    private var pendingOperationAfterHostKey: (() async -> Void)?

    // MARK: - Toast
    var toastMessage: ToastMessage?

    private var fileWatcher: RepositoryFileWatcher?

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
        loadCollapsedSections()
    }

    // MARK: - File System Watcher

    /// Start watching the repo for filesystem changes. Call once after init.
    func startWatching() {
        guard fileWatcher == nil else { return }
        fileWatcher = RepositoryFileWatcher(repoPath: repoPath) { [weak self] changes in
            guard let self else { return }
            Task { @MainActor in
                await self.handleFileSystemChanges(changes)
            }
        }
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    private func handleFileSystemChanges(_ changes: Set<RepositoryFileWatcher.ChangeKind>) async {
        guard !isLoading, !operationInProgress else { return }

        let needsFullReload = changes.contains(.head) || changes.contains(.refs)

        if needsFullReload {
            await loadAll()
        } else {
            await refreshStatusAndGraph()
        }
    }

    /// Lightweight refresh: only file statuses + uncommitted graph entry.
    /// Does NOT reload the full commit list — only updates the uncommitted entry.
    private func refreshStatusAndGraph() async {
        do {
            let sts = try await git.status()
            fileStatuses = sts
            let hc = try await git.headCommitHash()
            headCommitHash = hc
            currentBranchHashes = await git.commitHashesOnCurrentBranch()

            let hadUncommitted = commits.first?.isUncommitted == true
            let needsUncommitted = !sts.isEmpty || rebaseState != nil

            if hadUncommitted && needsUncommitted {
                let staged = sts.filter(\.hasStagedChanges).count
                let unstaged = sts.filter(\.hasUnstagedChanges).count
                let uncommitted = CommitInfo.uncommittedEntry(
                    parentHash: hc, stagedCount: staged, unstagedCount: unstaged
                )
                commits[0] = uncommitted
            } else if hadUncommitted != needsUncommitted {
                if hadUncommitted { commits.removeFirst() }
                if needsUncommitted {
                    let staged = sts.filter(\.hasStagedChanges).count
                    let unstaged = sts.filter(\.hasUnstagedChanges).count
                    let uncommitted = CommitInfo.uncommittedEntry(
                        parentHash: hc, stagedCount: staged, unstagedCount: unstaged
                    )
                    commits.insert(uncommitted, at: 0)
                }
            }

            if let file = selectedDiffFile, selectedCommit?.isUncommitted == true {
                await selectDiffFile(file, context: currentDiffContext)
            }
        } catch {}
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Phase 1: Load metadata in parallel
            async let b = git.localBranches()
            async let rb = git.remoteBranches()
            async let r = git.remotes()
            async let t = git.tags()
            async let st = git.stashes()
            async let sub = git.submodules()
            async let cur = git.currentBranch()
            async let stat = git.status()
            async let hch = git.headCommitHash()
            async let detached = git.isDetachedHead()
            async let branchHashes = git.commitHashesOnCurrentBranch()

            let (lb, rbs, rms, tgs, sth, subs, cb, sts, hc, dh) = try await (
                b, rb, r, t, st, sub, cur, stat, hch, detached
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
            isDetachedHead = dh
            currentBranchHashes = await branchHashes

            // Phase 2: Load commits with pagination (graph is computed lazily by the view layer)
            var loadedCommits: [CommitInfo] = []

            // Check conflict state early so we know if we need a WIP entry
            if let state = try? await git.rebaseState() {
                rebaseState = state
                conflictType = .rebase
                rebaseCommitMessage = await git.rebaseCommitMessage()
            } else if let mergeState = try? await git.mergeConflictState() {
                rebaseState = nil
                if await git.isMergeInProgress() {
                    conflictType = .merge(branch: mergeState.sourceBranch)
                    mergeCommitMessage = await git.mergeCommitMessage()
                } else if !mergeState.conflictedFiles.isEmpty {
                    conflictType = .stashApply
                } else {
                    conflictType = nil
                }
                mergeConflictedFiles = mergeState.conflictedFiles
                mergeResolvedFiles = mergeState.resolvedFiles
            } else {
                rebaseState = nil
                conflictType = nil
                mergeConflictedFiles = []
                mergeResolvedFiles = []
            }

            let needsWIP = !sts.isEmpty || conflictType != nil
            if needsWIP {
                let staged = sts.filter(\.hasStagedChanges).count
                let unstaged = sts.filter(\.hasUnstagedChanges).count
                let uncommitted = CommitInfo.uncommittedEntry(
                    parentHash: hc, stagedCount: staged, unstagedCount: unstaged
                )
                loadedCommits.append(uncommitted)
            }

            // Create on-demand commit walker (pull-based, no eager traversal)
            let walker = await git.createCommitWalker()
            commitWalker = walker
            allCommitsLoaded = false

            // Load first page on background thread
            if let walker {
                let pageSize = commitPageSize
                let batch = await Task.detached(priority: .userInitiated) {
                    walker.nextBatch(count: pageSize)
                }.value
                loadedCommits.append(contentsOf: batch)
                if batch.count < pageSize {
                    allCommitsLoaded = true
                    commitWalker = nil
                }
            } else {
                allCommitsLoaded = true
            }

            commits = loadedCommits
        } catch {
            print("Error loading repo data: \(error)")
        }
    }

    /// Load the next page of commits as the user scrolls down.
    /// Only walks `commitPageSize` commits via git_revwalk – no eager traversal.
    func loadMoreCommits() async {
        guard !allCommitsLoaded, !isLoadingMore, let walker = commitWalker else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let pageSize = commitPageSize
        let batch = await Task.detached(priority: .userInitiated) {
            walker.nextBatch(count: pageSize)
        }.value

        if !batch.isEmpty {
            commits.append(contentsOf: batch)
        }
        if batch.count < pageSize {
            allCommitsLoaded = true
            commitWalker = nil
            print("[RepoViewModel] All commits loaded, total=\(commits.count)")
        }
    }

    func selectCommit(_ commit: CommitInfo) async {
        if isCompareMode { exitCompareMode() }
        selectedCommit = commit
        selectedDiffFile = nil
        fileDiffContent = ""
        parsedDiff = nil
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
        let isUncommitted = selectedCommit?.isUncommitted == true || isInConflict
        guard selectedCommit != nil || isInConflict else { return }
        selectedDiffFile = file
        currentDiffContext = context
        do {
            if isUncommitted {
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
            } else if let commit = selectedCommit {
                fileDiffContent = try await git.fileDiff(hash: commit.hash, path: file.path)
            }
            parsedDiff = DiffParserEngine.parse(fileDiffContent)
        } catch {
            fileDiffContent = "Failed to load diff"
            parsedDiff = nil
        }
    }

    var isAmend = false
    var isGeneratingAICommit = false

    /// Generate commit message from staged diff using cursor-agent
    func generateAICommitMessage() async {
        isGeneratingAICommit = true
        defer { isGeneratingAICommit = false }
        do {
            let diff = try await git.diffStaged()
            guard !diff.isEmpty else {
                showToast(title: "No staged changes", detail: "Stage files first to generate a commit message", style: .info)
                return
            }
            let (title, description) = try await AICommitService.generateCommitMessage(diff: diff)
            commitSummary = title
            commitDescription = description
        } catch let error as AICommitError {
            switch error {
            case .notFound:
                showToast(title: "cursor-agent Not Found", detail: "Install Cursor IDE or configure cursor-agent. See Settings → AI Commit.", style: .error)
            case .apiKeyMissing:
                showToast(title: "API Key Required", detail: "Set CURSOR_API_KEY in Settings → AI Commit.", style: .error)
                openSettings()
            default:
                showToast(title: "AI Generate Failed", detail: error.localizedDescription, style: .error)
            }
        } catch {
            showToast(title: "AI Generate Failed", detail: error.localizedDescription, style: .error)
        }
    }

    /// Generate commit message for an existing commit's diff (for reword)
    func generateAICommitMessageForCommit(hash: String) async -> (title: String, description: String)? {
        isGeneratingAICommit = true
        defer { isGeneratingAICommit = false }
        do {
            let diff = try await git.commitDiff(hash: hash)
            guard !diff.isEmpty else {
                showToast(title: "No diff found", style: .info)
                return nil
            }
            let result = try await AICommitService.generateCommitMessage(diff: diff)
            return result
        } catch let error as AICommitError {
            switch error {
            case .notFound:
                showToast(title: "cursor-agent Not Found", detail: "Install Cursor IDE or configure cursor-agent. See Settings → AI Commit.", style: .error)
            case .apiKeyMissing:
                showToast(title: "API Key Required", detail: "Set CURSOR_API_KEY in Settings → AI Commit.", style: .error)
                openSettings()
            default:
                showToast(title: "AI Generate Failed", detail: error.localizedDescription, style: .error)
            }
            return nil
        } catch {
            showToast(title: "AI Generate Failed", detail: error.localizedDescription, style: .error)
            return nil
        }
    }

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
        // Update uncommitted entry counts without reloading all commits
        let hadUncommitted = commits.first?.isUncommitted == true
        let needsUncommitted = !fileStatuses.isEmpty

        if hadUncommitted && needsUncommitted {
            let staged = fileStatuses.filter(\.hasStagedChanges).count
            let unstaged = fileStatuses.filter(\.hasUnstagedChanges).count
            let uncommitted = CommitInfo.uncommittedEntry(
                parentHash: headCommitHash, stagedCount: staged, unstagedCount: unstaged
            )
            commits[0] = uncommitted
        } else if hadUncommitted != needsUncommitted {
            if hadUncommitted { commits.removeFirst() }
            if needsUncommitted {
                let staged = fileStatuses.filter(\.hasStagedChanges).count
                let unstaged = fileStatuses.filter(\.hasUnstagedChanges).count
                let uncommitted = CommitInfo.uncommittedEntry(
                    parentHash: headCommitHash, stagedCount: staged, unstagedCount: unstaged
                )
                commits.insert(uncommitted, at: 0)
            }
        }
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
        let hasUpstream = localBranches.first(where: { $0.isCurrent })?.upstream != nil
        if !hasUpstream {
            pushUpstreamRemote = "origin"
            pushUpstreamBranch = currentBranch
            showPushUpstreamPrompt = true
            return
        }
        await performRemoteOperation { try await $0.git.push() }
    }

    func performPushWithUpstream(remote: String, branch: String) async {
        showPushUpstreamPrompt = false
        await performRemoteOperation {
            try await $0.git.push(remoteName: remote, branchName: branch, setUpstream: true)
        }
    }

    func cancelPushUpstreamPrompt() {
        showPushUpstreamPrompt = false
    }

    func performStashSave(message: String? = nil) async {
        await performRemoteOperation { try await $0.git.stashSave(message: message) }
    }

    func performStashPop() async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.stashPop()
            await loadAll()
        } catch {
            await checkForMergeOrStashConflict(errorMessage: error.localizedDescription, type: .stashApply)
        }
        operationInProgress = false
    }

    func performCreateBranch(name: String) async {
        await performRemoteOperation { try await $0.git.createBranch(name: name) }
    }

    func performAddRemote(name: String, url: String) async {
        await performRemoteOperation { try await $0.git.addRemote(name: name, url: url) }
    }

    func performDeleteRemote(name: String) async {
        await performRemoteOperation { try await $0.git.deleteRemote(name: name) }
    }

    func performEditRemote(oldName: String, newName: String, newURL: String) async {
        await performRemoteOperation {
            if oldName != newName {
                try await $0.git.renameRemote(oldName: oldName, newName: newName)
            }
            try await $0.git.setRemoteURL(name: newName, url: newURL)
        }
    }

    // MARK: - Commit Context Menu Operations

    func performMerge(_ refName: String) async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.merge(refName)
            await loadAll()
        } catch {
            await checkForMergeOrStashConflict(errorMessage: error.localizedDescription, type: .merge(branch: refName))
        }
        operationInProgress = false
    }

    func performRebase(onto target: String) async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.rebase(onto: target)
            await loadAll()
        } catch {
            await checkForRebaseConflict(errorMessage: error.localizedDescription)
        }
        operationInProgress = false
    }

    func performCheckoutBranch(_ name: String) async {
        await performRemoteOperation { try await $0.git.checkoutBranch(name) }
    }

    func performCheckoutCommit(_ hash: String) async {
        await performRemoteOperation { try await $0.git.checkoutCommit(hash) }
    }

    func performCherryPick(_ hash: String) async {
        await performRemoteOperation { try await $0.git.cherryPick(hash) }
    }

    func performReset(_ hash: String, mode: GitService.ResetMode) async {
        await performRemoteOperation { try await $0.git.resetToCommit(hash, mode: mode) }
    }

    func performRevert(_ hash: String) async {
        await performRemoteOperation { try await $0.git.revertCommit(hash) }
    }

    func performSquashCommits(_ hashes: [String]) async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.squashCommits(hashes)
            await loadAll()
            showToast(title: "Squash Completed", detail: "Successfully squashed \(hashes.count) commits", style: .success)
        } catch {
            await checkForRebaseConflict(errorMessage: error.localizedDescription)
        }
        operationInProgress = false
    }

    func performDeleteBranch(_ name: String, force: Bool = false) async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.deleteBranch(name, force: force)
            await loadAll()
        } catch {
            let msg = error.localizedDescription
            if !force && (msg.lowercased().contains("not fully merged") || msg.lowercased().contains("is not fully merged")) {
                forceDeleteBranchName = name
                showForceDeleteBranchPrompt = true
            } else {
                operationError = msg
            }
        }
        operationInProgress = false
    }

    func confirmForceDeleteBranch() async {
        showForceDeleteBranchPrompt = false
        let name = forceDeleteBranchName
        forceDeleteBranchName = ""
        await performDeleteBranch(name, force: true)
    }

    func cancelForceDeleteBranch() {
        showForceDeleteBranchPrompt = false
        forceDeleteBranchName = ""
    }

    func performRenameBranch(oldName: String, newName: String) async {
        await performRemoteOperation { try await $0.git.renameBranch(oldName: oldName, newName: newName) }
    }

    func performDeleteRemoteBranch(remote: String, branch: String) async {
        await performRemoteOperation { try await $0.git.deleteRemoteBranch(remote: remote, branch: branch) }
    }

    func performCreateTag(name: String, at hash: String) async {
        await performRemoteOperation { try await $0.git.createTag(name: name, at: hash) }
    }

    func performSetUpstream(remote: String, branch: String) async {
        await performRemoteOperation { try await $0.git.setUpstream(remote: remote, branch: branch) }
    }

    func performEditCommitMessage(hash: String, newMessage: String) async {
        if hash == headCommitHash {
            await performRemoteOperation { try await $0.git.amendCommitMessage(newMessage) }
        } else {
            // Non-HEAD commit: use interactive rebase to reword
            operationInProgress = true
            operationError = nil
            do {
                try await git.rewordCommitMessage(hash: hash, newMessage: newMessage)
                await loadAll()
                showToast(title: "Message Updated", style: .success)
            } catch {
                await checkForRebaseConflict(errorMessage: error.localizedDescription)
            }
            operationInProgress = false
        }
    }

    func performCreateBranchAt(name: String, commitHash: String) async {
        await performRemoteOperation { try await $0.git.createBranchAt(name: name, commitHash: commitHash) }
    }

    // MARK: - Scroll to commit

    var isCompareMode = false
    var compareBaseHash: String?

    var scrollToCommitHash: String?

    func performCompareWithWorkingDirectory(_ commit: CommitInfo) async {
        isCompareMode = true
        compareBaseHash = commit.hash
        selectedCommit = commit
        selectedDiffFile = nil
        fileDiffContent = ""
        parsedDiff = nil
        do {
            diffFiles = try await git.compareFileList(commit.hash)
        } catch {
            diffFiles = []
            operationError = "Compare failed: \(error.localizedDescription)"
        }
    }

    func selectCompareFile(_ file: DiffFile) async {
        guard let baseHash = compareBaseHash else { return }
        selectedDiffFile = file
        currentDiffContext = .committed
        do {
            fileDiffContent = try await git.compareFileDiff(baseHash, path: file.path)
            parsedDiff = DiffParserEngine.parse(fileDiffContent)
        } catch {
            fileDiffContent = "Failed to load diff"
            parsedDiff = nil
        }
    }

    func exitCompareMode() {
        isCompareMode = false
        compareBaseHash = nil
        diffFiles = []
        fileDiffContent = ""
        parsedDiff = nil
        selectedDiffFile = nil
    }

    func scrollToCommitForBranch(_ branch: BranchInfo) {
        if let commit = commits.first(where: { $0.shortHash == branch.shortHash || $0.hash.hasPrefix(branch.shortHash) }) {
            scrollToCommitHash = commit.hash
            Task { await selectCommit(commit) }
        }
    }

    private func performRemoteOperation(_ op: @escaping (RepoViewModel) async throws -> Void) async {
        operationInProgress = true
        operationError = nil
        do {
            try await op(self)
            await loadAll()
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performRemoteOperation(op)
                }
                showHostKeyPrompt = true
            } else {
                operationError = msg
            }
        }
        operationInProgress = false
    }

    private func extractHostFromError(_ msg: String) -> String {
        if let range = msg.range(of: "'"),
           let endRange = msg[range.upperBound...].range(of: "'") {
            return String(msg[range.upperBound..<endRange.lowerBound])
        }
        if msg.lowercased().contains("github.com") { return "github.com" }
        if msg.lowercased().contains("gitlab.com") { return "gitlab.com" }
        if msg.lowercased().contains("bitbucket.org") { return "bitbucket.org" }
        return "unknown host"
    }

    func acceptHostKey() async {
        showHostKeyPrompt = false
        let host = hostKeyHost
        guard !host.isEmpty, host != "unknown host" else { return }
        do {
            try await git.addHostToKnownHosts(host: host)
            if let op = pendingOperationAfterHostKey {
                pendingOperationAfterHostKey = nil
                await op()
            }
        } catch {
            showToast(title: "Failed to add host key", detail: error.localizedDescription, style: .error)
        }
    }

    func rejectHostKey() {
        showHostKeyPrompt = false
        hostKeyHost = ""
        pendingOperationAfterHostKey = nil
    }

    // MARK: - Conflict Management (Rebase / Merge / Stash)

    func checkForRebaseConflict(errorMessage: String? = nil) async {
        do {
            if let state = try await git.rebaseState() {
                rebaseState = state
                conflictType = .rebase
                rebaseCommitMessage = await git.rebaseCommitMessage()
                if errorMessage != nil {
                    if !state.conflictedFiles.isEmpty {
                        showToast(title: "Rebase Conflict", detail: "There are merge conflicts that need to be resolved", style: .error)
                    } else {
                        showToast(title: "Rebase Failed", detail: errorMessage ?? "Unknown error", style: .error)
                    }
                }
                await loadAll()
            } else {
                if let msg = errorMessage {
                    operationError = msg
                }
            }
        } catch {
            if let msg = errorMessage {
                operationError = msg
            }
        }
    }

    func checkForMergeOrStashConflict(errorMessage: String, type: ConflictType) async {
        do {
            let conflicts = try await git.conflictedFiles()
            if !conflicts.isEmpty {
                conflictType = type
                mergeConflictedFiles = conflicts
                mergeResolvedFiles = (try? await git.resolvedConflictFiles()) ?? []
                if case .merge = type {
                    mergeCommitMessage = await git.mergeCommitMessage()
                }
                showToast(title: type.title, detail: "There are merge conflicts that need to be resolved", style: .error)
                await loadAll()
            } else {
                operationError = errorMessage
            }
        } catch {
            operationError = errorMessage
        }
    }

    func refreshConflictState() async {
        switch conflictType {
        case .rebase:
            do {
                rebaseState = try await git.rebaseState()
                if rebaseState != nil {
                    rebaseCommitMessage = await git.rebaseCommitMessage()
                } else {
                    conflictType = nil
                }
            } catch {}
        case .merge, .stashApply:
            do {
                mergeConflictedFiles = try await git.conflictedFiles()
                mergeResolvedFiles = (try? await git.resolvedConflictFiles()) ?? []
                if mergeConflictedFiles.isEmpty && mergeResolvedFiles.isEmpty {
                    conflictType = nil
                    mergeConflictedFiles = []
                    mergeResolvedFiles = []
                }
            } catch {}
        case nil:
            break
        }
    }

    /// Legacy compatibility: refresh rebase state only
    func refreshRebaseState() async {
        await refreshConflictState()
    }

    func markFileResolved(_ file: ConflictFile) async {
        do {
            try await git.markConflictResolved(path: file.path)
            await refreshConflictState()
            await refreshStatusAndGraph()
        } catch {
            showToast(title: "Mark Resolved Failed", detail: error.localizedDescription, style: .error)
        }
    }

    func markFileConflicted(path: String) async {
        do {
            try await git.markFileConflicted(path: path)
            await refreshConflictState()
            await refreshStatusAndGraph()
        } catch {
            showToast(title: "Mark Conflicted Failed", detail: error.localizedDescription, style: .error)
        }
    }

    func markAllFilesResolved() async {
        do {
            try await git.markAllConflictsResolved()
            await refreshConflictState()
            await refreshStatusAndGraph()
        } catch {
            showToast(title: "Mark All Resolved Failed", detail: error.localizedDescription, style: .error)
        }
    }

    func rebaseContinue() async {
        operationInProgress = true
        do {
            try await git.rebaseContinue(message: rebaseCommitMessage.isEmpty ? nil : rebaseCommitMessage)
            rebaseState = nil
            conflictType = nil
            rebaseCommitMessage = ""
            conflictMergeFile = nil
            showConflictMergeView = false
            showToast(title: "Rebase Complete", style: .success)
            await loadAll()
        } catch {
            await checkForRebaseConflict(errorMessage: error.localizedDescription)
        }
        operationInProgress = false
    }

    func rebaseSkip() async {
        operationInProgress = true
        do {
            try await git.rebaseSkip()
            rebaseState = nil
            conflictType = nil
            conflictMergeFile = nil
            showConflictMergeView = false
            await loadAll()
            await refreshConflictState()
            if rebaseState == nil && conflictType == nil {
                showToast(title: "Rebase Complete", style: .success)
            }
        } catch {
            await checkForRebaseConflict(errorMessage: error.localizedDescription)
        }
        operationInProgress = false
    }

    func rebaseAbort() async {
        operationInProgress = true
        do {
            try await git.rebaseAbort()
            clearConflictState()
            showToast(title: "Rebase Aborted", style: .info)
            await loadAll()
        } catch {
            showToast(title: "Abort Failed", detail: error.localizedDescription, style: .error)
        }
        operationInProgress = false
    }

    // MARK: - Merge Conflict Actions

    func mergeContinue() async {
        operationInProgress = true
        do {
            let msg = mergeCommitMessage.isEmpty ? nil : mergeCommitMessage
            if let msg {
                try await git.commit(message: msg)
            } else {
                // Use default MERGE_MSG
                let defaultMsg = await git.mergeCommitMessage()
                try await git.commit(message: defaultMsg.isEmpty ? "Merge commit" : defaultMsg)
            }
            clearConflictState()
            showToast(title: "Merge Complete", style: .success)
            await loadAll()
        } catch {
            showToast(title: "Merge Commit Failed", detail: error.localizedDescription, style: .error)
        }
        operationInProgress = false
    }

    func mergeAbort() async {
        operationInProgress = true
        do {
            try await git.mergeAbort()
            clearConflictState()
            showToast(title: "Merge Aborted", style: .info)
            await loadAll()
        } catch {
            showToast(title: "Abort Failed", detail: error.localizedDescription, style: .error)
        }
        operationInProgress = false
    }

    // MARK: - Stash Conflict Actions

    func stashConflictAbort() async {
        operationInProgress = true
        do {
            try await git.stashConflictAbort()
            clearConflictState()
            showToast(title: "Stash Apply Aborted", style: .info)
            await loadAll()
        } catch {
            showToast(title: "Abort Failed", detail: error.localizedDescription, style: .error)
        }
        operationInProgress = false
    }

    // MARK: - General Conflict Continue/Abort (dispatches based on type)

    func conflictContinue() async {
        switch conflictType {
        case .rebase:
            await rebaseContinue()
        case .merge:
            await mergeContinue()
        case .stashApply:
            // For stash, "continue" means all conflicts are resolved - just clear state
            clearConflictState()
            showToast(title: "Stash Apply Complete", style: .success)
            await loadAll()
        case nil:
            break
        }
    }

    func conflictAbort() async {
        switch conflictType {
        case .rebase:
            await rebaseAbort()
        case .merge:
            await mergeAbort()
        case .stashApply:
            await stashConflictAbort()
        case nil:
            break
        }
    }

    private func clearConflictState() {
        rebaseState = nil
        conflictType = nil
        rebaseCommitMessage = ""
        mergeCommitMessage = ""
        mergeConflictedFiles = []
        mergeResolvedFiles = []
        conflictMergeFile = nil
        showConflictMergeView = false
    }

    func openConflictMerge(_ file: ConflictFile) async {
        conflictMergeFile = file
        do {
            let sides = try await git.readConflictSides(path: file.path)
            conflictSides = sides
            buildInitialOutput()
            showConflictMergeView = true
        } catch {
            showToast(title: "Cannot Open Conflict", detail: error.localizedDescription, style: .error)
        }
    }

    func closeConflictMerge() {
        showConflictMergeView = false
        conflictMergeFile = nil
        conflictSides = nil
        conflictOutputLines = []
    }

    private func buildInitialOutput() {
        guard let sides = conflictSides else { return }
        let oursLines = sides.oursContent.components(separatedBy: "\n")
        let theirsLines = sides.theirsContent.components(separatedBy: "\n")

        var output: [String] = []
        var oursIdx = 0
        var theirsIdx = 0

        let maxLines = max(oursLines.count, theirsLines.count)
        let conflictRanges = sides.markers.map { ($0.oursRange, $0.theirsRange) }

        func isInConflict(_ idx: Int) -> (Bool, Int?) {
            for (i, (oursR, _)) in conflictRanges.enumerated() {
                if oursR.contains(idx) { return (true, i) }
            }
            return (false, nil)
        }

        while oursIdx < maxLines {
            let (inConflict, regionIdx) = isInConflict(oursIdx)
            if inConflict, let ri = regionIdx {
                let oursR = sides.markers[ri].oursRange
                let theirsR = sides.markers[ri].theirsRange
                for i in oursR { output.append(i < oursLines.count ? oursLines[i] : "") }
                _ = theirsR
                oursIdx = oursR.upperBound
                theirsIdx = theirsR.upperBound
            } else {
                if oursIdx < oursLines.count {
                    output.append(oursLines[oursIdx])
                }
                oursIdx += 1
                theirsIdx += 1
            }
        }
        conflictOutputLines = output
    }

    struct RegionChoice: Equatable {
        var oursChecked: Bool
        var theirsChecked: Bool
    }

    var regionChoices: [Int: RegionChoice] = [:]

    func toggleOurs(_ regionIndex: Int) {
        var choice = regionChoices[regionIndex] ?? RegionChoice(oursChecked: false, theirsChecked: false)
        choice.oursChecked.toggle()
        regionChoices[regionIndex] = choice
        rebuildOutputFromChoices()
    }

    func toggleTheirs(_ regionIndex: Int) {
        var choice = regionChoices[regionIndex] ?? RegionChoice(oursChecked: false, theirsChecked: false)
        choice.theirsChecked.toggle()
        regionChoices[regionIndex] = choice
        rebuildOutputFromChoices()
    }

    func resetConflictChoices() {
        regionChoices = [:]
        buildInitialOutput()
    }

    private func rebuildOutputFromChoices() {
        guard let sides = conflictSides else { return }
        let oursLines = sides.oursContent.components(separatedBy: "\n")
        let theirsLines = sides.theirsContent.components(separatedBy: "\n")

        var output: [String] = []
        var oursIdx = 0

        while oursIdx < oursLines.count {
            var handledRegion = false
            for (i, marker) in sides.markers.enumerated() {
                if marker.oursRange.lowerBound == oursIdx {
                    let choice = regionChoices[i]
                    let includeOurs = choice?.oursChecked ?? false
                    let includeTheirs = choice?.theirsChecked ?? false

                    if includeOurs {
                        for j in marker.oursRange {
                            if j < oursLines.count { output.append(oursLines[j]) }
                        }
                    }
                    if includeTheirs {
                        for j in marker.theirsRange {
                            if j < theirsLines.count { output.append(theirsLines[j]) }
                        }
                    }
                    if !includeOurs && !includeTheirs {
                        for j in marker.oursRange {
                            if j < oursLines.count { output.append(oursLines[j]) }
                        }
                    }

                    oursIdx = marker.oursRange.upperBound
                    handledRegion = true
                    break
                }
            }
            if !handledRegion {
                output.append(oursLines[oursIdx])
                oursIdx += 1
            }
        }
        conflictOutputLines = output
    }

    func saveConflictResolution() async {
        guard let file = conflictMergeFile else { return }
        let content = conflictOutputLines.joined(separator: "\n")
        do {
            try await git.saveConflictResolution(path: file.path, content: content)
            try await git.markConflictResolved(path: file.path)
            showToast(title: "Saved", detail: "\(file.path) marked as resolved", style: .success)
            showConflictMergeView = false
            conflictMergeFile = nil
            conflictSides = nil
            conflictOutputLines = []
            regionChoices = [:]
            await refreshRebaseState()
            await refreshStatusAndGraph()
        } catch {
            showToast(title: "Save Failed", detail: error.localizedDescription, style: .error)
        }
    }

    // MARK: - Toast

    func showToast(title: String, detail: String = "", style: ToastMessage.ToastStyle = .error) {
        toastMessage = ToastMessage(title: title, detail: detail, style: style)
    }

    func dismissToast() {
        toastMessage = nil
    }

    /// Open the app's Settings window
    func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func toggleSection(_ section: String) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
        saveCollapsedSections()
    }

    func isSectionCollapsed(_ section: String) -> Bool {
        collapsedSections.contains(section)
    }

    // MARK: - GitLab MR Operations

    private func getGitLabService() -> GitLabService {
        if let svc = gitlabService { return svc }
        let svc = GitLabService(repoPath: repoPath)
        gitlabService = svc
        return svc
    }

    func loadMergeRequests() async {
        guard await GitLabService.isConfigured else {
            mergeRequests = []
            mrError = nil
            return
        }

        isMRLoading = true
        mrError = nil
        do {
            let mrs = try await getGitLabService().listMergeRequests(state: mrStateFilter)
            mergeRequests = mrs
        } catch {
            mrError = error.localizedDescription
            mergeRequests = []
        }
        isMRLoading = false
    }

    func setMRFilter(_ filter: MRStateFilter) async {
        mrStateFilter = filter
        await loadMergeRequests()
    }

    func performMRMerge(mr: GitLabMR) async {
        isMRMerging = true
        mrMergingStatus = "Rebase & Merge !\(mr.iid) \(mr.title) …"
        do {
            try await getGitLabService().performRebaseAndMerge(
                mrIID: mr.iid,
                sourceBranch: mr.sourceBranch,
                targetBranch: mr.targetBranch
            )
            showToast(title: "MR Merged", detail: "!\(mr.iid) \(mr.title)", style: .success)
            await loadMergeRequests()
            await loadAll()
        } catch {
            showToast(title: "MR Merge Failed", detail: error.localizedDescription, style: .error)
        }
        isMRMerging = false
        mrMergingStatus = ""
    }

    func openMRInBrowser(_ mr: GitLabMR) {
        if let url = URL(string: mr.webUrl) {
            NSWorkspace.shared.open(url)
        }
    }
}

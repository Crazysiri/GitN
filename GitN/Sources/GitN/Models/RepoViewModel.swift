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
    var knownRemoteTags: Set<String> = []
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
    var selectedStash: StashInfo?
    var diffFiles: [DiffFile] = []
    var fileDiffContent: String = ""
    var parsedDiff: ParsedDiff?
    var selectedDiffFile: DiffFile?
    /// True when the selected file exceeds maxDiffFileSize.
    var isFileTooLarge = false
    var fileTooLargeSizeMB: String = ""

    var fileStatuses: [FileStatus] = []
    var isStageOperationInProgress = false
    var selectedFilePaths: Set<String> = []
    /// Anchor path for Shift+click range selection.
    var lastSelectedFilePath: String?
    var commitSummary: String = ""
    var commitDescription: String = ""

    var commitMessage: String {
        if commitDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return commitSummary
        }
        return commitSummary + "\n\n" + commitDescription
    }

    var showTerminal: Bool = false {
        didSet {
            UserDefaults.standard.set(showTerminal, forKey: "GitN.showTerminal.\(repoPath)")
        }
    }
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

    @MainActor
    func openFilePreview(path: String, commitHash: String?) async {
        var content = ""
        if let hash = commitHash {
            content = (try? await git.fileContent(atCommit: hash, path: path)) ?? ""
        }
        if content.isEmpty {
            let fullPath = (repoPath as NSString).appendingPathComponent(path)
            content = (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
        }

        let fileName = (path as NSString).lastPathComponent
        let view: AnyView = path.isMarkdownFile
            ? AnyView(MarkdownPreviewView(title: fileName, content: content))
            : AnyView(SourcePreviewView(title: fileName, content: content, language: path.sourceLanguage))

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = fileName
        window.setContentSize(NSSize(width: 800, height: 600))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
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
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        do {
            try await git.stageFiles(paths)
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
        await selectFirstUnstagedOrKeep()
    }

    func unstageFiles(_ paths: [String]) async {
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        do {
            try await git.unstageFiles(paths)
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
        await selectFirstUnstagedOrKeep()
    }

    /// Selects the first file in the unstaged area after a staging operation.
    /// If no unstaged files remain, the current diff is preserved unchanged.
    private func selectFirstUnstagedOrKeep() async {
        guard selectedCommit?.isUncommitted == true || isInConflict else { return }
        guard let firstStatus = fileStatuses.first(where: \.hasUnstagedChanges) else { return }
        let diffFile = diffFiles.first(where: { $0.path == firstStatus.path })
            ?? DiffFile(additions: 0, deletions: 0, path: firstStatus.path)
        selectedFilePaths = [firstStatus.path]
        await selectDiffFile(diffFile, context: .unstaged)
    }

    /// - Parameters:
    ///   - path: The file path that was clicked.
    ///   - isMulti: `true` when ⌘ is held (toggle individual item).
    ///   - isRange: `true` when ⇧ is held (select range from anchor).
    ///   - orderedPaths: The full ordered list of visible paths in the
    ///     section (staged / unstaged) so we can compute the range.
    func toggleFileSelection(_ path: String, isMulti: Bool, isRange: Bool = false, orderedPaths: [String] = []) {
        if isRange, let anchor = lastSelectedFilePath, !orderedPaths.isEmpty {
            // Shift+click: select the range [anchor … path] inclusive.
            if let anchorIdx = orderedPaths.firstIndex(of: anchor),
               let targetIdx = orderedPaths.firstIndex(of: path) {
                let lo = min(anchorIdx, targetIdx)
                let hi = max(anchorIdx, targetIdx)
                let range = orderedPaths[lo...hi]
                selectedFilePaths = Set(range)
            } else {
                selectedFilePaths = [path]
                lastSelectedFilePath = path
            }
            // Don't update the anchor on shift-click so further
            // shift-clicks extend / shrink from the original anchor.
        } else if isMulti {
            if selectedFilePaths.contains(path) {
                selectedFilePaths.remove(path)
            } else {
                selectedFilePaths.insert(path)
            }
            lastSelectedFilePath = path
        } else {
            selectedFilePaths = [path]
            lastSelectedFilePath = path
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

    // MARK: - Hosted Code Review
    var mergeRequests: [CodeReviewItem] = []
    var mrStateFilter: CodeReviewFilter = .opened
    var isMRLoading = false
    var mrError: String?
    var isMRMerging = false
    var mrMergingStatus: String = ""

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
    private var toastAutoDismissTask: Task<Void, Never>?

    private var fileWatcher: RepositoryFileWatcher?
    private var isRefreshing = false
    private var refreshTimer: Timer?
    private var lastFetchDate: Date?

    var remoteBranchGroups: [String: [BranchInfo]] {
        Dictionary(grouping: remoteBranches) { branch in
            let parts = branch.name.split(separator: "/", maxSplits: 1)
            return parts.first.map(String.init) ?? branch.name
        }
    }

    private var preferredCodeHostingRemote: RemoteInfo? {
        if let origin = remotes.first(where: { $0.name == "origin" && CodeHostingProvider(remoteURL: $0.url) != .unknown }) {
            return origin
        }
        return remotes.first(where: { CodeHostingProvider(remoteURL: $0.url) != .unknown })
    }

    var codeHostingProvider: CodeHostingProvider {
        guard let remote = preferredCodeHostingRemote else { return .unknown }
        return CodeHostingProvider(remoteURL: remote.url)
    }

    var mergeRequestsSectionTitle: String {
        codeHostingProvider.sectionTitle
    }

    var mergeRequestsEmptyStateText: String {
        "No \(codeHostingProvider.emptyStateDisplayName)"
    }

    var mergeActionTitle: String? {
        codeHostingProvider.mergeActionTitle
    }

    init(path: String, name: String) {
        self.repoPath = path
        self.repoName = name
        self.git = GitService(repoPath: path)
        // 恢复上次 terminal 的打开状态
        self.showTerminal = UserDefaults.standard.bool(forKey: "GitN.showTerminal.\(path)")
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

    // MARK: - Periodic Refresh Timer

    /// Start periodic refresh timer that fetches from remote every 30 seconds
    /// Only refreshes the current tab (doesn't reload all data, just fetches)
    func startPeriodicRefresh() {
        stopPeriodicRefresh() // Ensure no duplicate timers
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performPeriodicFetch()
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Perform a lightweight fetch (only git fetch, no full reload)
    /// This is called by the periodic timer and should be lightweight
    private func performPeriodicFetch() async {
        await fetchIfNeeded()
    }

    /// Perform a fetch only if at least 30 seconds have passed since the last fetch.
    func fetchIfNeeded() async {
        // Don't fetch if already loading or if an operation is in progress
        guard !isLoading, !operationInProgress else { return }

        // Throttle: skip if last fetch was less than 30s ago
        if let last = lastFetchDate, Date().timeIntervalSince(last) < 30 {
            return
        }

        do {
            try await git.fetch()
            lastFetchDate = Date()
        } catch {
            // Silently ignore fetch errors
        }
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
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

            // Only re-diff if the selected file still has changes in the current context
            // (avoids blanking the diff when e.g. a file was just fully staged).
            if let file = selectedDiffFile, selectedCommit?.isUncommitted == true,
               let status = sts.first(where: { $0.path == file.path }) {
                let contextStillValid: Bool
                switch currentDiffContext {
                case .staged:   contextStillValid = status.hasStagedChanges
                case .unstaged: contextStillValid = status.hasUnstagedChanges
                case .committed: contextStillValid = true
                }
                if contextStillValid {
                    let fullPath = (repoPath as NSString).appendingPathComponent(file.path)
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: fullPath))?[.size] as? Int ?? 0
                    if fileSize <= Self.maxDiffFileSize {
                        await selectDiffFile(file, context: currentDiffContext)
                    }
                }
            }
        } catch {}
    }

    func refreshWithSync() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // First, fetch and prune remote branches and tags
            try await git.fetchWithPrune()
        } catch {
            // If fetch fails, still continue with loadAll
            // The error will be shown if needed
        }

        // Get remote tags and delete local tags that don't exist on remote
        await deleteLocalTagsNotOnRemote()

        // After fetch, load all data
        await loadAll()
    }

    /// Fetch remote tags from all configured remotes and update knownRemoteTags.
    /// Best-effort: silently ignores network errors.
    private func refreshKnownRemoteTags() async {
        guard !remotes.isEmpty else { return }
        var fetched: Set<String> = []
        for remote in remotes {
            if let tags = try? await git.remoteTags(remoteName: remote.name) {
                fetched.formUnion(tags)
            }
        }
        knownRemoteTags = fetched
    }

    private func deleteLocalTagsNotOnRemote() async {
        // Load remotes first
        do {
            remotes = try await git.remotes()
        } catch {
            return
        }

        // If no remotes, don't delete anything
        guard !remotes.isEmpty else { return }

        await refreshKnownRemoteTags()
        let remoteTags = knownRemoteTags

        // Get all local tags
        do {
            let localTags = try await git.tags()

            // Delete local tags that don't exist on remote
            // Note: --prune-tags only removes tags that were fetched from remote.
            // This ensures we also remove purely local tags that don't exist on remote.
            var deletedCount = 0
            for localTag in localTags {
                if !remoteTags.contains(localTag) {
                    do {
                        try await git.deleteTag(name: localTag)
                        deletedCount += 1
                    } catch {
                        // Continue with other tags if one fails
                        print("Failed to delete tag \(localTag): \(error.localizedDescription)")
                    }
                }
            }

            if deletedCount > 0 {
                print("Deleted \(deletedCount) local tag(s) that don't exist on remote")
            }
        } catch {
            // If we can't get local tags, skip deletion
            print("Failed to get local tags: \(error.localizedDescription)")
        }
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

            // Refresh remote tags in background (best-effort, doesn't block UI load)
            Task { await refreshKnownRemoteTags() }

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
        selectedStash = nil
        selectedDiffFile = nil
        fileDiffContent = ""
        parsedDiff = nil
        selectedFilePaths = []
        do {
            if commit.isUncommitted {
                refreshUncommittedDiffFiles()
                // Auto-select the first unstaged file, falling back to the first staged file
                let firstStatus = fileStatuses.first(where: \.hasUnstagedChanges)
                    ?? fileStatuses.first(where: \.hasStagedChanges)
                if let status = firstStatus {
                    let context: DiffContext = status.hasUnstagedChanges ? .unstaged : .staged
                    let diffFile = diffFiles.first(where: { $0.path == status.path })
                        ?? DiffFile(additions: 0, deletions: 0, path: status.path)
                    selectedFilePaths = [status.path]
                    await selectDiffFile(diffFile, context: context)
                }
            } else {
                diffFiles = try await git.diffDetail(hash: commit.hash)
                if let first = diffFiles.first {
                    await selectDiffFile(first, context: .committed)
                }
            }
        } catch {
            diffFiles = []
        }
    }

    private func refreshUncommittedDiffFiles() {
        diffFiles = fileStatuses.map { status in
            DiffFile(additions: 0, deletions: 0, path: status.path)
        }
    }

    enum DiffContext { case staged, unstaged, committed }
    var currentDiffContext: DiffContext = .committed

    /// Max file size (in bytes) for which we compute a full diff.
    /// Files larger than this get a placeholder to avoid OOM on huge files
    /// (e.g. Xcode project.pbxproj).
    private static let maxDiffFileSize: Int = 1_024_000  // ~1 MB

    func selectDiffFile(_ file: DiffFile, context: DiffContext = .committed, ignoreSize: Bool = false) async {
        let isUncommitted = selectedCommit?.isUncommitted == true || isInConflict
        guard selectedCommit != nil || selectedStash != nil || isInConflict else { return }
        selectedDiffFile = file
        currentDiffContext = context
        isFileTooLarge = false
        fileTooLargeSizeMB = ""
        do {
            if let stash = selectedStash {
                fileDiffContent = try await git.stashFileDiff(stash.index, path: file.path)
                if fileDiffContent.isEmpty {
                    fileDiffContent = "No changes in this file"
                    parsedDiff = nil
                } else {
                    parsedDiff = DiffParserEngine.parse(fileDiffContent)
                    if parsedDiff == nil || parsedDiff?.hunks.isEmpty == true {
                        parsedDiff = nil
                    }
                }
            } else if isUncommitted {
                // Guard against huge files that would blow up memory
                if !ignoreSize {
                    let fullPath = (repoPath as NSString).appendingPathComponent(file.path)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int, size > Self.maxDiffFileSize {
                        let sizeMB = String(format: "%.1f", Double(size) / 1_048_576.0)
                        isFileTooLarge = true
                        fileTooLargeSizeMB = sizeMB
                        fileDiffContent = ""
                        parsedDiff = nil
                        return
                    }
                }

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
                parsedDiff = DiffParserEngine.parse(fileDiffContent)
            } else if let commit = selectedCommit {
                fileDiffContent = try await git.fileDiff(hash: commit.hash, path: file.path)
                parsedDiff = DiffParserEngine.parse(fileDiffContent)
            }
        } catch {
            fileDiffContent = "Failed to load diff"
            parsedDiff = nil
        }
    }

    func forceLoadFileDiff() async {
        guard let file = selectedDiffFile else { return }
        await selectDiffFile(file, context: currentDiffContext, ignoreSize: true)
    }

    /// Open the currently selected file in the system's external diff tool
    /// (e.g. FileMerge via `opendiff`, or whatever `git difftool` is configured to use).
    func openExternalDiffTool() {
        guard let file = selectedDiffFile else { return }
        let path = file.path

        Task.detached { [repoPath, currentDiffContext, selectedCommit] in
            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

            if selectedCommit?.isUncommitted == true {
                switch currentDiffContext {
                case .staged:
                    process.arguments = ["difftool", "--cached", "--no-prompt", "--", path]
                case .unstaged:
                    process.arguments = ["difftool", "--no-prompt", "--", path]
                case .committed:
                    process.arguments = ["difftool", "--no-prompt", "--", path]
                }
            } else if let commit = selectedCommit {
                process.arguments = ["difftool", "\(commit.hash)~1", commit.hash, "--no-prompt", "--", path]
            } else {
                return
            }

            try? process.run()
        }
    }

    var isAmend = false
    var isGeneratingAICommit = false

    /// Generate commit message from staged diff using the selected AI CLI tool
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
            case .notFound(let tool):
                showToast(title: "\(tool.displayName) Not Found", detail: error.localizedDescription, style: .error)
            case .apiKeyMissing:
                showToast(title: "AI Setup Required", detail: error.localizedDescription, style: .error)
                openSettings()
            case .authorizationRequired(let tool):
                showToast(title: "\(tool.displayName) Login Required", detail: error.localizedDescription, style: .error)
                openSettings()
            case .agentFailed, .emptyResponse:
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
            case .notFound(let tool):
                showToast(title: "\(tool.displayName) Not Found", detail: error.localizedDescription, style: .error)
            case .apiKeyMissing:
                showToast(title: "AI Setup Required", detail: error.localizedDescription, style: .error)
                openSettings()
            case .authorizationRequired(let tool):
                showToast(title: "\(tool.displayName) Login Required", detail: error.localizedDescription, style: .error)
                openSettings()
            case .agentFailed, .emptyResponse:
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
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        do {
            try await git.stageFile(path)
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
    }

    func unstageFile(_ path: String) async {
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        do {
            try await git.unstageFile(path)
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
    }

    func stageAllFiles() async {
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        let unstaged = fileStatuses.filter(\.hasUnstagedChanges)
        do {
            try await git.stageFiles(unstaged.map(\.path))
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
        // No unstaged files remain — preserve the last displayed diff
    }

    func unstageAllFiles() async {
        guard !isStageOperationInProgress else { return }
        isStageOperationInProgress = true
        defer { isStageOperationInProgress = false }
        let staged = fileStatuses.filter(\.hasStagedChanges)
        do {
            try await git.unstageFiles(staged.map(\.path))
            fileStatuses = try await git.status()
            refreshUncommittedDiffFiles()
        } catch {}
        await selectFirstUnstagedOrKeep()
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

    /// The default pull mode persisted across sessions.
    /// These are the selectable modes shown in the Pull dropdown menu.
    enum PullMode: String, CaseIterable, Identifiable {
        case pullFF         = "pullFF"          // --ff-only
        case pull           = "pull"            // default (ff if possible)
        case pullRebase     = "pullRebase"      // --rebase

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pullFF:     return "Pull (fast-forward only)"
            case .pull:       return "Pull (fast-forward if possible)"
            case .pullRebase: return "Pull (rebase)"
            }
        }
    }

    var defaultPullMode: PullMode = PullMode(rawValue: UserDefaults.standard.string(forKey: "GitN.defaultPullMode") ?? "") ?? .pull {
        didSet {
            UserDefaults.standard.set(defaultPullMode.rawValue, forKey: "GitN.defaultPullMode")
        }
    }

    /// Show force-pull confirmation dialog
    var showForcePullConfirm = false
    /// Show force-push confirmation dialog
    var showForcePushConfirm = false

    func performFetch() async {
        await performRemoteOperation { try await $0.git.fetch() }
    }

    /// Execute pull using the current default mode.
    func performPull() async {
        await performPull(mode: defaultPullMode)
    }

    func performPull(mode: PullMode) async {
        operationInProgress = true
        operationError = nil
        do {
            switch mode {
            case .pull:
                try await git.pull()
            case .pullFF:
                try await git.pullFF()
            case .pullRebase:
                try await git.pullRebase()
            }
            await loadAll()
            showToast(title: "Pull Complete", detail: "\(currentBranch) updated", style: .success)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performPull(mode: mode)
                }
                showHostKeyPrompt = true
            } else {
                showToast(title: "Pull Failed", detail: msg, style: .error)
            }
        }
        operationInProgress = false
    }

    func performForcePull() async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.pullForce()
            await loadAll()
            showToast(title: "Pull Complete", detail: "\(currentBranch) updated (force)", style: .success)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performForcePull()
                }
                showHostKeyPrompt = true
            } else {
                showToast(title: "Pull Failed", detail: msg, style: .error)
            }
        }
        operationInProgress = false
    }

    /// Execute normal push.
    func performPush() async {
        let hasUpstream = localBranches.first(where: { $0.isCurrent })?.upstream != nil
        if !hasUpstream {
            pushUpstreamRemote = "origin"
            pushUpstreamBranch = currentBranch
            showPushUpstreamPrompt = true
            return
        }
        operationInProgress = true
        operationError = nil
        do {
            try await git.push()
            await loadAll()
            showToast(title: "Push Complete", detail: "\(currentBranch) pushed", style: .success)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performPush()
                }
                showHostKeyPrompt = true
            } else {
                showToast(title: "Push Failed", detail: msg, style: .error)
            }
        }
        operationInProgress = false
    }

    func performForcePush() async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.pushForce()
            await loadAll()
            showToast(title: "Push Complete", detail: "\(currentBranch) pushed (force)", style: .success)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performForcePush()
                }
                showHostKeyPrompt = true
            } else {
                showToast(title: "Push Failed", detail: msg, style: .error)
            }
        }
        operationInProgress = false
    }

    func performPushWithUpstream(remote: String, branch: String) async {
        showPushUpstreamPrompt = false
        operationInProgress = true
        operationError = nil
        do {
            try await git.push(remoteName: remote, branchName: branch, setUpstream: true)
            await loadAll()
            showToast(title: "Push Complete", detail: "\(branch) pushed to \(remote)", style: .success)
        } catch {
            let msg = error.localizedDescription
            if msg.contains("Host key verification failed") || msg.contains("host key") {
                let host = extractHostFromError(msg)
                hostKeyHost = host
                pendingOperationAfterHostKey = { [weak self] in
                    guard let self else { return }
                    await self.performPushWithUpstream(remote: remote, branch: branch)
                }
                showHostKeyPrompt = true
            } else {
                showToast(title: "Push Failed", detail: msg, style: .error)
            }
        }
        operationInProgress = false
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

    /// Apply a specific stash (apply without deleting)
    func performStashApplyAt(stash: StashInfo) async {
        let idx = stashNumericIndex(stash)
        operationInProgress = true
        operationError = nil
        do {
            try await git.stashApply(index: idx)
            await loadAll()
            showToast(title: "Stash Applied", detail: stash.message, style: .success)
        } catch {
            await checkForMergeOrStashConflict(errorMessage: error.localizedDescription, type: .stashApply)
        }
        operationInProgress = false
    }

    /// Pop a specific stash (apply and delete)
    func performStashPopAt(stash: StashInfo) async {
        let idx = stashNumericIndex(stash)
        operationInProgress = true
        operationError = nil
        do {
            try await git.stashPop(index: idx)
            await loadAll()
            showToast(title: "Stash Popped", detail: stash.message, style: .success)
        } catch {
            await checkForMergeOrStashConflict(errorMessage: error.localizedDescription, type: .stashApply)
        }
        operationInProgress = false
    }

    /// Drop (delete) a specific stash
    func performStashDrop(stash: StashInfo) async {
        let idx = stashNumericIndex(stash)
        operationInProgress = true
        operationError = nil
        do {
            try await git.stashDrop(index: idx)
            await loadAll()
            showToast(title: "Stash Deleted", detail: stash.message, style: .success)
        } catch {
            operationError = "Stash drop failed: \(error.localizedDescription)"
        }
        operationInProgress = false
    }

    /// Extract numeric index from stash ref string like "stash@{0}"
    private func stashNumericIndex(_ stash: StashInfo) -> Int {
        if let range = stash.index.range(of: #"\d+"#, options: .regularExpression) {
            return Int(stash.index[range]) ?? 0
        }
        return 0
    }

    /// Pull a specific branch. If current, just pull. If not, try fast-forward fetch first,
    /// then fall back to stash → checkout → pull → checkout back → pop stash.
    func performPullBranch(_ branch: BranchInfo) async {
        if branch.isCurrent {
            await performPull()
            return
        }

        // Determine remote name from upstream or default to "origin"
        let remoteName: String
        if let upstream = branch.upstream {
            remoteName = String(upstream.split(separator: "/", maxSplits: 1).first ?? "origin")
        } else {
            remoteName = "origin"
        }

        operationInProgress = true
        operationError = nil

        // Try fast-forward fetch first (git fetch origin branchName:branchName)
        do {
            try await git.fetchBranchFastForward(remoteName: remoteName, branchName: branch.name)
            await loadAll()
            showToast(title: "Pull Complete", detail: "\(branch.name) updated (fast-forward)", style: .success)
            operationInProgress = false
            return
        } catch {
            // Fast-forward not possible, fall back to stash/checkout/pull flow
        }

        // Fall back: stash → checkout → pull → checkout back → pop stash
        let originalBranch = currentBranch
        let hasChanges = !fileStatuses.isEmpty

        do {
            // 1. Stash if there are uncommitted changes
            if hasChanges {
                try await git.stashSave(message: "Auto-stash before pulling \(branch.name)")
            }

            // 2. Checkout target branch
            try await git.checkoutBranch(branch.name)

            // 3. Pull
            try await git.pull()

            // 4. Checkout back to original branch
            try await git.checkoutBranch(originalBranch)

            // 5. Pop stash if we stashed
            if hasChanges {
                try await git.stashPop()
            }

            await loadAll()
            showToast(title: "Pull Complete", detail: "\(branch.name) updated", style: .success)
        } catch {
            // Try to recover: checkout back to original branch
            try? await git.checkoutBranch(originalBranch)
            if hasChanges {
                try? await git.stashPop()
            }
            showToast(title: "Pull Failed", detail: "Pull \(branch.name) failed: \(error.localizedDescription)", style: .error)
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

    func performDeleteTag(_ name: String) async {
        await performRemoteOperation { try await $0.git.deleteTag(name: name) }
    }

    func performPushTag(name: String, remote: String = "origin") async {
        await performRemoteOperation { try await $0.git.pushTag(name: name, remote: remote) }
    }

    func performDeleteRemoteTag(name: String, remote: String = "origin") async {
        await performRemoteOperation { try await $0.git.deleteRemoteTag(name: name, remote: remote) }
    }

    func getTagCommitHash(_ name: String) async throws -> String {
        return try await git.tagCommitHash(name: name)
    }

    func getTagMessage(_ name: String) async -> String? {
        return try? await git.tagMessage(name: name)
    }

    func performAnnotateTag(name: String, message: String) async {
        await performRemoteOperation { try await $0.git.annotateTag(name: name, message: message) }
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

    /// Get the full commit message (including description) for a commit by hash
    func getFullCommitMessage(hash: String) async -> String {
        do {
            return try await git.fullCommitMessage(hash: hash)
        } catch {
            return ""
        }
    }

    func performCreateBranchAt(name: String, commitHash: String) async {
        operationInProgress = true
        operationError = nil
        do {
            try await git.createBranchAt(name: name, commitHash: commitHash)
            await loadAll()
            showToast(title: "Branch Created", detail: "Created branch '\(name)'", style: .success)
        } catch {
            let msg = error.localizedDescription
            showToast(title: "Branch Creation Failed", detail: msg, style: .error)
        }
        operationInProgress = false
    }
    
    func getBranchCommitHash(_ branchName: String, isRemote: Bool = false) async throws -> String {
        return try await git.branchCommitHash(branchName, isRemote: isRemote)
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

    func scrollToCommitForTag(_ tagName: String) {
        // 查找 refs 中包含该 tag 的 commit
        if let commit = commits.first(where: { commit in
            commit.refs.contains { ref in
                ref.contains("tag:") && ref.contains(tagName)
            }
        }) {
            scrollToCommitHash = commit.hash
            Task { await selectCommit(commit) }
        }
    }
    
    func scrollToCommitForStash(_ stash: StashInfo) {
        Task { await selectStash(stash) }
    }
    
    func selectStash(_ stash: StashInfo) async {
        if isCompareMode { exitCompareMode() }
        selectedStash = stash
        selectedCommit = nil
        selectedDiffFile = nil
        fileDiffContent = ""
        parsedDiff = nil
        do {
            diffFiles = try await git.stashDiffFiles(stash.index)
        } catch {
            diffFiles = []
            showToast(title: "Failed to load stash diff", detail: error.localizedDescription, style: .error)
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
                showToast(title: "Operation Failed", detail: msg, style: .error)
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
        let oursLines = sides.oursLines
        let theirsLines = sides.theirsLines

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
        let oursLines = sides.oursLines
        let theirsLines = sides.theirsLines

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
        toastAutoDismissTask?.cancel()
        let message = ToastMessage(title: title, detail: detail, style: style)
        toastMessage = message
        let dismissID = message.id
        toastAutoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.toastMessage?.id == dismissID else { return }
            self.toastMessage = nil
            self.toastAutoDismissTask = nil
        }
    }

    func dismissToast() {
        toastAutoDismissTask?.cancel()
        toastAutoDismissTask = nil
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

    // MARK: - Hosted Code Review Operations

    private func getGitLabService() -> GitLabService {
        GitLabService(repoPath: repoPath, remoteName: preferredCodeHostingRemote?.name ?? "origin")
    }

    private func getGitHubService() -> GitHubService {
        GitHubService(repoPath: repoPath, remoteName: preferredCodeHostingRemote?.name ?? "origin")
    }

    func loadMergeRequests() async {
        isMRLoading = true
        mrError = nil
        do {
            switch codeHostingProvider {
            case .gitlab:
                guard GitLabService.isConfigured else {
                    mergeRequests = []
                    mrError = GitLabError.notConfigured.localizedDescription
                    isMRLoading = false
                    return
                }
                mergeRequests = try await getGitLabService().listMergeRequests(state: mrStateFilter)
            case .github:
                guard GitHubService.isConfigured else {
                    mergeRequests = []
                    mrError = GitHubError.notConfigured.localizedDescription
                    isMRLoading = false
                    return
                }
                mergeRequests = try await getGitHubService().listPullRequests(state: mrStateFilter)
            case .unknown:
                mergeRequests = []
                mrError = "The selected remote host is not supported yet."
            }
        } catch {
            mrError = error.localizedDescription
            mergeRequests = []
        }
        isMRLoading = false
    }

    func setMRFilter(_ filter: CodeReviewFilter) async {
        mrStateFilter = filter
        await loadMergeRequests()
    }

    func canPerformMerge(for review: CodeReviewItem) -> Bool {
        review.state == .opened && mergeActionTitle != nil
    }

    func performMRMerge(mr: CodeReviewItem) async {
        isMRMerging = true
        mrMergingStatus = "\(mergeActionTitle ?? "Merge") \(mr.numberDisplay) \(mr.title) ..."
        do {
            switch mr.provider {
            case .gitlab:
                try await getGitLabService().performRebaseAndMerge(
                    mrIID: mr.number,
                    sourceBranch: mr.sourceBranch,
                    targetBranch: mr.targetBranch
                )
            case .github:
                try await getGitHubService().performRebaseAndMerge(prNumber: mr.number)
            case .unknown:
                throw NSError(domain: "GitN", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected remote host is not supported yet."])
            }
            showToast(title: "\(codeHostingProvider.singularDisplayName) Merged", detail: "\(mr.numberDisplay) \(mr.title)", style: .success)
            await loadMergeRequests()
            await loadAll()
        } catch {
            showToast(title: "\(codeHostingProvider.singularDisplayName) Merge Failed", detail: error.localizedDescription, style: .error)
        }
        isMRMerging = false
        mrMergingStatus = ""
    }

    func openMRInBrowser(_ mr: CodeReviewItem) {
        if let url = URL(string: mr.webURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

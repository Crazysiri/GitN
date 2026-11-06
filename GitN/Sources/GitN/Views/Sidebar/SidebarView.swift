import SwiftUI

struct SidebarView: View {
    let viewModel: RepoViewModel
    @Environment(AppModel.self) private var appModel

    private static let animatedSectionItemLimit = 60
    private static let animatedRemoteDisclosureItemLimit = 120
    private static let fileSearchDebounceNanoseconds: UInt64 = 120_000_000

    @State private var showAddRemote = false
    @State private var newRemoteName = ""
    @State private var newRemoteURL = ""

    @State private var showEditRemote = false
    @State private var editingRemote: RemoteInfo?
    @State private var editRemoteName = ""
    @State private var editRemoteURL = ""

    @State private var showRenameBranch = false
    @State private var renamingBranch = ""
    @State private var renamedBranchName = ""

    @State private var showCreateTagAtBranch = false
    @State private var tagAtBranchHash = ""
    @State private var tagAtBranchName = ""

    @State private var showCreateBranchFrom = false
    @State private var branchFromHash = ""
    @State private var branchFromName = ""
    @State private var branchFromIsRemote = false
    @State private var newBranchFromName = ""

    @State private var showSetUpstream = false
    @State private var upstreamRemote = "origin"
    @State private var upstreamBranch = ""

    @State private var showMergeConfirm = false
    @State private var mergingMR: CodeReviewItem?

    @State private var collapsedFileFolders: Set<String> = []
    @State private var seenFileFolders: Set<String> = []
    @State private var expandingFileFolders: Set<String> = []
    @State private var collapsedRemotes: Set<String> = []
    @State private var collapsedLocalFolders: Set<String> = []
    @State private var collapsedRemoteFolders: Set<String> = []

    @State private var showAnnotateTag = false
    @State private var annotatingTagName = ""
    @State private var annotateTagMessage = ""

    @State private var showCreateBranchFromTag = false
    @State private var branchFromTagName = ""
    @State private var newBranchFromTagName = ""

    @State private var stashPendingDrop: StashInfo?
    @State private var showCreateWorktree = false
    @State private var worktreeCreateBranch = true
    @State private var worktreeBranch = ""
    @State private var worktreePath = ""
    @State private var isCreatingWorktree = false
    @State private var worktreePendingRemoval: WorktreeInfo?
    @State private var activeFileTreeEdit: FileTreeEditState?
    @State private var pendingWorkingTreeDelete: PendingWorkingTreeDelete?
    @State private var fileSearchText = ""
    @State private var fileSearchSnapshot: WorkingTreeFileTreeBuilder.TreeSnapshot?
    @State private var fileSearchSnapshotQuery = ""
    @State private var fileSearchGeneration = 0
    @State private var fileSearchTask: Task<Void, Never>?
    @State private var isFileSearchSearching = false
    @State private var isFileSearchFieldHovered = false
    @FocusState private var isFileSearchFieldFocused: Bool

    private var localBranchesSectionShouldAnimate: Bool {
        viewModel.localBranches.count + (viewModel.isDetachedHead ? 1 : 0) <= Self.animatedSectionItemLimit
    }

    private var filesSectionShouldAnimate: Bool {
        viewModel.workingTreeFiles.count <= Self.animatedSectionItemLimit
    }

    private var trimmedFileSearchText: String {
        fileSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFileSearchActive: Bool {
        !trimmedFileSearchText.isEmpty
    }

    private var isFileSearchFieldHighlighted: Bool {
        isFileSearchFieldFocused || isFileSearchFieldHovered
    }

    private var remoteSectionShouldAnimate: Bool {
        let remoteBranchCount = viewModel.remoteBranchGroups.values.reduce(0) { $0 + $1.count }
        return remoteBranchCount + viewModel.remotes.count <= Self.animatedSectionItemLimit
    }

    private var tagsSectionShouldAnimate: Bool {
        viewModel.tags.count <= Self.animatedSectionItemLimit
    }

    private var stashesSectionShouldAnimate: Bool {
        viewModel.stashes.count <= Self.animatedSectionItemLimit
    }

    private var submodulesSectionShouldAnimate: Bool {
        viewModel.submodules.count <= Self.animatedSectionItemLimit
    }

    private func remoteDisclosureShouldAnimate(_ remoteName: String) -> Bool {
        (viewModel.remoteBranchGroups[remoteName]?.count ?? 0) <= Self.animatedRemoteDisclosureItemLimit
    }

    private func isRemoteCollapsed(_ remoteName: String) -> Bool {
        collapsedRemotes.contains(remoteName)
    }

    private func toggleRemoteDisclosure(_ remoteName: String, animate: Bool) {
        let update = {
            if collapsedRemotes.contains(remoteName) {
                collapsedRemotes.remove(remoteName)
            } else {
                collapsedRemotes.insert(remoteName)
            }
        }

        if animate {
            withAnimation(.easeInOut(duration: 0.2)) {
                update()
            }
        } else {
            update()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    localBranchesSection
                    worktreesSection
                    remotesSection
                    tagsSection
                    stashesSection
                    submodulesSection
                    mergeRequestsSection
                    filesSection
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            isFileSearchFieldFocused = false
            Task { @MainActor in
                await Task.yield()
                isFileSearchFieldFocused = false
            }
            if !viewModel.isSectionCollapsed("files") {
                Task {
                    await viewModel.loadWorkingTreeFilesRootIfNeeded()
                    await viewModel.prewarmWorkingTreeFileSearchIndex()
                }
            }
        }
        .onChange(of: viewModel.workingTreeFiles) { _, _ in
            collapseNewLoadedFileFolders()
            if isFileSearchActive {
                scheduleFileSearch(allowNarrowingExistingResults: false)
            }
        }
        .onChange(of: viewModel.workingTreeFolderContents) { _, _ in
            collapseNewLoadedFileFolders()
            if isFileSearchActive {
                scheduleFileSearch(allowNarrowingExistingResults: false)
            }
        }
        .onChange(of: fileSearchText) { _, _ in
            scheduleFileSearch(allowNarrowingExistingResults: true)
        }
        .onDisappear {
            fileSearchTask?.cancel()
            isFileSearchSearching = false
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .sheet(isPresented: $showAddRemote) {
            addRemoteSheet
        }
        .sheet(isPresented: $showEditRemote) { editRemoteSheet }
        .sheet(isPresented: $showRenameBranch) { renameBranchSheet }
        .sheet(isPresented: $showCreateTagAtBranch) { createTagAtBranchSheet }
        .sheet(isPresented: $showCreateBranchFrom) { createBranchFromSheet }
        .sheet(isPresented: $showCreateWorktree) { createWorktreeSheet }
        .sheet(isPresented: $showSetUpstream) { setUpstreamSheet }
        .sheet(isPresented: $showAnnotateTag) { annotateTagSheet }
        .sheet(isPresented: $showCreateBranchFromTag) { createBranchFromTagSheet }
        .alert(viewModel.mergeActionTitle ?? "Merge", isPresented: $showMergeConfirm) {
            Button("Merge", role: .destructive) {
                guard let mr = mergingMR else { return }
                Task { await viewModel.performMRMerge(mr: mr) }
                mergingMR = nil
            }
            Button("Cancel", role: .cancel) {
                mergingMR = nil
            }
        } message: {
            if let mr = mergingMR {
                switch mr.provider {
                case .gitlab:
                    Text("Will rebase '\(mr.sourceBranch)' onto '\(mr.targetBranch)' and merge \(mr.provider.singularDisplayName) \(mr.numberDisplay).\n\nCurrent working directory will be stashed and restored after the operation.")
                case .github:
                    Text("Will ask GitHub to rebase-merge \(mr.provider.singularDisplayName) \(mr.numberDisplay).")
                case .unknown:
                    Text("Unsupported remote host.")
                }
            }
        }
        .alert("Delete Stash", isPresented: Binding(
            get: { stashPendingDrop != nil },
            set: { if !$0 { stashPendingDrop = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let stash = stashPendingDrop else { return }
                stashPendingDrop = nil
                Task { await viewModel.performStashDrop(stash: stash) }
            }
            Button("Cancel", role: .cancel) {
                stashPendingDrop = nil
            }
        } message: {
            if let stash = stashPendingDrop {
                let summary = stash.message.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = summary.isEmpty ? stash.index : "“\(summary)” (\(stash.index))"
                Text("Remove \(detail)? The stashed changes will be discarded. This cannot be undone.")
            }
        }
        .alert("Remove Worktree", isPresented: Binding(
            get: { worktreePendingRemoval != nil },
            set: { if !$0 { worktreePendingRemoval = nil } }
        )) {
            Button("Remove Worktree", role: .destructive) {
                guard let worktree = worktreePendingRemoval else { return }
                worktreePendingRemoval = nil
                let openPaths = Set(appModel.tabs.map { WorktreeService.canonicalPath($0.path) })
                Task { await viewModel.performRemoveWorktree(worktree, openPaths: openPaths) }
            }
            Button("Cancel", role: .cancel) { worktreePendingRemoval = nil }
        } message: {
            if let worktreePendingRemoval {
                Text("Remove the clean worktree at \(worktreePendingRemoval.path)? Its branch will be kept. Git will refuse removal if it has local changes.")
            }
        }
        .alert("Delete \(pendingWorkingTreeDelete?.isFolder == true ? "Folder" : "File")", isPresented: Binding(
            get: { pendingWorkingTreeDelete != nil },
            set: { if !$0 { pendingWorkingTreeDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let pendingWorkingTreeDelete else { return }
                self.pendingWorkingTreeDelete = nil
                Task { await viewModel.performDeleteWorkingTreeItem(path: pendingWorkingTreeDelete.path) }
            }
            Button("Cancel", role: .cancel) {
                pendingWorkingTreeDelete = nil
            }
        } message: {
            if let pendingWorkingTreeDelete {
                Text("Delete \(pendingWorkingTreeDelete.displayName)? This cannot be undone.")
            }
        }
    }

    // MARK: - Add Remote Sheet

    private func collapseNewLoadedFileFolders() {
        let loadedFolderPaths = Set(
            viewModel.workingTreeFiles.compactMap { node -> String? in
                if case .folder(_, let relativePath) = node {
                    return relativePath
                }
                return nil
            }
        ).union(
            viewModel.workingTreeFolderContents.values.flatMap { nodes in
                nodes.compactMap { node -> String? in
                    if case .folder(_, let relativePath) = node {
                        return relativePath
                    }
                    return nil
                }
            }
        )
        let newFolderPaths = loadedFolderPaths.subtracting(seenFileFolders)
        let autoCollapsedPaths = newFolderPaths.subtracting(expandingFileFolders)
        collapsedFileFolders.formUnion(autoCollapsedPaths)
        seenFileFolders.formUnion(newFolderPaths)
        expandingFileFolders.subtract(loadedFolderPaths)
    }

    private func scheduleFileSearch(allowNarrowingExistingResults: Bool) {
        fileSearchGeneration += 1
        let generation = fileSearchGeneration
        let query = trimmedFileSearchText
        fileSearchTask?.cancel()
        isFileSearchSearching = false

        guard !query.isEmpty else {
            fileSearchSnapshot = nil
            fileSearchSnapshotQuery = ""
            return
        }

        let repositoryPath = viewModel.repoPath
        let candidateFilePaths: Set<String>?
        if allowNarrowingExistingResults,
           !fileSearchSnapshotQuery.isEmpty,
           query.hasPrefix(fileSearchSnapshotQuery),
           query != fileSearchSnapshotQuery,
           let fileSearchSnapshot {
            candidateFilePaths = fileSearchSnapshot.matchedFilePaths
        } else {
            candidateFilePaths = nil
            fileSearchSnapshot = .empty
            fileSearchSnapshotQuery = ""
        }

        fileSearchTask = Task {
            do {
                try await Task.sleep(nanoseconds: Self.fileSearchDebounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == fileSearchGeneration else { return }
                isFileSearchSearching = true
            }

            let searchTask = Task.detached(priority: .utility) {
                let snapshot = try await WorkingTreeFileSearchIndex.shared.search(
                    repositoryPath: repositoryPath,
                    query: query,
                    candidateFilePaths: candidateFilePaths
                )
                await MainActor.run {
                    guard generation == fileSearchGeneration else { return }
                    fileSearchSnapshot = snapshot
                    fileSearchSnapshotQuery = query
                }
            }
            try? await withTaskCancellationHandler {
                try await searchTask.value
            } onCancel: {
                searchTask.cancel()
            }
            await MainActor.run {
                guard generation == fileSearchGeneration else { return }
                isFileSearchSearching = false
            }
        }
    }

    private var addRemoteSheet: some View {
        VStack(spacing: 12) {
            Text("Add Remote")
                .font(.headline)
            FocusTextField(titleKey: "Remote name (e.g. origin)", text: $newRemoteName)
                .frame(width: 300)
            FocusTextField(titleKey: "Remote URL", text: $newRemoteURL)
                .frame(width: 300)
            HStack {
                Button("Cancel") {
                    showAddRemote = false
                    newRemoteName = ""
                    newRemoteURL = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let name = newRemoteName.trimmingCharacters(in: .whitespaces)
                    let url = newRemoteURL.trimmingCharacters(in: .whitespaces)
                    showAddRemote = false
                    newRemoteName = ""
                    newRemoteURL = ""
                    guard !name.isEmpty, !url.isEmpty else { return }
                    Task { await viewModel.performAddRemote(name: name, url: url) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    newRemoteName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    newRemoteURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(20)
    }

    // MARK: - Files

    private var filesSection: some View {
        SidebarSection(
            title: "FILES",
            icon: "doc.on.doc",
            count: nil,
            isCollapsed: viewModel.isSectionCollapsed("files"),
            onToggle: {
                let wasCollapsed = viewModel.isSectionCollapsed("files")
                viewModel.toggleSection("files")
                if wasCollapsed {
                    Task {
                        await viewModel.loadWorkingTreeFilesRootIfNeeded()
                        await viewModel.prewarmWorkingTreeFileSearchIndex()
                    }
                }
            },
            animateCollapse: filesSectionShouldAnimate,
            headerContextMenu: {
                AnyView(filesRootContextMenu)
            }
        ) {
            let treeNodes = isFileSearchActive ? (fileSearchSnapshot?.rootNodes ?? []) : viewModel.workingTreeFiles
            let folderContents = isFileSearchActive ? (fileSearchSnapshot?.folderContents ?? [:]) : viewModel.workingTreeFolderContents
            let collapsedFolders = isFileSearchActive ? [] : collapsedFileFolders
            let flatNodes = flattenWorkingTree(
                treeNodes,
                folderContents: folderContents,
                depth: 0,
                collapsedFolders: collapsedFolders
            )
            let listRows = fileTreeRows(from: flatNodes)
            fileSearchField
            if listRows.isEmpty {
                Text(isFileSearchActive ? "No matches" : "No files")
                    .font(AppTypography.Sidebar.rowMeta)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 28)
                    .padding(.vertical, 4)
            } else {
                ForEach(listRows) { row in
                    switch row {
                    case .node(let node):
                        fileTreeNodeRow(node)
                    case .create(let parentPath, let depth, let isFolder):
                        SidebarFileInlineEditorRow(
                            name: pendingNameBinding(for: parentPath, isFolder: isFolder),
                            icon: isFolder ? "folder.badge.plus" : "doc.badge.plus",
                            depth: depth,
                            isFolder: isFolder,
                            placeholder: isFolder ? "New Folder" : "New File",
                            submitLabel: isFolder ? .done : .return
                        ) {
                            commitFileTreeCreate(parentPath: parentPath, isFolder: isFolder)
                        } onCancel: {
                            cancelActiveFileTreeEdit()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filesRootContextMenu: some View {
        Button("New Folder") {
            startCreatingNode(in: "", isFolder: true, depth: 0)
        }
        Button("New File") {
            startCreatingNode(in: "", isFolder: false, depth: 0)
        }
    }

    private var fileSearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(isFileSearchFieldHighlighted ? .secondary : .tertiary)

            TextField("Search files", text: $fileSearchText)
                .textFieldStyle(.plain)
                .font(AppTypography.Sidebar.row)
                .focused($isFileSearchFieldFocused)
                .onAppear {
                    isFileSearchFieldFocused = false
                    Task { @MainActor in
                        await Task.yield()
                        isFileSearchFieldFocused = false
                    }
                }

            if isFileSearchSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
                    .hoverTooltip("Searching")
            }

            if isFileSearchActive {
                Button {
                    fileSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.Sidebar.rowMeta)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .hoverTooltip("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.textBackgroundColor).opacity(isFileSearchFieldHighlighted ? 0.95 : 0.76))
        )
        .animatedInputBorder(
            isFocused: isFileSearchFieldFocused,
            cornerRadius: 6,
            showsBaseBorder: true
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isFileSearchFieldHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isFileSearchFieldHighlighted)
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func fileTreeNodeRow(_ node: FlatWorkingTreeNode) -> some View {
        switch node.kind {
        case .folder:
            if case let .rename(path, _, pendingName, _) = activeFileTreeEdit, path == node.relativePath {
                SidebarFileInlineEditorRow(
                    name: Binding(
                        get: { pendingName },
                        set: { updateRenamePendingName($0, path: path, depth: node.depth) }
                    ),
                    icon: "folder",
                    depth: node.depth,
                    isFolder: true,
                    placeholder: node.displayName
                ) {
                    commitFileTreeRename(path: node.relativePath)
                } onCancel: {
                    cancelActiveFileTreeEdit()
                }
            } else {
                SidebarFileFolderRow(
                    name: node.displayName,
                    isCollapsed: isFileSearchActive ? false : collapsedFileFolders.contains(node.relativePath),
                    depth: node.depth
                )
                .contextMenu {
                    fileFolderContextMenu(node)
                        .font(AppTypography.Sidebar.contextMenu)
                }
                .onTapGesture {
                    if !isFileSearchActive {
                        toggleFolder(node.relativePath)
                    }
                }
            }
        case .file:
            if case let .rename(path, _, pendingName, _) = activeFileTreeEdit, path == node.relativePath {
                SidebarFileInlineEditorRow(
                    name: Binding(
                        get: { pendingName },
                        set: { updateRenamePendingName($0, path: path, depth: node.depth) }
                    ),
                    icon: "doc.text",
                    depth: node.depth,
                    isFolder: false,
                    placeholder: node.displayName
                ) {
                    commitFileTreeRename(path: node.relativePath)
                } onCancel: {
                    cancelActiveFileTreeEdit()
                }
            } else {
                SidebarFileRow(
                    name: node.displayName,
                    depth: node.depth,
                    isSelected: viewModel.selectedWorkingTreeFilePath == node.relativePath
                )
                .contextMenu {
                    fileLeafContextMenu(node)
                        .font(AppTypography.Sidebar.contextMenu)
                }
                .onTapGesture {
                    Task { await viewModel.openWorkingTreeFilePreview(path: node.relativePath) }
                }
            }
        }
    }

    @ViewBuilder
    private func fileFolderContextMenu(_ node: FlatWorkingTreeNode) -> some View {
        Button("New Folder") {
            startCreatingNode(in: node.relativePath, isFolder: true, depth: node.depth + 1)
        }
        Button("New File") {
            startCreatingNode(in: node.relativePath, isFolder: false, depth: node.depth + 1)
        }
        Divider()
        Button("Rename") {
            activeFileTreeEdit = .rename(
                path: node.relativePath,
                originalName: node.displayName,
                pendingName: node.displayName,
                depth: node.depth
            )
        }
        Button("Delete", role: .destructive) {
            pendingWorkingTreeDelete = PendingWorkingTreeDelete(
                path: node.relativePath,
                displayName: node.displayName,
                isFolder: true
            )
        }
        Divider()
        Button("Reveal in Finder") {
            viewModel.showInFinder(path: node.relativePath)
        }
        Button("Copy Path") {
            viewModel.copyWorkingTreePath(path: node.relativePath)
        }
    }

    @ViewBuilder
    private func fileLeafContextMenu(_ node: FlatWorkingTreeNode) -> some View {
        Button("File History") {
            Task { await viewModel.openFileHistory(path: node.relativePath, context: .unstaged) }
        }
        Divider()
        Button("Rename") {
            activeFileTreeEdit = .rename(
                path: node.relativePath,
                originalName: node.displayName,
                pendingName: node.displayName,
                depth: node.depth
            )
        }
        Button("Delete", role: .destructive) {
            pendingWorkingTreeDelete = PendingWorkingTreeDelete(
                path: node.relativePath,
                displayName: node.displayName,
                isFolder: false
            )
        }
        Divider()
        Button("Reveal in Finder") {
            viewModel.showInFinder(path: node.relativePath)
        }
        Button("Copy Path") {
            viewModel.copyWorkingTreePath(path: node.relativePath)
        }
    }

    private func toggleFolder(_ relativePath: String) {
        cancelActiveFileTreeEdit()
        if collapsedFileFolders.contains(relativePath) {
            collapsedFileFolders.remove(relativePath)
            expandingFileFolders.insert(relativePath)
            Task { await viewModel.setWorkingTreeFolderExpanded(path: relativePath, isExpanded: true) }
        } else {
            collapsedFileFolders.insert(relativePath)
            expandingFileFolders.remove(relativePath)
            Task { await viewModel.setWorkingTreeFolderExpanded(path: relativePath, isExpanded: false) }
        }
    }

    private func startCreatingNode(in parentPath: String, isFolder: Bool, depth: Int) {
        fileSearchText = ""
        if !parentPath.isEmpty {
            collapsedFileFolders.remove(parentPath)
            expandingFileFolders.insert(parentPath)
            Task { await viewModel.setWorkingTreeFolderExpanded(path: parentPath, isExpanded: true) }
        } else if viewModel.isSectionCollapsed("files") {
            viewModel.toggleSection("files")
            Task { await viewModel.loadWorkingTreeFilesRootIfNeeded() }
        }
        activeFileTreeEdit = isFolder
            ? .createFolder(parentPath: parentPath, pendingName: "", depth: depth)
            : .createFile(parentPath: parentPath, pendingName: "", depth: depth)
    }

    private func cancelActiveFileTreeEdit() {
        activeFileTreeEdit = nil
    }

    private func commitFileTreeCreate(parentPath: String, isFolder: Bool) {
        guard let currentEdit = activeFileTreeEdit else { return }
        let pendingName: String
        switch currentEdit {
        case .createFolder(let currentParentPath, let currentPendingName, _),
             .createFile(let currentParentPath, let currentPendingName, _):
            guard currentParentPath == parentPath else { return }
            pendingName = currentPendingName
        case .rename:
            return
        }

        activeFileTreeEdit = nil
        Task {
            if isFolder {
                _ = await viewModel.performCreateWorkingTreeFolder(parentPath: parentPath, name: pendingName)
            } else {
                _ = await viewModel.performCreateWorkingTreeFile(parentPath: parentPath, name: pendingName)
            }
        }
    }

    private func commitFileTreeRename(path: String) {
        guard case let .rename(currentPath, originalName, pendingName, _) = activeFileTreeEdit,
              currentPath == path else { return }

        let trimmedName = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName == originalName {
            activeFileTreeEdit = nil
            return
        }

        activeFileTreeEdit = nil
        Task {
            _ = await viewModel.performRenameWorkingTreeItem(path: path, newName: pendingName)
        }
    }

    private func updateRenamePendingName(_ newValue: String, path: String, depth: Int) {
        guard case let .rename(currentPath, originalName, _, currentDepth) = activeFileTreeEdit,
              currentPath == path,
              currentDepth == depth else { return }
        activeFileTreeEdit = .rename(
            path: currentPath,
            originalName: originalName,
            pendingName: newValue,
            depth: currentDepth
        )
    }

    private func pendingNameBinding(for parentPath: String, isFolder: Bool) -> Binding<String> {
        Binding(
            get: {
                switch activeFileTreeEdit {
                case .createFolder(let currentParentPath, let pendingName, _) where isFolder && currentParentPath == parentPath:
                    return pendingName
                case .createFile(let currentParentPath, let pendingName, _) where !isFolder && currentParentPath == parentPath:
                    return pendingName
                default:
                    return ""
                }
            },
            set: { newValue in
                switch activeFileTreeEdit {
                case .createFolder(let currentParentPath, _, let depth) where isFolder && currentParentPath == parentPath:
                    activeFileTreeEdit = .createFolder(parentPath: currentParentPath, pendingName: newValue, depth: depth)
                case .createFile(let currentParentPath, _, let depth) where !isFolder && currentParentPath == parentPath:
                    activeFileTreeEdit = .createFile(parentPath: currentParentPath, pendingName: newValue, depth: depth)
                default:
                    break
                }
            }
        )
    }

    private func fileTreeRows(from flatNodes: [FlatWorkingTreeNode]) -> [FileTreeListRow] {
        var rows = flatNodes.map(FileTreeListRow.node)
        guard !isFileSearchActive else { return rows }

        switch activeFileTreeEdit {
        case .createFolder(let parentPath, _, let depth):
            rows.insert(.create(parentPath: parentPath, depth: depth, isFolder: true), at: insertionIndex(for: parentPath, in: flatNodes))
        case .createFile(let parentPath, _, let depth):
            rows.insert(.create(parentPath: parentPath, depth: depth, isFolder: false), at: insertionIndex(for: parentPath, in: flatNodes))
        case .rename, .none:
            break
        }

        return rows
    }

    private func insertionIndex(for parentPath: String, in flatNodes: [FlatWorkingTreeNode]) -> Int {
        guard !parentPath.isEmpty else { return 0 }
        guard let parentIndex = flatNodes.firstIndex(where: { $0.relativePath == parentPath }) else { return flatNodes.count }
        return parentIndex + 1
    }

    // MARK: - Local Branch Context Menu

    @ViewBuilder
    private func localBranchContextMenu(_ branch: BranchInfo) -> some View {
        let cur = viewModel.currentBranch

        // Pull
        if branch.isCurrent {
            Button("Pull \(branch.name)") {
                Task { await viewModel.performPull() }
            }
            Button("Push \(branch.name)") {
                Task { await viewModel.performPush() }
            }
        } else {
            Button("Pull \(branch.name)") {
                Task { await viewModel.performPullBranch(branch) }
            }
        }

        Divider()

        if !branch.isCurrent {
            Button("Merge \(branch.name) into \(cur)") {
                Task { await viewModel.performMerge(branch.name) }
            }
            Button("Rebase \(cur) onto \(branch.name)") {
                Task { await viewModel.performRebase(onto: branch.name) }
            }
            Divider()
            Button("Checkout \(branch.name)") {
                Task { await viewModel.performCheckoutBranch(branch.name) }
            }
        }

        if branch.isCurrent {
            Button("Set Upstream") {
                upstreamRemote = "origin"
                upstreamBranch = branch.name
                showSetUpstream = true
            }
            if branch.upstream != nil {
                Button("Unset Upstream") {
                    Task { await viewModel.performUnsetUpstream(branch: branch.name) }
                }
            }
            if let createReviewTitle = viewModel.currentBranchReviewCreationActionTitle,
               viewModel.currentBranchReviewCreationURL() != nil {
                Button(createReviewTitle) {
                    viewModel.openCurrentBranchReviewCreationInBrowser()
                }
            }
            Divider()
        }

        Button("Create branch here") {
            branchFromName = branch.name
            branchFromIsRemote = false
            branchFromHash = branch.shortHash
            newBranchFromName = ""
            showCreateBranchFrom = true
        }
        Button("Create Worktree for \(branch.name)…") {
            presentCreateWorktree(for: branch.name)
        }
        .disabled(branch.isCurrent || viewModel.worktrees.contains { $0.branchName == branch.name })
        if !branch.isCurrent {
            Button("Cherry pick commit") {
                Task { await viewModel.performCherryPick(branch.shortHash) }
            }
        }
        Menu("Reset \(cur) to this commit") {
            Button("Soft") { Task { await viewModel.performReset(branch.shortHash, mode: .soft) } }
            Button("Mixed") { Task { await viewModel.performReset(branch.shortHash, mode: .mixed) } }
            Button("Hard") { Task { await viewModel.performReset(branch.shortHash, mode: .hard) } }
        }
        Button("Revert commit") {
            Task { await viewModel.performRevert(branch.shortHash) }
        }

        Divider()

        Button("Rename \(branch.name)") {
            renamingBranch = branch.name
            renamedBranchName = branch.name
            showRenameBranch = true
        }
        if !branch.isCurrent {
            Button("Delete \(branch.name) locally", role: .destructive) {
                Task { await viewModel.performDeleteBranch(branch.name) }
            }
            if let upstream = branch.upstream {
                let remoteParts = upstream.split(separator: "/", maxSplits: 1)
                let remote = remoteParts.first.map(String.init) ?? "origin"
                let remoteBranch = remoteParts.dropFirst().first.map(String.init) ?? branch.name
                Button("Delete \(branch.name) on \(remote)", role: .destructive) {
                    Task { await viewModel.performDeleteRemoteBranch(remote: remote, branch: remoteBranch) }
                }
            }
        }

        Divider()

        Button("Copy branch name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.name, forType: .string)
        }
        Button("Copy commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.shortHash, forType: .string)
        }

        Divider()

        Button("Create tag here") {
            tagAtBranchHash = branch.shortHash
            tagAtBranchName = ""
            showCreateTagAtBranch = true
        }
    }

    // MARK: - Remote Branch Context Menu

    @ViewBuilder
    private func remoteBranchContextMenu(_ branch: BranchInfo, remoteName: String) -> some View {
        let cur = viewModel.currentBranch
        let fullName = branch.name
        let shortName = fullName.replacingOccurrences(of: "\(remoteName)/", with: "")

        Button("Merge \(fullName) into \(cur)") {
            Task { await viewModel.performMerge(fullName) }
        }
        Button("Rebase \(cur) onto \(fullName)") {
            Task { await viewModel.performRebase(onto: fullName) }
        }

        Divider()

        Button("Checkout \(fullName)") {
            Task { await viewModel.performCheckoutBranch(fullName) }
        }

        Divider()

        Button("Create branch here") {
            branchFromName = fullName
            branchFromIsRemote = true
            branchFromHash = branch.shortHash
            newBranchFromName = shortName
            showCreateBranchFrom = true
        }
        if !branch.isCurrent {
            Button("Cherry pick commit") {
                Task { await viewModel.performCherryPick(branch.shortHash) }
            }
        }
        Menu("Reset \(cur) to this commit") {
            Button("Soft") { Task { await viewModel.performReset(branch.shortHash, mode: .soft) } }
            Button("Mixed") { Task { await viewModel.performReset(branch.shortHash, mode: .mixed) } }
            Button("Hard") { Task { await viewModel.performReset(branch.shortHash, mode: .hard) } }
        }
        Button("Revert commit") {
            Task { await viewModel.performRevert(branch.shortHash) }
        }

        Divider()

        Button("Delete \(fullName)", role: .destructive) {
            Task { await viewModel.performDeleteRemoteBranch(remote: remoteName, branch: shortName) }
        }

        Divider()

        Button("Copy branch name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullName, forType: .string)
        }
        Button("Copy commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.shortHash, forType: .string)
        }

        Divider()

        Button("Create tag here") {
            tagAtBranchHash = branch.shortHash
            tagAtBranchName = ""
            showCreateTagAtBranch = true
        }
    }

    // MARK: - Branch Sheets

    private var renameBranchSheet: some View {
        VStack(spacing: 12) {
            Text("Rename Branch")
                .font(.headline)
            FocusTextField(titleKey: "New name", text: $renamedBranchName)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showRenameBranch = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    let newName = renamedBranchName.trimmingCharacters(in: .whitespaces)
                    showRenameBranch = false
                    guard !newName.isEmpty, newName != renamingBranch else { return }
                    Task { await viewModel.performRenameBranch(oldName: renamingBranch, newName: newName) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renamedBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var createTagAtBranchSheet: some View {
        VStack(spacing: 12) {
            Text("Create Tag")
                .font(.headline)
            FocusTextField(titleKey: "Tag name", text: $tagAtBranchName)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showCreateTagAtBranch = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = tagAtBranchName.trimmingCharacters(in: .whitespaces)
                    showCreateTagAtBranch = false
                    guard !name.isEmpty else { return }
                    Task { await viewModel.performCreateTag(name: name, at: tagAtBranchHash) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagAtBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var createBranchFromSheet: some View {
        VStack(spacing: 12) {
            Text("Create Branch")
                .font(.headline)
            FocusTextField(titleKey: "Branch name", text: $newBranchFromName)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showCreateBranchFrom = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = newBranchFromName.trimmingCharacters(in: .whitespaces)
                    showCreateBranchFrom = false
                    guard !name.isEmpty else { return }
                    Task { 
                        // Get full hash from branch name
                        do {
                            let fullHash = try await viewModel.getBranchCommitHash(branchFromName, isRemote: branchFromIsRemote)
                            await viewModel.performCreateBranchAt(name: name, commitHash: fullHash)
                        } catch {
                            // Fallback: try using shortHash directly (might work if it's unique)
                            await viewModel.performCreateBranchAt(name: name, commitHash: branchFromHash)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchFromName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var setUpstreamSheet: some View {
        VStack(spacing: 12) {
            Text("Set Upstream")
                .font(.headline)
            FocusTextField(titleKey: "Remote", text: $upstreamRemote)
                .frame(width: 280)
            FocusTextField(titleKey: "Branch", text: $upstreamBranch)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showSetUpstream = false }
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    let remote = upstreamRemote.trimmingCharacters(in: .whitespaces)
                    let branch = upstreamBranch.trimmingCharacters(in: .whitespaces)
                    showSetUpstream = false
                    guard !remote.isEmpty, !branch.isEmpty else { return }
                    Task { await viewModel.performSetUpstream(remote: remote, branch: branch) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    upstreamRemote.trimmingCharacters(in: .whitespaces).isEmpty ||
                    upstreamBranch.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(20)
    }

    // MARK: - Edit Remote Sheet

    private var editRemoteSheet: some View {
        VStack(spacing: 12) {
            Text("Edit Remote")
                .font(.headline)
            FocusTextField(titleKey: "Remote name", text: $editRemoteName)
                .frame(width: 300)
            FocusTextField(titleKey: "Remote URL", text: $editRemoteURL)
                .frame(width: 300)
            HStack {
                Button("Cancel") {
                    showEditRemote = false
                    editingRemote = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let original = editingRemote else { return }
                    let name = editRemoteName.trimmingCharacters(in: .whitespaces)
                    let url = editRemoteURL.trimmingCharacters(in: .whitespaces)
                    showEditRemote = false
                    editingRemote = nil
                    guard !name.isEmpty, !url.isEmpty else { return }
                    Task { await viewModel.performEditRemote(oldName: original.name, newName: name, newURL: url) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    editRemoteName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    editRemoteURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(20)
    }

    // MARK: - Local Branches

    private var localBranchesSection: some View {
        SidebarSection(
            title: "LOCAL",
            icon: "arrow.triangle.branch",
            count: viewModel.localBranches.count + (viewModel.isDetachedHead ? 1 : 0),
            isCollapsed: viewModel.isSectionCollapsed("local"),
            onToggle: { viewModel.toggleSection("local") },
            animateCollapse: localBranchesSectionShouldAnimate
        ) {
            // Detached HEAD indicator
            if viewModel.isDetachedHead {
                SidebarDetachedHeadRow(
                    shortHash: viewModel.currentBranch
                )
                .onTapGesture {
                    Task { await viewModel.navigateToCommit(hash: viewModel.currentBranch) }
                }
            }

            let localTree = makeBranchTree(branches: viewModel.localBranches)
            let localFlat = flattenBranchTree(localTree, depth: 0, collapsedFolders: collapsedLocalFolders)
            ForEach(localFlat) { node in
                if let branch = node.branchInfo {
                    SidebarBranchRow(
                        name: node.displayName,
                        isCurrent: branch.isCurrent,
                        icon: "arrow.triangle.branch",
                        ahead: branch.ahead,
                        behind: branch.behind,
                        indentDepth: node.depth
                    )
                    .onTapGesture(count: 2) {
                        guard !branch.isCurrent else { return }
                        Task { await viewModel.performCheckoutBranch(branch.name) }
                    }
                    .onTapGesture {
                        Task { await viewModel.scrollToCommitForBranch(branch) }
                    }
                    .contextMenu {
                        localBranchContextMenu(branch)
                            .font(AppTypography.Sidebar.contextMenu)
                    }
                } else {
                    BranchGroupRow(
                        name: node.displayName,
                        isCollapsed: collapsedLocalFolders.contains(node.fullPath),
                        depth: node.depth
                    )
                    .onTapGesture {
                        if collapsedLocalFolders.contains(node.fullPath) {
                            collapsedLocalFolders.remove(node.fullPath)
                        } else {
                            collapsedLocalFolders.insert(node.fullPath)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Worktrees

    private var availableWorktreeBranches: [BranchInfo] {
        let checkedOut = Set(viewModel.worktrees.compactMap(\.branchName))
        return viewModel.localBranches.filter { !$0.isCurrent && !checkedOut.contains($0.name) }
    }

    private var suggestedWorktreeFolderName: String {
        let leaf = worktreeBranch.split(separator: "/").last.map(String.init) ?? "new-worktree"
        return "\(viewModel.repoName)-\(leaf)"
    }

    private func presentCreateWorktree(for branch: String? = nil) {
        worktreeCreateBranch = branch == nil
        worktreeBranch = branch ?? ""
        let parent = URL(fileURLWithPath: viewModel.repoPath).deletingLastPathComponent()
        let suffix = branch?.split(separator: "/").last.map(String.init) ?? "new-worktree"
        worktreePath = parent.appendingPathComponent("\(viewModel.repoName)-\(suffix)").path
        viewModel.worktreeError = nil
        showCreateWorktree = true
    }

    private func chooseWorktreeDestinationParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the parent folder for the new worktree"
        panel.directoryURL = URL(fileURLWithPath: viewModel.repoPath).deletingLastPathComponent()
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        worktreePath = parent.appendingPathComponent(suggestedWorktreeFolderName).path
    }

    private var createWorktreeSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Worktree")
                .font(.headline)
            Picker("Source", selection: $worktreeCreateBranch) {
                Text("New branch from HEAD").tag(true)
                Text("Existing local branch").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: worktreeCreateBranch) { _, createBranch in
                worktreeBranch = createBranch ? "" : (availableWorktreeBranches.first?.name ?? "")
                viewModel.worktreeError = nil
            }

            if worktreeCreateBranch {
                TextField("New branch name", text: $worktreeBranch)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Branch", selection: $worktreeBranch) {
                    ForEach(availableWorktreeBranches) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                if availableWorktreeBranches.isEmpty {
                    Text("No unchecked-out local branches are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Absolute destination path", text: $worktreePath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { chooseWorktreeDestinationParent() }
            }
            Text("The branch remains after the worktree is removed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = viewModel.worktreeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { showCreateWorktree = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreatingWorktree)
                Button("Create and Open") {
                    let path = worktreePath
                    let branch = worktreeBranch
                    let createBranch = worktreeCreateBranch
                    isCreatingWorktree = true
                    Task {
                        defer { isCreatingWorktree = false }
                        if let createdPath = await viewModel.performCreateWorktree(
                            path: path, branch: branch, createBranch: createBranch
                        ) {
                            showCreateWorktree = false
                            let name = URL(fileURLWithPath: createdPath).lastPathComponent
                            appModel.openRepository(path: createdPath, name: name)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreatingWorktree || viewModel.operationInProgress
                    || worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !worktreePath.hasPrefix("/"))
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var worktreesSection: some View {
        SidebarSection(
            title: "WORKTREES",
            icon: "square.stack.3d.up",
            count: viewModel.worktrees.count,
            isCollapsed: viewModel.isSectionCollapsed("worktrees"),
            onToggle: { viewModel.toggleSection("worktrees") },
            animateCollapse: viewModel.worktrees.count <= Self.animatedSectionItemLimit,
            onAdd: { presentCreateWorktree() },
            onRefresh: { Task { await viewModel.refreshWorktrees() } }
        ) {
            ForEach(viewModel.worktrees) { worktree in
                let isCurrent = WorktreeService.canonicalPath(worktree.path)
                    == WorktreeService.canonicalPath(viewModel.repoPath)
                let isOpen = appModel.tabs.contains {
                    WorktreeService.canonicalPath($0.path) == WorktreeService.canonicalPath(worktree.path)
                }
                Button {
                    let name = URL(fileURLWithPath: worktree.path).lastPathComponent
                    appModel.openRepository(path: worktree.path, name: name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: worktree.isMain ? "house" : "square.stack.3d.up")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(worktree.branchName ?? (worktree.isDetached ? "Detached HEAD" : "Worktree"))
                                    .font(AppTypography.Sidebar.row)
                                    .lineLimit(1)
                                if isCurrent { Text("Current").foregroundStyle(.secondary) }
                                if worktree.isLocked { Image(systemName: "lock.fill") }
                                if worktree.isPrunable { Image(systemName: "exclamationmark.triangle") }
                            }
                            Text(worktree.path)
                                .font(AppTypography.Sidebar.rowMeta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(worktree.isPrunable || worktree.isBare)
                .hoverTooltip(worktree.path)
                .contextMenu {
                    Button("Open in Tab") {
                        let name = URL(fileURLWithPath: worktree.path).lastPathComponent
                        appModel.openRepository(path: worktree.path, name: name)
                    }
                    .disabled(worktree.isPrunable || worktree.isBare)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                    }
                    .disabled(worktree.isPrunable)
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(worktree.path, forType: .string)
                    }
                    Divider()
                    Button(isOpen ? "Close Tab Before Removing" : "Remove Worktree…", role: .destructive) {
                        worktreePendingRemoval = worktree
                    }
                    .disabled(worktree.isMain || isCurrent || isOpen || worktree.isLocked || worktree.isPrunable)
                }
            }
        }
    }

    // MARK: - Remotes

    private var remotesSection: some View {
        SidebarSection(
            title: "REMOTE",
            icon: "network",
            count: viewModel.remotes.count,
            isCollapsed: viewModel.isSectionCollapsed("remote"),
            onToggle: { viewModel.toggleSection("remote") },
            animateCollapse: remoteSectionShouldAnimate,
            onAdd: { showAddRemote = true }
        ) {
            ForEach(viewModel.remotes) { remote in
                let shouldAnimate = remoteDisclosureShouldAnimate(remote.name)
                let isCollapsed = isRemoteCollapsed(remote.name)

                VStack(alignment: .leading, spacing: 0) {
                    SidebarRemoteDisclosureRow(
                        name: remote.name,
                        isCollapsed: isCollapsed,
                        onToggle: {
                            toggleRemoteDisclosure(remote.name, animate: shouldAnimate)
                        }
                    )
                    .padding(.leading, 24)
                    .contextMenu {
                        Group {
                            Button {
                                editingRemote = remote
                                editRemoteName = remote.name
                                editRemoteURL = remote.url
                                showEditRemote = true
                            } label: {
                                Label("Edit Remote…", systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                Task { await viewModel.performDeleteRemote(name: remote.name) }
                            } label: {
                                Label("Delete Remote", systemImage: "trash")
                            }
                        }
                        .font(AppTypography.Sidebar.contextMenu)
                    }

                    if !isCollapsed {
                        let branches = viewModel.remoteBranchGroups[remote.name] ?? []
                        let remoteTree = makeBranchTree(branches: branches, prefix: remote.name)
                        let remoteFlat = flattenBranchTree(remoteTree, depth: 0, collapsedFolders: collapsedRemoteFolders)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(remoteFlat) { node in
                                if let branch = node.branchInfo {
                                    SidebarBranchRow(
                                        name: node.displayName,
                                        isCurrent: false,
                                        icon: "arrow.triangle.branch",
                                        indentDepth: node.depth
                                    )
                                    .padding(.leading, 32)
                                    .onTapGesture(count: 2) {
                                        Task { await viewModel.performCheckoutBranch(branch.name) }
                                    }
                                    .onTapGesture {
                                        Task { await viewModel.scrollToCommitForBranch(branch) }
                                    }
                                    .contextMenu {
                                        remoteBranchContextMenu(branch, remoteName: remote.name)
                                            .font(AppTypography.Sidebar.contextMenu)
                                    }
                                } else {
                                    BranchGroupRow(
                                        name: node.displayName,
                                        isCollapsed: collapsedRemoteFolders.contains(node.fullPath),
                                        depth: node.depth
                                    )
                                    .padding(.leading, 32)
                                    .onTapGesture {
                                        if collapsedRemoteFolders.contains(node.fullPath) {
                                            collapsedRemoteFolders.remove(node.fullPath)
                                        } else {
                                            collapsedRemoteFolders.insert(node.fullPath)
                                        }
                                    }
                                }
                            }
                        }
                        .transition(
                            shouldAnimate
                                ? .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                                    removal: .opacity
                                  )
                                : .identity
                        )
                    }
                }
            }
        }
    }

    // MARK: - Tag Context Menu

    @ViewBuilder
    private func tagContextMenu(_ tag: String) -> some View {
        let cur = viewModel.currentBranch

        Button("Push \(tag) to origin") {
            Task { await viewModel.performPushTag(name: tag, remote: "origin") }
        }

        Divider()

        Button("Rebase \(cur) onto \(tag)") {
            Task { await viewModel.performRebase(onto: tag) }
        }
        Button("Checkout \(tag)") {
            Task { await viewModel.performCheckoutBranch(tag) }
        }

        Divider()

        Button("Create branch here") {
            branchFromTagName = tag
            newBranchFromTagName = ""
            showCreateBranchFromTag = true
        }
        Menu("Reset \(cur) to this") {
            Button("Soft") {
                Task {
                    if let hash = try? await viewModel.getTagCommitHash(tag) {
                        await viewModel.performReset(hash, mode: .soft)
                    }
                }
            }
            Button("Mixed") {
                Task {
                    if let hash = try? await viewModel.getTagCommitHash(tag) {
                        await viewModel.performReset(hash, mode: .mixed)
                    }
                }
            }
            Button("Hard") {
                Task {
                    if let hash = try? await viewModel.getTagCommitHash(tag) {
                        await viewModel.performReset(hash, mode: .hard)
                    }
                }
            }
        }
        Button("Revert \(tag)") {
            Task {
                if let hash = try? await viewModel.getTagCommitHash(tag) {
                    await viewModel.performRevert(hash)
                }
            }
        }

        Divider()

        Button("Delete \(tag) locally", role: .destructive) {
            Task { await viewModel.performDeleteTag(tag) }
        }
        if viewModel.knownRemoteTags.contains(tag) {
            Button("Delete \(tag) remotely", role: .destructive) {
                Task { await viewModel.performDeleteRemoteTag(name: tag, remote: "origin") }
            }
        }

        Divider()

        Button("Copy tag name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tag, forType: .string)
        }

        Divider()

        Button("Annotate \(tag)...") {
            annotatingTagName = tag
            annotateTagMessage = ""
            showAnnotateTag = true
            Task {
                if let existing = await viewModel.getTagMessage(tag) {
                    annotateTagMessage = existing
                }
            }
        }
    }

    // MARK: - Tag Sheets

    private var annotateTagSheet: some View {
        VStack(spacing: 12) {
            Text("Annotate Tag \"\(annotatingTagName)\"")
                .font(.headline)
            FocusTextField(titleKey: "Annotation message", text: $annotateTagMessage, axis: .vertical)
                .frame(width: 320)
                .lineLimit(4, reservesSpace: true)
            HStack {
                Button("Cancel") { showAnnotateTag = false }
                    .keyboardShortcut(.cancelAction)
                Button("Annotate") {
                    let name = annotatingTagName
                    let msg = annotateTagMessage.trimmingCharacters(in: .whitespaces)
                    showAnnotateTag = false
                    guard !msg.isEmpty else { return }
                    Task { await viewModel.performAnnotateTag(name: name, message: msg) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(annotateTagMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var createBranchFromTagSheet: some View {
        VStack(spacing: 12) {
            Text("Create Branch from \"\(branchFromTagName)\"")
                .font(.headline)
            FocusTextField(titleKey: "Branch name", text: $newBranchFromTagName)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showCreateBranchFromTag = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = newBranchFromTagName.trimmingCharacters(in: .whitespaces)
                    let tagName = branchFromTagName
                    showCreateBranchFromTag = false
                    guard !name.isEmpty else { return }
                    Task {
                        if let hash = try? await viewModel.getTagCommitHash(tagName) {
                            await viewModel.performCreateBranchAt(name: name, commitHash: hash)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchFromTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        SidebarSection(
            title: "TAGS",
            icon: "tag",
            count: viewModel.tags.count,
            isCollapsed: viewModel.isSectionCollapsed("tags"),
            onToggle: { viewModel.toggleSection("tags") },
            animateCollapse: tagsSectionShouldAnimate
        ) {
            ForEach(viewModel.tags, id: \.self) { tag in
                SidebarTagRow(name: tag)
                    .onTapGesture(count: 2) {
                        Task { await viewModel.performCheckoutBranch(tag) }
                    }
                    .onTapGesture {
                        Task { await viewModel.scrollToCommitForTag(tag) }
                    }
                    .contextMenu {
                        tagContextMenu(tag)
                            .font(AppTypography.Sidebar.contextMenu)
                    }
            }
        }
    }

    // MARK: - Stashes

    private var stashesSection: some View {
        SidebarSection(
            title: "STASHES",
            icon: "tray",
            count: viewModel.stashes.count,
            isCollapsed: viewModel.isSectionCollapsed("stashes"),
            onToggle: { viewModel.toggleSection("stashes") },
            animateCollapse: stashesSectionShouldAnimate
        ) {
            ForEach(viewModel.stashes) { stash in
                SidebarStashRow(stash: stash)
                    .onTapGesture {
                        Task { await viewModel.scrollToCommitForStash(stash) }
                    }
                    .contextMenu {
                        Group {
                            Button("Apply (keep stash)") {
                                Task { await viewModel.performStashApplyAt(stash: stash) }
                            }
                            Button("Pop (apply & delete)") {
                                Task { await viewModel.performStashPopAt(stash: stash) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                stashPendingDrop = stash
                            }
                        }
                        .font(AppTypography.Sidebar.contextMenu)
                    }
            }
        }
    }

    // MARK: - Submodules

    private var submodulesSection: some View {
        SidebarSection(
            title: "SUBMODULES",
            icon: "shippingbox",
            count: viewModel.submodules.count,
            isCollapsed: viewModel.isSectionCollapsed("submodules"),
            onToggle: { viewModel.toggleSection("submodules") },
            animateCollapse: submodulesSectionShouldAnimate
        ) {
            ForEach(viewModel.submodules) { sub in
                Label(sub.name, systemImage: "shippingbox")
                    .font(.caption)
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Merge Requests

    private var mergeRequestsSection: some View {
        SidebarSection(
            title: viewModel.mergeRequestsSectionTitle,
            icon: "arrow.triangle.pull",
            count: viewModel.mergeRequests.count,
            isCollapsed: viewModel.isSectionCollapsed("mergeRequests"),
            onToggle: {
                let wasCollapsed = viewModel.isSectionCollapsed("mergeRequests")
                viewModel.toggleSection("mergeRequests")
                // 展开时加载数据
                if wasCollapsed {
                    Task { await viewModel.loadMergeRequests() }
                }
            },
            onRefresh: {
                Task { await viewModel.loadMergeRequests() }
            }
        ) {
            // State filter picker
            HStack(spacing: 2) {
                ForEach(CodeReviewFilter.allCases) { filter in
                    Button {
                        Task { await viewModel.setMRFilter(filter) }
                    } label: {
                        Text(filter.displayName)
                            .font(.system(size: 10, weight: viewModel.mrStateFilter == filter ? .bold : .regular))
                            .foregroundStyle(viewModel.mrStateFilter == filter ? .white : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    viewModel.mrStateFilter == filter
                                        ? Color.accentColor.opacity(0.8)
                                        : Color(.separatorColor).opacity(0.5)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 4)

            if viewModel.isMRLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let error = viewModel.mrError {
                Text(error)
                    .font(AppTypography.Sidebar.row)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
            } else if viewModel.mergeRequests.isEmpty {
                Text(viewModel.mergeRequestsEmptyStateText)
                    .font(AppTypography.Sidebar.rowMeta)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 28)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.mergeRequests) { mr in
                    SidebarMRRow(mr: mr)
                        .contextMenu {
                            mrContextMenu(mr)
                                .font(AppTypography.Sidebar.contextMenu)
                        }
                        .onTapGesture(count: 2) {
                            viewModel.openMRInBrowser(mr)
                        }
                        .onTapGesture { }
                }
            }
        }
    }

    @ViewBuilder
    private func mrContextMenu(_ mr: CodeReviewItem) -> some View {
        Button("Open in Browser") {
            viewModel.openMRInBrowser(mr)
        }

        if viewModel.canPerformMerge(for: mr), let mergeActionTitle = viewModel.mergeActionTitle {
            Divider()
            Button(mergeActionTitle) {
                mergingMR = mr
                showMergeConfirm = true
            }
            .disabled(viewModel.isMRMerging)
        }

        Divider()

        Button("Copy Title") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(mr.title, forType: .string)
        }
        Button("Copy Source Branch") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(mr.sourceBranch, forType: .string)
        }
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(mr.webURL, forType: .string)
        }
    }
}

// MARK: - Reusable Components

struct SidebarSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int?
    let isCollapsed: Bool
    let onToggle: () -> Void
    let animateCollapse: Bool
    let onAdd: (() -> Void)?
    let onRefresh: (() -> Void)?
    let headerContextMenu: (() -> AnyView)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        count: Int? = nil,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        animateCollapse: Bool = true,
        onAdd: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        headerContextMenu: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.animateCollapse = animateCollapse
        self.onAdd = onAdd
        self.onRefresh = onRefresh
        self.headerContextMenu = headerContextMenu
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button(action: {
                    if animateCollapse {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onToggle()
                        }
                    } else {
                        onToggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(AppTypography.Sidebar.sectionChevron)
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)

                        Image(systemName: icon)
                            .font(AppTypography.Sidebar.rowMeta)
                            .foregroundStyle(.secondary)

                        Text(title)
                            .font(AppTypography.Sidebar.sectionHeader)
                            .foregroundStyle(.secondary)

                        if let count {
                            Text("\(count)")
                                .font(AppTypography.Sidebar.sectionCount)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color(.separatorColor)))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppTypography.Sidebar.rowMetaStrong)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip("Refresh")
                }

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(AppTypography.Sidebar.rowMetaStrong)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .hoverTooltip("Add")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu {
                if let headerContextMenu {
                    headerContextMenu()
                }
            }

            if !isCollapsed {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .transition(
                    animateCollapse
                        ? .opacity
                        : .identity
                )
                .clipped()
            }
        }
    }
}

private struct SidebarRemoteDisclosureRow: View {
    let name: String
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(AppTypography.Sidebar.sectionChevron)
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)

                Label(name, systemImage: "externaldrive.connected.to.line.below")
                    .font(AppTypography.Sidebar.row)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.trailing, 8)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarBranchRow: View {
    let name: String
    let isCurrent: Bool
    let icon: String
    var ahead: Int = 0
    var behind: Int = 0
    var badge: String? = nil
    var badgeColor: Color = .secondary
    var iconColor: Color? = nil
    var indentDepth: Int = 0

    @State private var isHovering = false

    private var branchNameColor: Color {
        isCurrent ? Color(nsColor: .controlAccentColor) : .primary
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(isCurrent ? .green : (iconColor ?? .secondary))

            if let badge = badge {
                Text(badge)
                    .font(AppTypography.Sidebar.rowMonoStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeColor.opacity(0.75)))
            }

            Text(name)
                .font(AppTypography.Sidebar.row)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(branchNameColor)
                .lineLimit(1)

            Spacer()

            if ahead > 0 || behind > 0 {
                aheadBehindBadge
            }

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTypography.Sidebar.rowMeta)
                    .foregroundStyle(.green)
            }
        }
        .padding(.leading, CGFloat(28 + indentDepth * 12))
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }

    private var aheadBehindBadge: some View {
        HStack(spacing: 2) {
            if ahead > 0 {
                HStack(spacing: 1) {
                    Text("\(ahead)")
                        .font(AppTypography.Sidebar.rowMono)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            if behind > 0 {
                HStack(spacing: 1) {
                    Text("\(behind)")
                        .font(AppTypography.Sidebar.rowMono)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct SidebarDetachedHeadRow: View {
    let shortHash: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "point.topleft.filled.down.to.point.bottomright.curvepath")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.orange)

            Text("HEAD")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.orange.opacity(0.8)))

            Text(shortHash)
                .font(AppTypography.Sidebar.rowMonoLarge)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text("detached")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.tertiary)
                .italic()
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.orange.opacity(0.06))
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Code Review Row

struct SidebarMRRow: View {
    let mr: CodeReviewItem

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                // State icon
                Image(systemName: mrStateIcon)
                    .font(AppTypography.Sidebar.rowMeta)
                    .foregroundStyle(mrStateColor)

                Text(mr.numberDisplay)
                    .font(AppTypography.Sidebar.rowMonoStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(mrStateColor.opacity(0.75)))

                if mr.isDraft {
                    Text("Draft")
                        .font(AppTypography.Sidebar.rowMeta)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(.separatorColor)))
                }

                Spacer()

                if let author = mr.author {
                    Text(author.displayName)
                        .font(AppTypography.Sidebar.rowMeta)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(mr.title)
                .font(AppTypography.Sidebar.row)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(AppTypography.Sidebar.rowMeta)
                    .foregroundStyle(.tertiary)
                Text(mr.sourceBranch)
                    .font(AppTypography.Sidebar.rowMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                Text(mr.targetBranch)
                    .font(AppTypography.Sidebar.rowMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }

    private var mrStateIcon: String {
        switch mr.state {
        case .opened: return "arrow.triangle.pull"
        case .closed: return "xmark.circle"
        case .merged: return "arrow.triangle.merge"
        }
    }

    private var mrStateColor: Color {
        switch mr.state {
        case .opened: return .green
        case .closed: return .red
        case .merged: return .purple
        }
    }
}

// MARK: - Tag Row

struct SidebarTagRow: View {
    let name: String
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tag")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.secondary)
            
            Text(name)
                .font(AppTypography.Sidebar.row)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Branch Tree

indirect enum BranchTreeNode: Identifiable {
    case folder(name: String, fullPath: String, children: [BranchTreeNode])
    case leaf(BranchInfo, displayName: String)

    var id: String {
        switch self {
        case .folder(_, let p, _): return "F:\(p)"
        case .leaf(let b, _): return "L:\(b.id)"
        }
    }
}

struct FlatBranchNode: Identifiable {
    let id: String
    let displayName: String
    let fullPath: String
    let depth: Int
    let branchInfo: BranchInfo?
}

func makeBranchTree(branches: [BranchInfo], prefix: String = "") -> [BranchTreeNode] {
    var folders: [String: [BranchInfo]] = [:]
    var leaves: [BranchInfo] = []

    for branch in branches {
        let remaining: String
        if prefix.isEmpty {
            remaining = branch.name
        } else {
            let prefixWithSlash = prefix + "/"
            guard branch.name.hasPrefix(prefixWithSlash) else { continue }
            remaining = String(branch.name.dropFirst(prefixWithSlash.count))
        }
        if let slash = remaining.firstIndex(of: "/") {
            let seg = String(remaining[..<slash])
            folders[seg, default: []].append(branch)
        } else {
            leaves.append(branch)
        }
    }

    var nodes: [BranchTreeNode] = []
    for b in leaves.sorted(by: { $0.name < $1.name }) {
        let displayName = prefix.isEmpty ? b.name : String(b.name.dropFirst(prefix.count + 1))
        nodes.append(.leaf(b, displayName: displayName))
    }
    for seg in folders.keys.sorted() {
        let fullPath = prefix.isEmpty ? seg : "\(prefix)/\(seg)"
        let children = makeBranchTree(branches: folders[seg]!, prefix: fullPath)
        nodes.append(.folder(name: seg, fullPath: fullPath, children: children))
    }
    return nodes
}

func flattenBranchTree(_ nodes: [BranchTreeNode], depth: Int, collapsedFolders: Set<String>) -> [FlatBranchNode] {
    var result: [FlatBranchNode] = []
    for node in nodes {
        switch node {
        case .folder(let name, let path, let children):
            result.append(FlatBranchNode(id: "F:\(path)", displayName: name, fullPath: path, depth: depth, branchInfo: nil))
            if !collapsedFolders.contains(path) {
                result += flattenBranchTree(children, depth: depth + 1, collapsedFolders: collapsedFolders)
            }
        case .leaf(let branch, let displayName):
            result.append(FlatBranchNode(id: "L:\(branch.id)", displayName: displayName, fullPath: branch.name, depth: depth, branchInfo: branch))
        }
    }
    return result
}

struct BranchGroupRow: View {
    let name: String
    let isCollapsed: Bool
    let depth: Int

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 9)
            Image(systemName: "folder")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.secondary)
            Text(name)
                .font(AppTypography.Sidebar.row)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, CGFloat(28 + depth * 12))
        .padding(.trailing, 12)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.12) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Working Tree Files

private struct FlatWorkingTreeNode: Identifiable {
    enum Kind {
        case folder
        case file
    }

    let id: String
    let kind: Kind
    let displayName: String
    let relativePath: String
    let depth: Int
}

private enum FileTreeEditState: Equatable {
    case createFolder(parentPath: String, pendingName: String, depth: Int)
    case createFile(parentPath: String, pendingName: String, depth: Int)
    case rename(path: String, originalName: String, pendingName: String, depth: Int)
}

private struct PendingWorkingTreeDelete: Identifiable, Equatable {
    let path: String
    let displayName: String
    let isFolder: Bool

    var id: String { path }
}

private enum FileTreeListRow: Identifiable {
    case node(FlatWorkingTreeNode)
    case create(parentPath: String, depth: Int, isFolder: Bool)

    var id: String {
        switch self {
        case .node(let node):
            return node.id
        case .create(let parentPath, _, let isFolder):
            return "create:\(isFolder ? "folder" : "file"):\(parentPath)"
        }
    }
}

private func flattenWorkingTree(
    _ nodes: [WorkingTreeFileNode],
    folderContents: [String: [WorkingTreeFileNode]],
    depth: Int,
    collapsedFolders: Set<String>
) -> [FlatWorkingTreeNode] {
    var result: [FlatWorkingTreeNode] = []

    for node in nodes {
        switch node {
        case .folder(let name, let relativePath):
            result.append(
                FlatWorkingTreeNode(
                    id: "folder:\(relativePath)",
                    kind: .folder,
                    displayName: name,
                    relativePath: relativePath,
                    depth: depth
                )
            )
            if !collapsedFolders.contains(relativePath),
               let children = folderContents[relativePath] {
                result += flattenWorkingTree(
                    children,
                    folderContents: folderContents,
                    depth: depth + 1,
                    collapsedFolders: collapsedFolders
                )
            }
        case .file(let name, let relativePath):
            result.append(
                FlatWorkingTreeNode(
                    id: "file:\(relativePath)",
                    kind: .file,
                    displayName: name,
                    relativePath: relativePath,
                    depth: depth
                )
            )
        }
    }

    return result
}

private struct SidebarFileFolderRow: View {
    let name: String
    let isCollapsed: Bool
    let depth: Int

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 9)
            Image(systemName: "folder")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.secondary)
            Text(name)
                .font(AppTypography.Sidebar.row)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, CGFloat(28 + depth * 12))
        .padding(.trailing, 12)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.12) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct SidebarFileInlineEditorRow: View {
    @Binding var name: String
    let icon: String
    let depth: Int
    let isFolder: Bool
    let placeholder: String
    var submitLabel: SubmitLabel = .done
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $name)
                .textFieldStyle(.plain)
                .font(AppTypography.Sidebar.row)
                .foregroundStyle(.primary)
                .focused($isFocused)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        onCancel()
                    }
                }

            Spacer()
        }
        .padding(.leading, CGFloat(28 + depth * 12))
        .padding(.trailing, 12)
        .padding(.vertical, isFolder ? 2 : 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.selectedContentBackgroundColor).opacity(0.12))
                .padding(.horizontal, 4)
        )
        .onAppear {
            isFocused = true
        }
    }
}

private struct SidebarFileRow: View {
    let name: String
    let depth: Int
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text")
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)

            Text(name)
                .font(AppTypography.Sidebar.row)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, CGFloat(28 + depth * 12))
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.88)
        }
        if isHovering {
            return Color(.selectedContentBackgroundColor).opacity(0.15)
        }
        return .clear
    }
}

// MARK: - Stash Row

struct SidebarStashRow: View {
    let stash: StashInfo
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stash.message)
                .font(AppTypography.Sidebar.row)
                .lineLimit(1)
            Text(stash.index)
                .font(AppTypography.Sidebar.rowMeta)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

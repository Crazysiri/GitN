import SwiftUI

struct SidebarView: View {
    let viewModel: RepoViewModel

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

    @State private var collapsedLocalFolders: Set<String> = []
    @State private var collapsedRemoteFolders: Set<String> = []

    @State private var showAnnotateTag = false
    @State private var annotatingTagName = ""
    @State private var annotateTagMessage = ""

    @State private var showCreateBranchFromTag = false
    @State private var branchFromTagName = ""
    @State private var newBranchFromTagName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    localBranchesSection
                    remotesSection
                    tagsSection
                    stashesSection
                    submodulesSection
                    mergeRequestsSection
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .sheet(isPresented: $showAddRemote) {
            addRemoteSheet
        }
        .sheet(isPresented: $showEditRemote) { editRemoteSheet }
        .sheet(isPresented: $showRenameBranch) { renameBranchSheet }
        .sheet(isPresented: $showCreateTagAtBranch) { createTagAtBranchSheet }
        .sheet(isPresented: $showCreateBranchFrom) { createBranchFromSheet }
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
    }

    // MARK: - Add Remote Sheet

    private var addRemoteSheet: some View {
        VStack(spacing: 12) {
            Text("Add Remote")
                .font(.headline)
            TextField("Remote name (e.g. origin)", text: $newRemoteName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            TextField("Remote URL", text: $newRemoteURL)
                .textFieldStyle(.roundedBorder)
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

    // MARK: - Local Branch Context Menu

    @ViewBuilder
    private func localBranchContextMenu(_ branch: BranchInfo) -> some View {
        let cur = viewModel.currentBranch

        // Pull
        if branch.isCurrent {
            Button("Pull \(branch.name)") {
                Task { await viewModel.performPull() }
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
            Divider()
        }

        Button("Create branch here") {
            branchFromName = branch.name
            branchFromIsRemote = false
            branchFromHash = branch.shortHash
            newBranchFromName = ""
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
            TextField("New name", text: $renamedBranchName)
                .textFieldStyle(.roundedBorder)
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
            TextField("Tag name", text: $tagAtBranchName)
                .textFieldStyle(.roundedBorder)
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
            TextField("Branch name", text: $newBranchFromName)
                .textFieldStyle(.roundedBorder)
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
            TextField("Remote", text: $upstreamRemote)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            TextField("Branch", text: $upstreamBranch)
                .textFieldStyle(.roundedBorder)
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
            TextField("Remote name", text: $editRemoteName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            TextField("Remote URL", text: $editRemoteURL)
                .textFieldStyle(.roundedBorder)
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
            onToggle: { viewModel.toggleSection("local") }
        ) {
            // Detached HEAD indicator
            if viewModel.isDetachedHead {
                SidebarDetachedHeadRow(
                    shortHash: viewModel.currentBranch
                )
                .onTapGesture {
                    viewModel.scrollToCommitHash = viewModel.currentBranch
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
                            .font(.system(size: 11, weight: .medium))
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

    // MARK: - Remotes

    private var remotesSection: some View {
        SidebarSection(
            title: "REMOTE",
            icon: "network",
            count: viewModel.remotes.count,
            isCollapsed: viewModel.isSectionCollapsed("remote"),
            onToggle: { viewModel.toggleSection("remote") },
            onAdd: { showAddRemote = true }
        ) {
            ForEach(viewModel.remotes) { remote in
                DisclosureGroup {
                    let branches = viewModel.remoteBranchGroups[remote.name] ?? []
                    let remoteTree = makeBranchTree(branches: branches, prefix: remote.name)
                    let remoteFlat = flattenBranchTree(remoteTree, depth: 0, collapsedFolders: collapsedRemoteFolders)
                    ForEach(remoteFlat) { node in
                        if let branch = node.branchInfo {
                            SidebarBranchRow(
                                name: node.displayName,
                                isCurrent: false,
                                icon: "arrow.triangle.branch",
                                indentDepth: node.depth
                            )
                            .padding(.leading, 8)
                            .onTapGesture(count: 2) {
                                Task { await viewModel.performCheckoutBranch(branch.name) }
                            }
                            .onTapGesture {
                                Task { await viewModel.scrollToCommitForBranch(branch) }
                            }
                            .contextMenu {
                                remoteBranchContextMenu(branch, remoteName: remote.name)
                                    .font(.system(size: 11, weight: .medium))
                            }
                        } else {
                            BranchGroupRow(
                                name: node.displayName,
                                isCollapsed: collapsedRemoteFolders.contains(node.fullPath),
                                depth: node.depth
                            )
                            .padding(.leading, 8)
                            .onTapGesture {
                                if collapsedRemoteFolders.contains(node.fullPath) {
                                    collapsedRemoteFolders.remove(node.fullPath)
                                } else {
                                    collapsedRemoteFolders.insert(node.fullPath)
                                }
                            }
                        }
                    }
                } label: {
                    Label(remote.name, systemImage: "externaldrive.connected.to.line.below")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
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
                    .font(.system(size: 11, weight: .medium))
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
            TextField("Annotation message", text: $annotateTagMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
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
            TextField("Branch name", text: $newBranchFromTagName)
                .textFieldStyle(.roundedBorder)
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
            onToggle: { viewModel.toggleSection("tags") }
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
                            .font(.system(size: 11, weight: .medium))
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
            onToggle: { viewModel.toggleSection("stashes") }
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
                                Task { await viewModel.performStashDrop(stash: stash) }
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
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
            onToggle: { viewModel.toggleSection("submodules") }
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
                            .font(.system(size: 9, weight: viewModel.mrStateFilter == filter ? .bold : .regular))
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
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
            } else if viewModel.mergeRequests.isEmpty {
                Text(viewModel.mergeRequestsEmptyStateText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 28)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.mergeRequests) { mr in
                    SidebarMRRow(mr: mr)
                        .contextMenu {
                            mrContextMenu(mr)
                                .font(.system(size: 11, weight: .medium))
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
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onAdd: (() -> Void)?
    let onRefresh: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        count: Int,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        onAdd: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.onAdd = onAdd
        self.onRefresh = onRefresh
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)

                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("\(count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(.separatorColor)))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }

                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !isCollapsed {
                content()
            }
        }
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

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(isCurrent ? .green : (iconColor ?? .secondary))

            if let badge = badge {
                Text(badge)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeColor.opacity(0.75)))
            }

            Text(name)
                .font(.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)

            Spacer()

            if ahead > 0 || behind > 0 {
                aheadBehindBadge
            }

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
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
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            if behind > 0 {
                HStack(spacing: 1) {
                    Text("\(behind)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                .font(.caption2)
                .foregroundStyle(.orange)

            Text("HEAD")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.orange.opacity(0.8)))

            Text(shortHash)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text("detached")
                .font(.system(size: 9))
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
                    .font(.caption2)
                    .foregroundStyle(mrStateColor)

                Text(mr.numberDisplay)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(mrStateColor.opacity(0.75)))

                if mr.isDraft {
                    Text("Draft")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(.separatorColor)))
                }

                Spacer()

                if let author = mr.author {
                    Text(author.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(mr.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(mr.sourceBranch)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                Text(mr.targetBranch)
                    .font(.system(size: 9, design: .monospaced))
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(name)
                .font(.caption)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.caption)
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

// MARK: - Stash Row

struct SidebarStashRow: View {
    let stash: StashInfo
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stash.message)
                .font(.caption)
                .lineLimit(1)
            Text(stash.index)
                .font(.caption2)
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

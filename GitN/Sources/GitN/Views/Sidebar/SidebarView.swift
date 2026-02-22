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
    @State private var newBranchFromName = ""

    @State private var showSetUpstream = false
    @State private var upstreamRemote = "origin"
    @State private var upstreamBranch = ""

    var body: some View {
        VStack(spacing: 0) {
            repoHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    localBranchesSection
                    remotesSection
                    tagsSection
                    stashesSection
                    submodulesSection
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
            Button("Delete \(branch.name)", role: .destructive) {
                Task { await viewModel.performDeleteBranch(branch.name) }
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
                    Task { await viewModel.performCreateBranchAt(name: name, commitHash: branchFromHash) }
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

    // MARK: - Header

    private var repoHeader: some View {
        HStack {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.repoName)
                    .font(.headline)
                    .lineLimit(1)
                if !viewModel.currentBranch.isEmpty {
                    Text(viewModel.currentBranch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Local Branches

    private var localBranchesSection: some View {
        SidebarSection(
            title: "LOCAL",
            icon: "arrow.triangle.branch",
            count: viewModel.localBranches.count,
            isCollapsed: viewModel.isSectionCollapsed("local"),
            onToggle: { viewModel.toggleSection("local") }
        ) {
            ForEach(viewModel.localBranches) { branch in
                SidebarBranchRow(
                    name: branch.name,
                    isCurrent: branch.isCurrent,
                    icon: "arrow.triangle.branch"
                )
                .onTapGesture { viewModel.scrollToCommitForBranch(branch) }
                .contextMenu {
                    localBranchContextMenu(branch)
                        .font(.system(size: 11, weight: .medium))
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
                    ForEach(branches) { branch in
                        let shortName = branch.name
                            .replacingOccurrences(of: "\(remote.name)/", with: "")
                        SidebarBranchRow(name: shortName, isCurrent: false, icon: "arrow.triangle.branch")
                            .padding(.leading, 8)
                            .contextMenu {
                                remoteBranchContextMenu(branch, remoteName: remote.name)
                                    .font(.system(size: 11, weight: .medium))
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
                Label(tag, systemImage: "tag")
                    .font(.caption)
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.vertical, 2)
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
                .padding(.vertical, 2)
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
}

// MARK: - Reusable Components

struct SidebarSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onAdd: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        count: Int,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        onAdd: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
        self.onAdd = onAdd
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

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(isCurrent ? .green : .secondary)

            Text(name)
                .font(.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)

            Spacer()

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
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

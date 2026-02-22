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
        .sheet(isPresented: $showEditRemote) {
            editRemoteSheet
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
                    }
                } label: {
                    Label(remote.name, systemImage: "externaldrive.connected.to.line.below")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(.leading, 24)
                .contextMenu {
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

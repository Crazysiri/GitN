import SwiftUI

struct SidebarView: View {
    let viewModel: RepoViewModel

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
            onToggle: { viewModel.toggleSection("remote") }
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
                .padding(.leading, 12)
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
                    .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovering = $0 }
    }
}

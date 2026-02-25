import SwiftUI
import AppKit

struct GraphView: View {
    let viewModel: RepoViewModel

    @State private var showCreateTagSheet = false
    @State private var showCreateBranchSheet = false
    @State private var showEditMessageSheet = false
    @State private var showSetUpstreamSheet = false
    @State private var contextCommit: CommitInfo?
    @State private var tagName = ""
    @State private var newBranchNameAtCommit = ""
    @State private var editedMessage = ""
    @State private var upstreamRemote = "origin"
    @State private var upstreamBranch = ""

    private let rowHeight: CGFloat = 24
    private let columnWidth: CGFloat = 18
    private let avatarSize: CGFloat = 18
    private let graphAreaWidth: CGFloat = 150
    private let refsColumnWidth: CGFloat = 86

    var body: some View {
        VStack(spacing: 0) {

            graphHeader
            Divider()

            if viewModel.commits.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                CommitTableView(
                    commits: viewModel.commits,
                    selectedCommitHash: viewModel.selectedCommit?.hash,
                    currentBranch: viewModel.currentBranch,
                    hasUnresolvedConflicts: viewModel.hasUnresolvedConflicts,
                    scrollToHash: viewModel.scrollToCommitHash,
                    rowHeight: rowHeight,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize,
                    graphAreaWidth: graphAreaWidth,
                    refsColumnWidth: refsColumnWidth,
                    onSelectCommit: { commit in
                        Task { await viewModel.selectCommit(commit) }
                    },
                    onConsumeScrollToHash: {
                        viewModel.scrollToCommitHash = nil
                    },
                    onContextAction: { commit, action in
                        handleContextAction(commit: commit, action: action)
                    }
                )
            }
        }
        .background(Color(.textBackgroundColor))
        .sheet(isPresented: $showCreateTagSheet) { createTagSheet }
        .sheet(isPresented: $showCreateBranchSheet) { createBranchAtSheet }
        .sheet(isPresented: $showEditMessageSheet) { editMessageSheet }
        .sheet(isPresented: $showSetUpstreamSheet) { setUpstreamSheet }
    }

    // MARK: - Context Action Handler

    private func handleContextAction(commit: CommitInfo, action: CommitContextAction) {
        switch action {
        case .merge(let branch):
            Task { await viewModel.performMerge(branch) }
        case .rebase(let branch):
            Task { await viewModel.performRebase(onto: branch) }
        case .checkoutBranch(let branch):
            Task { await viewModel.performCheckoutBranch(branch) }
        case .checkoutCommit(let hash):
            Task { await viewModel.performCheckoutCommit(hash) }
        case .setUpstream:
            contextCommit = commit
            upstreamBranch = viewModel.currentBranch
            upstreamRemote = "origin"
            showSetUpstreamSheet = true
        case .createBranch:
            contextCommit = commit
            newBranchNameAtCommit = ""
            showCreateBranchSheet = true
        case .cherryPick(let hash):
            Task { await viewModel.performCherryPick(hash) }
        case .resetSoft(let hash):
            Task { await viewModel.performReset(hash, mode: .soft) }
        case .resetMixed(let hash):
            Task { await viewModel.performReset(hash, mode: .mixed) }
        case .resetHard(let hash):
            Task { await viewModel.performReset(hash, mode: .hard) }
        case .editMessage:
            contextCommit = commit
            editedMessage = commit.message
            showEditMessageSheet = true
        case .revert(let hash):
            Task { await viewModel.performRevert(hash) }
        case .deleteBranch(let branch):
            Task { await viewModel.performDeleteBranch(branch) }
        case .copySHA(let hash):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hash, forType: .string)
        case .compareWithWorkingDir:
            Task { await viewModel.performCompareWithWorkingDirectory(commit) }
        case .createTag:
            contextCommit = commit
            tagName = ""
            showCreateTagSheet = true
        case .squashCommits(let hashes):
            Task { await viewModel.performSquashCommits(hashes) }
        }
    }

    // MARK: - Header

    private var graphHeader: some View {
        HStack(spacing: 0) {
            Text("Branch / Tag")
                .frame(width: refsColumnWidth, alignment: .leading)
                .padding(.leading, 8)
            Divider().frame(height: 12)
            Text("Graph")
                .frame(width: graphAreaWidth, alignment: .leading)
                .padding(.leading, 6)
            Divider().frame(height: 12)
            Text("Commit Message")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No commits yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    private var createTagSheet: some View {
        VStack(spacing: 12) {
            Text("Create Tag")
                .font(.headline)
            TextField("Tag name", text: $tagName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showCreateTagSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let c = contextCommit else { return }
                    let name = tagName.trimmingCharacters(in: .whitespaces)
                    showCreateTagSheet = false
                    guard !name.isEmpty else { return }
                    Task { await viewModel.performCreateTag(name: name, at: c.hash) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var createBranchAtSheet: some View {
        VStack(spacing: 12) {
            Text("Create Branch")
                .font(.headline)
            if let c = contextCommit {
                Text("At \(c.shortHash) – \(c.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 280)
            }
            TextField("Branch name", text: $newBranchNameAtCommit)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Button("Cancel") { showCreateBranchSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let c = contextCommit else { return }
                    let name = newBranchNameAtCommit.trimmingCharacters(in: .whitespaces)
                    showCreateBranchSheet = false
                    guard !name.isEmpty else { return }
                    Task { await viewModel.performCreateBranchAt(name: name, commitHash: c.hash) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchNameAtCommit.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private var editMessageSheet: some View {
        VStack(spacing: 12) {
            Text("Edit Commit Message")
                .font(.headline)
            TextEditor(text: $editedMessage)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 400, height: 120)
                .border(Color(.separatorColor))
            HStack {
                Button("Cancel") { showEditMessageSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let c = contextCommit else { return }
                    let msg = editedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    showEditMessageSheet = false
                    guard !msg.isEmpty else { return }
                    Task { await viewModel.performEditCommitMessage(hash: c.hash, newMessage: msg) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                Button("Cancel") { showSetUpstreamSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    let remote = upstreamRemote.trimmingCharacters(in: .whitespaces)
                    let branch = upstreamBranch.trimmingCharacters(in: .whitespaces)
                    showSetUpstreamSheet = false
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
}

// MARK: - Context Action Enum

enum CommitContextAction {
    case merge(String)
    case rebase(String)
    case checkoutBranch(String)
    case checkoutCommit(String)
    case setUpstream
    case createBranch
    case cherryPick(String)
    case resetSoft(String)
    case resetMixed(String)
    case resetHard(String)
    case editMessage
    case revert(String)
    case deleteBranch(String)
    case copySHA(String)
    case compareWithWorkingDir
    case createTag
    case squashCommits([String])
}

// MARK: - NSTableView Wrapper
//
// Uses AppKit NSTableView instead of SwiftUI ScrollView+LazyVStack for proper
// cell reuse and native scrolling performance. Inspired by Xit's HistoryTableController.
// Key advantages:
// 1. Cell reuse — only a fixed number of row views exist at any time
// 2. draw(_:) for rendering instead of per-row SwiftUI Canvas
// 3. No @Observable cascading invalidation — only visible cells are updated

struct CommitTableView: NSViewRepresentable {
    let commits: [CommitInfo]
    let selectedCommitHash: String?
    let currentBranch: String
    let hasUnresolvedConflicts: Bool
    let scrollToHash: String?
    let rowHeight: CGFloat
    let columnWidth: CGFloat
    let avatarSize: CGFloat
    let graphAreaWidth: CGFloat
    let refsColumnWidth: CGFloat
    let onSelectCommit: (CommitInfo) -> Void
    let onConsumeScrollToHash: () -> Void
    let onContextAction: (CommitInfo, CommitContextAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = GraphScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed

        // Wire up graph horizontal scroll on the custom scroll view
        scrollView.graphHScroll = context.coordinator.graphHScroll
        scrollView.graphColumnX = 8 + refsColumnWidth
        scrollView.graphAreaWidth = graphAreaWidth
        scrollView.columnWidth = columnWidth

        let tableView = CommitNSTableView()
        tableView.style = .plain
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none // We draw our own selection

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("commit"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        // Context menu builder
        let coordinator = context.coordinator
        tableView.contextMenuBuilder = { [weak coordinator] row in
            coordinator?.buildContextMenu(for: row)
        }

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let oldCommitIDs = coordinator.commitIDs
        let newCommitIDs = commits.map(\.hash)
        let dataChanged = oldCommitIDs != newCommitIDs

        coordinator.commits = commits
        coordinator.selectedCommitHash = selectedCommitHash
        coordinator.currentBranch = currentBranch
        coordinator.hasUnresolvedConflicts = hasUnresolvedConflicts
        coordinator.onSelectCommit = onSelectCommit
        coordinator.onContextAction = onContextAction
        coordinator.columnWidth = columnWidth
        coordinator.avatarSize = avatarSize
        coordinator.graphAreaWidth = graphAreaWidth
        coordinator.refsColumnWidth = refsColumnWidth
        coordinator.commitIDs = newCommitIDs

        guard let tableView = coordinator.tableView else { return }

        if dataChanged {
            // Detect append vs. full change for lazy graph processor
            let isAppend = newCommitIDs.count > oldCommitIDs.count &&
                           !oldCommitIDs.isEmpty &&
                           oldCommitIDs == Array(newCommitIDs.prefix(oldCommitIDs.count))

            if isAppend {
                // Streaming append — keep existing graph state, just extend commits
                coordinator.lazyGraph.updateCommits(commits)
            } else {
                // Full change (reload, uncommitted entry added/removed, etc.)
                coordinator.lazyGraph.reset(commits: commits)
            }

            // Reset multi-selection when data changes (commits reloaded)
            if let hash = selectedCommitHash {
                coordinator.selectedRowHashes = [hash]
            } else {
                coordinator.selectedRowHashes = []
            }
            tableView.reloadData()
        } else {
            // Just refresh visible cells (selection change, etc.)
            tableView.enumerateAvailableRowViews { rowView, row in
                if let cellView = rowView.view(atColumn: 0) as? CommitRowCellView {
                    coordinator.configureCell(cellView, row: row)
                }
            }
        }

        // Update selection — only force single selection when NOT in a multi-select state
        if coordinator.selectedRowHashes.count <= 1 {
            if let selectedHash = selectedCommitHash {
                if let row = commits.firstIndex(where: { $0.hash == selectedHash }) {
                    if tableView.selectedRow != row {
                        coordinator.isUpdatingSelection = true
                        coordinator.selectedRowHashes = [selectedHash]
                        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                        coordinator.isUpdatingSelection = false
                    }
                }
            } else if !tableView.selectedRowIndexes.isEmpty {
                coordinator.isUpdatingSelection = true
                coordinator.selectedRowHashes = []
                tableView.deselectAll(nil)
                coordinator.isUpdatingSelection = false
            }
        }

        // Scroll to hash
        if let hash = scrollToHash, let row = commits.firstIndex(where: { $0.hash == hash }) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.allowsImplicitAnimation = true
                tableView.scrollRowToVisible(row)
            }
            // Center the row
            if let clipView = tableView.enclosingScrollView?.contentView {
                let rowRect = tableView.rect(ofRow: row)
                let visH = clipView.bounds.height
                let y = rowRect.midY - visH / 2
                clipView.setBoundsOrigin(NSPoint(x: 0, y: max(0, y)))
            }
            onConsumeScrollToHash()
        }

        // Update max columns for horizontal scroll (from lazy processor's computed entries)
        let maxCols = coordinator.lazyGraph.maxColumns
        coordinator.graphHScroll.maxColumns = maxCols
        let maxOff = max(0, CGFloat(maxCols + 1) * columnWidth - graphAreaWidth)
        if coordinator.graphHScroll.offset > maxOff {
            coordinator.graphHScroll.offset = maxOff
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        // No cleanup needed — GraphScrollView handles its own scroll logic
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var commits: [CommitInfo] = []
        var commitIDs: [String] = []
        let lazyGraph = LazyGraphProcessor()
        var selectedCommitHash: String?
        var currentBranch: String = ""
        var hasUnresolvedConflicts: Bool = false
        var onSelectCommit: ((CommitInfo) -> Void)?
        var onContextAction: ((CommitInfo, CommitContextAction) -> Void)?
        var rowHeight: CGFloat = 24
        var columnWidth: CGFloat = 18
        var avatarSize: CGFloat = 18
        var graphAreaWidth: CGFloat = 150
        var refsColumnWidth: CGFloat = 86

        fileprivate weak var tableView: CommitNSTableView?
        var isUpdatingSelection = false
        var selectedRowHashes: Set<String> = []
        let graphHScroll = GraphHScrollStateNS()

        init(parent: CommitTableView) {
            self.commits = parent.commits
            self.commitIDs = parent.commits.map(\.hash)
            self.selectedCommitHash = parent.selectedCommitHash
            self.currentBranch = parent.currentBranch
            self.hasUnresolvedConflicts = parent.hasUnresolvedConflicts
            self.onSelectCommit = parent.onSelectCommit
            self.onContextAction = parent.onContextAction
            self.rowHeight = parent.rowHeight
            self.columnWidth = parent.columnWidth
            self.avatarSize = parent.avatarSize
            self.graphAreaWidth = parent.graphAreaWidth
            self.refsColumnWidth = parent.refsColumnWidth
            if let hash = parent.selectedCommitHash {
                self.selectedRowHashes = [hash]
            }
            lazyGraph.reset(commits: parent.commits)
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            commits.count
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < commits.count else { return nil }

            // Lazy graph: ensure entries are computed through visible range + buffer
            let visibleRowCount = tableView.rows(
                in: tableView.enclosingScrollView?.contentView.bounds ?? tableView.bounds
            ).length
            let targetRow = min(commits.count, row + visibleRowCount + 200) - 1
            if targetRow >= lazyGraph.processedCount {
                lazyGraph.ensureProcessed(through: targetRow)
                // Update maxColumns for horizontal scroll
                graphHScroll.maxColumns = lazyGraph.maxColumns
            }

            let cellID = NSUserInterfaceItemIdentifier("CommitRow")
            let cell: CommitRowCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? CommitRowCellView {
                cell = reused
            } else {
                cell = CommitRowCellView()
                cell.identifier = cellID
            }

            configureCell(cell, row: row)
            return cell
        }

        func configureCell(_ cell: CommitRowCellView, row: Int) {
            guard row >= 0 && row < commits.count else { return }
            let commit = commits[row]
            cell.commit = commit
            cell.graphEntry = lazyGraph.entry(at: row)
            cell.isSelectedRow = selectedRowHashes.contains(commit.hash)
            cell.currentBranch = currentBranch
            cell.isRebaseConflict = commit.isUncommitted && hasUnresolvedConflicts
            cell.rowHeight = rowHeight
            cell.columnWidth = columnWidth
            cell.avatarSize = avatarSize
            cell.graphAreaWidth = graphAreaWidth
            cell.refsColumnWidth = refsColumnWidth
            cell.graphScrollOffset = graphHScroll.offset
            cell.isLastRow = row == commits.count - 1
            cell.needsDisplay = true
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rowHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            CommitTableRowView()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection else { return }
            guard let tableView = tableView else { return }
            let selectedRows = tableView.selectedRowIndexes

            // Update tracked selection hashes
            selectedRowHashes = Set(selectedRows.compactMap { row -> String? in
                guard row >= 0, row < commits.count else { return nil }
                return commits[row].hash
            })

            // Determine the "primary" selected row for commit detail display
            if let lastRow = selectedRows.last, lastRow >= 0, lastRow < commits.count {
                onSelectCommit?(commits[lastRow])
            }

            // Refresh visible rows for selection highlight
            tableView.enumerateAvailableRowViews { rowView, r in
                if let cellView = rowView.view(atColumn: 0) as? CommitRowCellView {
                    guard r >= 0, r < self.commits.count else { return }
                    cellView.isSelectedRow = self.selectedRowHashes.contains(self.commits[r].hash)
                    cellView.needsDisplay = true
                }
            }
        }

        // MARK: Context Menu

        func buildContextMenu(for row: Int) -> NSMenu? {
            guard row >= 0, row < commits.count else { return nil }
            let commit = commits[row]
            guard !commit.isUncommitted else { return nil }

            // Multi-selection: show squash menu
            if let tableView, tableView.selectedRowIndexes.count > 1 {
                return buildMultiSelectContextMenu()
            }

            let menu = NSMenu()
            let refs = commit.refs
            let isCurrentBranchHead = refs.contains(where: { $0.contains("HEAD") })
            let branchRef = refs.first(where: { !$0.contains("tag:") && !$0.contains("HEAD ->") })
            let otherBranchName = branchRef.map(RefBadgeHelper.displayName)
            let isOtherBranchHead = otherBranchName != nil && !isCurrentBranchHead

            // Merge
            if let otherBranchName, isOtherBranchHead {
                menu.addItem(menuItem("Merge \(otherBranchName) into \(currentBranch)") {
                    [weak self] in self?.onContextAction?(commit, .merge(otherBranchName))
                })
            }

            // Rebase
            if let otherBranchName, isOtherBranchHead {
                menu.addItem(menuItem("Rebase \(currentBranch) onto \(otherBranchName)") {
                    [weak self] in self?.onContextAction?(commit, .rebase(otherBranchName))
                })
            }

            if isOtherBranchHead || isCurrentBranchHead {
                menu.addItem(.separator())
            }

            // Checkout
            if isOtherBranchHead, let otherBranchName {
                let checkoutMenu = NSMenu()
                checkoutMenu.addItem(menuItem("Checkout \(otherBranchName)") {
                    [weak self] in self?.onContextAction?(commit, .checkoutBranch(otherBranchName))
                })
                checkoutMenu.addItem(menuItem("Checkout commit \(commit.shortHash)") {
                    [weak self] in self?.onContextAction?(commit, .checkoutCommit(commit.hash))
                })
                let checkoutItem = NSMenuItem(title: "Checkout", action: nil, keyEquivalent: "")
                checkoutItem.submenu = checkoutMenu
                menu.addItem(checkoutItem)
            } else if !isCurrentBranchHead {
                menu.addItem(menuItem("Checkout this commit") {
                    [weak self] in self?.onContextAction?(commit, .checkoutCommit(commit.hash))
                })
            }

            if isCurrentBranchHead {
                menu.addItem(menuItem("Set Upstream") {
                    [weak self] in self?.onContextAction?(commit, .setUpstream)
                })
            }

            menu.addItem(.separator())

            // Create branch
            menu.addItem(menuItem("Create branch here") {
                [weak self] in self?.onContextAction?(commit, .createBranch)
            })

            // Cherry pick
            if !isCurrentBranchHead {
                menu.addItem(menuItem("Cherry pick commit") {
                    [weak self] in self?.onContextAction?(commit, .cherryPick(commit.hash))
                })
            }

            // Reset submenu
            let resetMenu = NSMenu()
            resetMenu.addItem(menuItem("Soft – keep all changes staged") {
                [weak self] in self?.onContextAction?(commit, .resetSoft(commit.hash))
            })
            resetMenu.addItem(menuItem("Mixed – keep changes unstaged") {
                [weak self] in self?.onContextAction?(commit, .resetMixed(commit.hash))
            })
            resetMenu.addItem(menuItem("Hard – discard all changes") {
                [weak self] in self?.onContextAction?(commit, .resetHard(commit.hash))
            })
            let resetItem = NSMenuItem(title: "Reset \(currentBranch) to this commit", action: nil, keyEquivalent: "")
            resetItem.submenu = resetMenu
            menu.addItem(resetItem)

            // Edit message
            if isCurrentBranchHead {
                menu.addItem(menuItem("Edit commit message") {
                    [weak self] in self?.onContextAction?(commit, .editMessage)
                })
            }

            // Revert
            menu.addItem(menuItem("Revert commit") {
                [weak self] in self?.onContextAction?(commit, .revert(commit.hash))
            })

            menu.addItem(.separator())

            // Delete branch
            if isOtherBranchHead, let otherBranchName {
                let deleteItem = menuItem("Delete \(otherBranchName)") {
                    [weak self] in self?.onContextAction?(commit, .deleteBranch(otherBranchName))
                }
                deleteItem.attributedTitle = NSAttributedString(
                    string: "Delete \(otherBranchName)",
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
                menu.addItem(deleteItem)
            }

            // Copy SHA
            menu.addItem(menuItem("Copy commit SHA") {
                [weak self] in self?.onContextAction?(commit, .copySHA(commit.hash))
            })

            menu.addItem(.separator())

            // Compare
            menu.addItem(menuItem("Compare commit against working directory") {
                [weak self] in self?.onContextAction?(commit, .compareWithWorkingDir)
            })

            // Create tag
            menu.addItem(menuItem("Create tag here") {
                [weak self] in self?.onContextAction?(commit, .createTag)
            })

            return menu
        }

        private func buildMultiSelectContextMenu() -> NSMenu? {
            guard let tableView else { return nil }
            let selectedRows = tableView.selectedRowIndexes
            let selectedCommits = selectedRows.compactMap { row -> CommitInfo? in
                guard row >= 0, row < commits.count else { return nil }
                let c = commits[row]
                return c.isUncommitted ? nil : c
            }
            guard selectedCommits.count >= 2 else { return nil }

            let menu = NSMenu()

            // Squash commits
            let hashes = selectedCommits.map(\.hash)
            menu.addItem(menuItem("Squash \(selectedCommits.count) Commits") {
                [weak self] in
                guard let self else { return }
                // Use the first commit in the selection as the anchor
                self.onContextAction?(selectedCommits[0], .squashCommits(hashes))
            })

            menu.addItem(.separator())

            // Copy SHAs
            let shas = selectedCommits.map(\.shortHash).joined(separator: ", ")
            menu.addItem(menuItem("Copy SHAs") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shas, forType: .string)
            })

            return menu
        }

        private func menuItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, closure: action)
            return item
        }

        // MARK: Horizontal Scroll (handled by GraphScrollView)

        func updateMaxColumns() {
            // Called from updateNSView to keep the scroll state in sync
        }
    }
}

// MARK: - Custom NSScrollView with Graph Horizontal Scroll
//
// Overrides scrollWheel(with:) directly — much more reliable than NSEvent monitors,
// because the scroll view is the actual target of wheel events.

fileprivate final class GraphScrollView: NSScrollView {
    weak var graphHScroll: GraphHScrollStateNS?
    var graphColumnX: CGFloat = 94   // padding(8) + refsColumnWidth
    var graphAreaWidth: CGFloat = 150
    var columnWidth: CGFloat = 18

    override func scrollWheel(with event: NSEvent) {
        // Only handle horizontal graph scrolling when the mouse is within the Graph column
        if let state = graphHScroll {
            let locationInView = convert(event.locationInWindow, from: nil)
            let isInGraphColumn = locationInView.x >= graphColumnX
                && locationInView.x <= graphColumnX + graphAreaWidth

            if isInGraphColumn {
                var dx = event.scrollingDeltaX
                // For mouse wheel (non-precise), delta is in "lines" — scale to pixels
                if !event.hasPreciseScrollingDeltas {
                    dx *= columnWidth
                }
                // Shift + vertical scroll → horizontal scroll
                if event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) > abs(dx) {
                    dx = event.scrollingDeltaY
                    if !event.hasPreciseScrollingDeltas {
                        dx *= columnWidth
                    }
                }
                let maxOff = max(0, CGFloat(state.maxColumns + 1) * columnWidth - graphAreaWidth)
                if abs(dx) > 0.1 && maxOff > 0 {
                    state.offset = max(0, min(maxOff, state.offset - dx))
                    // Redraw visible rows with updated offset
                    if let tableView = documentView as? NSTableView {
                        tableView.enumerateAvailableRowViews { rowView, _ in
                            if let cellView = rowView.view(atColumn: 0) as? CommitRowCellView {
                                cellView.graphScrollOffset = state.offset
                                cellView.needsDisplay = true
                            }
                        }
                    }
                }
            }
        }
        // Always call super for vertical scrolling
        super.scrollWheel(with: event)
    }
}

// MARK: - Custom NSTableView with Context Menu

fileprivate final class CommitNSTableView: NSTableView {
    var contextMenuBuilder: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }

        // If right-clicking on an already-selected row in a multi-selection, keep selection
        if !isRowSelected(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        return contextMenuBuilder?(row)
    }
}

// MARK: - Closure-based NSMenuItem

private final class ClosureMenuItem: NSMenuItem {
    private var closure: (() -> Void)?

    convenience init(title: String, closure: @escaping () -> Void) {
        self.init(title: title, action: #selector(performAction), keyEquivalent: "")
        self.closure = closure
        self.target = self
    }

    @objc private func performAction() {
        closure?()
    }
}

// MARK: - Custom Row View (no default selection drawing)

private final class CommitTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set { }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // We handle selection drawing in the cell view
    }
}

// MARK: - Graph Horizontal Scroll State (plain class, NOT @Observable)

final class GraphHScrollStateNS {
    var offset: CGFloat = 0
    var maxColumns: Int = 1
}

// MARK: - Commit Row Cell View
//
// Draws the entire commit row (refs, graph, message) using AppKit drawing,
// similar to Xit's HistoryCellView. This is dramatically faster than SwiftUI's
// Canvas because:
// 1. Cell reuse — the same NSView is reconfigured for different rows
// 2. draw(_:) is called only for visible/dirty cells
// 3. No SwiftUI view diffing or body recomputation

final class CommitRowCellView: NSView {
    var commit: CommitInfo?
    var graphEntry: CommitGraphEntry?
    var isSelectedRow = false
    var currentBranch = ""
    var isRebaseConflict = false
    var rowHeight: CGFloat = 24
    var columnWidth: CGFloat = 18
    var avatarSize: CGFloat = 18
    var graphAreaWidth: CGFloat = 150
    var refsColumnWidth: CGFloat = 86
    var graphScrollOffset: CGFloat = 0
    var isLastRow = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let commit = commit else { return }
        let padding: CGFloat = 8

        if isRebaseConflict {
            drawConflictBanner()
            return
        }

        // Background
        if isSelectedRow {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.2).setFill()
            bounds.fill()
        } else if commit.isUncommitted {
            NSColor.orange.withAlphaComponent(0.04).setFill()
            bounds.fill()
        }

        // 1. Refs column
        let refsRect = NSRect(x: padding, y: 0, width: refsColumnWidth, height: bounds.height)
        NSGraphicsContext.current?.cgContext.saveGState()
        drawRefs(in: refsRect)
        NSGraphicsContext.current?.cgContext.restoreGState()

        // 2. Graph column
        let graphRect = NSRect(x: padding + refsColumnWidth, y: 0, width: graphAreaWidth, height: bounds.height)
        NSGraphicsContext.current?.cgContext.saveGState()
        drawGraph(in: graphRect)
        NSGraphicsContext.current?.cgContext.restoreGState()

        // 3. Message column
        let msgX = padding + refsColumnWidth + graphAreaWidth
        let msgRect = NSRect(x: msgX, y: 0, width: max(0, bounds.width - msgX - padding), height: bounds.height)
        drawMessage(in: msgRect)

        // Divider at bottom
        if !isLastRow {
            NSColor.separatorColor.withAlphaComponent(0.15).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    // MARK: - Conflict Banner

    private func drawConflictBanner() {
        NSColor.orange.withAlphaComponent(0.85).setFill()
        bounds.fill()

        let icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                           accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        let iconRect = NSRect(x: 10, y: (bounds.height - 13) / 2, width: 13, height: 13)
        icon?.draw(in: iconRect)

        let text = "A file conflict was found when attempting to merge into HEAD"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let textRect = NSRect(x: 28, y: (bounds.height - 14) / 2, width: bounds.width - 36, height: 14)
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    // MARK: - Refs Column

    /// Cached rect for the clickable "+N" pill (set during drawRefs, used in mouseDown)
    private var overflowPillRect: NSRect?

    private func drawRefs(in rect: NSRect) {
        guard let commit = commit, !commit.refs.isEmpty else {
            overflowPillRect = nil
            return
        }
        let clip = NSBezierPath(rect: rect)
        clip.addClip()

        var x = rect.minX
        let badgeHeight: CGFloat = 14
        let badgeY = (rect.height - badgeHeight) / 2

        if let firstRef = commit.refs.first {
            let (badgeW, _) = drawRefBadge(ref: firstRef, at: NSPoint(x: x, y: badgeY), height: badgeHeight)
            x += badgeW + 3
        }

        if commit.refs.count > 1 {
            let countStr = "+\(commit.refs.count - 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let size = countStr.size(withAttributes: attrs)
            let pillW = size.width + 8
            let pillRect = NSRect(x: x, y: badgeY, width: pillW, height: badgeHeight)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3)
            NSColor.controlBackgroundColor.setFill()
            pill.fill()
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            pill.lineWidth = 0.5
            pill.stroke()
            let textRect = NSRect(x: x + 4, y: badgeY + (badgeHeight - size.height) / 2,
                                  width: size.width, height: size.height)
            countStr.draw(in: textRect, withAttributes: attrs)

            // Cache the pill rect for click detection (offset by the padding used in draw)
            overflowPillRect = pillRect.offsetBy(dx: 8, dy: 0) // account for leading padding

            // Tooltip for all refs
            let allRefs = commit.refs.map { RefBadgeHelper.displayName($0) }.joined(separator: ", ")
            toolTip = allRefs
        } else {
            overflowPillRect = nil
        }
    }

    // MARK: - Click on Refs Overflow Pill

    override func mouseDown(with event: NSEvent) {
        guard let commit = commit, commit.refs.count > 1 else {
            super.mouseDown(with: event)
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        // Check if click is within the refs column area (badges + pill)
        let padding: CGFloat = 8
        let refsRect = NSRect(x: padding, y: 0, width: refsColumnWidth, height: bounds.height)
        if refsRect.contains(loc) {
            showRefsPopupMenu(for: commit, at: loc)
            return
        }
        super.mouseDown(with: event)
    }

    private func showRefsPopupMenu(for commit: CommitInfo, at point: NSPoint) {
        let menu = NSMenu()
        for ref in commit.refs {
            let displayName = RefBadgeHelper.menuDisplayName(ref)
            let icon = RefBadgeHelper.iconName(for: ref)
            let item = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
            let tintColor = RefBadgeHelper.badgeNSColor(for: ref)
            item.image = item.image?.tinted(with: tintColor)
            item.isEnabled = false // display-only menu items
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 8, y: bounds.height), in: self)
    }

    /// Draws a single ref badge and returns its size.
    @discardableResult
    private func drawRefBadge(ref: String, at origin: NSPoint, height: CGFloat) -> (CGFloat, CGFloat) {
        let name = RefBadgeHelper.displayName(ref)
        let color = RefBadgeHelper.badgeNSColor(for: ref)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: color
        ]
        let textSize = name.size(withAttributes: attrs)
        let badgeWidth = textSize.width + 8
        let badgeRect = NSRect(x: origin.x, y: origin.y, width: min(badgeWidth, refsColumnWidth - 8), height: height)

        // Background
        let path = NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.15).setFill()
        path.fill()
        color.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Text
        let textRect = NSRect(
            x: badgeRect.minX + 4,
            y: badgeRect.minY + (height - textSize.height) / 2,
            width: badgeRect.width - 8,
            height: textSize.height
        )
        name.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)

        return (badgeWidth, height)
    }

    // MARK: - Graph Column

    private func drawGraph(in rect: NSRect) {
                guard let entry = graphEntry else { return }
        let clip = NSBezierPath(rect: rect)
        clip.addClip()

        let h = rect.height
        let midY = rect.minY + h / 2
                let lineWidth: CGFloat = 1.5
        let scrollX = graphScrollOffset

        // Draw lines
                for line in entry.lines {
            let nsColor = (entry.isUncommitted || line.isUncommittedLink)
                ? NSColor.gray.withAlphaComponent(0.5)
                : GraphColorsNS.color(for: line.colorIndex)

            let fromX = rect.minX + CGFloat(line.from) * columnWidth - scrollX
            let toX = rect.minX + CGFloat(line.to) * columnWidth - scrollX
            let sourceY: CGFloat = line.upper ? rect.minY : rect.maxY

            let path = NSBezierPath()
            path.move(to: NSPoint(x: fromX, y: sourceY))
            path.line(to: NSPoint(x: toX, y: midY))
            path.lineCapStyle = .round

                    if line.from != line.to {
                NSColor.textBackgroundColor.setStroke()
                path.lineWidth = lineWidth + 2
                path.stroke()
            }
            nsColor.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }

        // Draw dot / avatar
        let dotX = rect.minX + CGFloat(entry.position) * columnWidth - scrollX
                if entry.isUncommitted {
                    let dotSize: CGFloat = 12
            let dotRect = NSRect(
                        x: dotX - dotSize / 2, y: midY - dotSize / 2,
                        width: dotSize, height: dotSize
                    )
            // Halo
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2)).fill()
            // Dashed circle
            let dashPath = NSBezierPath(ovalIn: dotRect)
            NSColor.gray.withAlphaComponent(0.5).setStroke()
            dashPath.lineWidth = 1.5
            let pattern: [CGFloat] = [3, 2]
            dashPath.setLineDash(pattern, count: 2, phase: 0)
            dashPath.stroke()
                } else {
            // Avatar circle
            let aSize = avatarSize
            let haloSize = aSize + 2
            let haloRect = NSRect(
                        x: dotX - haloSize / 2, y: midY - haloSize / 2,
                        width: haloSize, height: haloSize
                    )
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(ovalIn: haloRect).fill()

            let avatarRect = NSRect(
                x: dotX - aSize / 2, y: midY - aSize / 2,
                width: aSize, height: aSize
            )
            drawAvatar(in: avatarRect, name: commit?.authorName ?? "?",
                       borderColor: GraphColorsNS.color(for: entry.dotColorIndex))
        }
    }

    private func drawAvatar(in rect: NSRect, name: String, borderColor: NSColor) {
        let bgColor = avatarBackgroundColor(for: name)
        let path = NSBezierPath(ovalIn: rect)

        // Fill
        bgColor.setFill()
        path.fill()

        // Border
        borderColor.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Initial letter
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let initial = trimmed.isEmpty ? "?" : String(trimmed.first!).uppercased()
        let fontSize = rect.width * 0.42
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = initial.size(withAttributes: attrs)
        let textOrigin = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        initial.draw(at: textOrigin, withAttributes: attrs)
    }

    private func avatarBackgroundColor(for name: String) -> NSColor {
        var hash = 5381
        for char in name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(char.value)
        }
        let hue = CGFloat(abs(hash) % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.35, brightness: 0.45, alpha: 1.0)
    }

    // MARK: - Message Column

    private func drawMessage(in rect: NSRect) {
        guard let commit = commit else { return }
        let midY = rect.midY

        if commit.isUncommitted {
            // "Uncommitted Changes" label
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemOrange
            ]
            let title = "Uncommitted Changes"
            let titleSize = title.size(withAttributes: titleAttrs)
            title.draw(at: NSPoint(x: rect.minX + 6, y: midY - titleSize.height / 2), withAttributes: titleAttrs)

            // Detail
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let detailX = rect.minX + 6 + titleSize.width + 4
            let detailW = max(0, rect.maxX - detailX - 8)
            let detailRect = NSRect(x: detailX, y: midY - 6, width: detailW, height: 12)
            commit.message.draw(with: detailRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: detailAttrs)
        } else {
            // Commit message
            let msgAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
            let msgSize = commit.message.size(withAttributes: msgAttrs)

            // Date (right-aligned)
            var dateWidth: CGFloat = 0
            var dateStr: String?
            if let ds = BriefDateFormatter.format(commit.date) {
                dateStr = ds
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                let dSize = ds.size(withAttributes: dateAttrs)
                dateWidth = dSize.width + 12
                let dateOrigin = NSPoint(x: rect.maxX - dSize.width - 8, y: midY - dSize.height / 2)
                ds.draw(at: dateOrigin, withAttributes: dateAttrs)
            }

            let msgMaxW = max(0, rect.width - 14 - dateWidth)
            let msgRect = NSRect(x: rect.minX + 6, y: midY - msgSize.height / 2,
                                 width: msgMaxW, height: msgSize.height)
            commit.message.draw(with: msgRect,
                                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: msgAttrs)
        }
    }
}

// MARK: - Ref Badge Helper

enum RefBadgeHelper {
    static func iconName(for ref: String) -> String {
        if ref.contains("tag:") { return "tag.fill" }
        if ref.contains("/") && !ref.contains("HEAD") { return "cloud.fill" }
        return "arrow.triangle.branch"
    }

    static func displayName(_ ref: String) -> String {
        ref
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "origin/", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func menuDisplayName(_ ref: String) -> String {
        let stripped = ref.replacingOccurrences(of: "HEAD -> ", with: "")
        if ref.contains("tag:") {
            let tagName = ref.replacingOccurrences(of: "tag: ", with: "").trimmingCharacters(in: .whitespaces)
            return tagName
        } else if stripped.contains("/") {
            return stripped.trimmingCharacters(in: .whitespaces)
        } else {
            return stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    static func badgeNSColor(for ref: String) -> NSColor {
        if ref.contains("HEAD") {
            return .systemGreen
        } else if ref.contains("tag:") {
            return .systemYellow
        } else if ref.contains("/") {
            return .systemBlue
        } else {
            return .systemOrange
        }
    }
}

// MARK: - Brief Date Formatter

private enum BriefDateFormatter {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func format(_ raw: String) -> String? {
        guard let date = parser.date(from: raw) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return nil }

        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0

        if calendar.isDateInYesterday(date) { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "a week ago" }
        if days < 30 { return "\(days / 7) weeks ago" }
        if days < 60 { return "a month ago" }
        if days < 365 { return "\(days / 30) months ago" }
        return "\(days / 365)y ago"
    }
}

// MARK: - Graph Colors (NSColor version, gitx HSB palette)

private enum GraphColorsNS {
    static let colors: [NSColor] = (0..<8).map { i in
        NSColor(hue: CGFloat(i) / 8.0, saturation: 0.7, brightness: 0.8, alpha: 1.0)
    }

    static func color(for index: Int) -> NSColor {
        colors[abs(index) % colors.count]
    }
}

// MARK: - NSImage Tinting Helper

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: img.size)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

// MARK: - Conditional View Modifier (kept for other uses)

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

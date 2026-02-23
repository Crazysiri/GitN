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

    // Graph horizontal scroll state (reference type for NSEvent closure)
    @State private var graphHScroll = GraphHScrollState()

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
                scrollContent
            }
        }
        .background(Color(.textBackgroundColor))
        .onAppear {
            updateMaxColumns()
            installScrollWheelMonitor()
        }
        .onDisappear { removeScrollWheelMonitor() }
        .onChange(of: viewModel.graphEntries.count) { _, _ in
            updateMaxColumns()
        }
        .sheet(isPresented: $showCreateTagSheet) { createTagSheet }
        .sheet(isPresented: $showCreateBranchSheet) { createBranchAtSheet }
        .sheet(isPresented: $showEditMessageSheet) { editMessageSheet }
        .sheet(isPresented: $showSetUpstreamSheet) { setUpstreamSheet }
    }

    // MARK: - Horizontal Scroll

    /// Recompute the maximum column count from graph entries and clamp offset.
    private func updateMaxColumns() {
        let maxCols = viewModel.graphEntries.values.map(\.numColumns).max() ?? 1
        graphHScroll.maxColumns = maxCols
        let maxOff = max(0, CGFloat(maxCols + 1) * columnWidth - graphAreaWidth)
        graphHScroll.offset = min(graphHScroll.offset, maxOff)
    }

    private func installScrollWheelMonitor() {
        let state = graphHScroll
        let colWidth = columnWidth
        let areaWidth = graphAreaWidth
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard state.isHovering else { return event }
            var dx = event.scrollingDeltaX
            // Shift + vertical scroll → horizontal scroll (for mice without horizontal wheel)
            if event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) > abs(dx) {
                dx = event.scrollingDeltaY
            }
            let maxOff = max(0, CGFloat(state.maxColumns + 1) * colWidth - areaWidth)
            if abs(dx) > 0.1 && maxOff > 0 {
                state.offset = max(0, min(maxOff, state.offset - dx))
            }
            return event
        }
    }

    private func removeScrollWheelMonitor() {
        if let monitor = graphHScroll.monitor {
            NSEvent.removeMonitor(monitor)
            graphHScroll.monitor = nil
        }
    }

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

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                        graphRow(commit: commit, index: index)
                    }
                }
            }
            .onChange(of: viewModel.scrollToCommitHash) { _, hash in
                guard let hash else { return }
                withAnimation {
                    proxy.scrollTo(hash, anchor: .center)
                }
                viewModel.scrollToCommitHash = nil
            }
        }
    }

    @ViewBuilder
    private func graphRow(commit: CommitInfo, index: Int) -> some View {
        let row = GraphRowView(
            commit: commit,
            graphEntry: viewModel.graphEntries[commit.hash],
            isSelected: viewModel.selectedCommit?.hash == commit.hash,
            rowHeight: rowHeight,
            columnWidth: columnWidth,
            avatarSize: avatarSize,
            graphAreaWidth: graphAreaWidth,
            refsColumnWidth: refsColumnWidth,
            currentBranch: viewModel.currentBranch,
            isRebaseConflict: commit.isUncommitted && viewModel.isRebaseConflict,
            graphHScroll: graphHScroll
        )

        row
            .id(commit.hash)
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await viewModel.selectCommit(commit) }
            }
            .if(!commit.isUncommitted) { view in
                view.contextMenu {
                    commitContextMenu(for: commit)
                        .font(.system(size: 11, weight: .medium))
                }
            }

        if index < viewModel.commits.count - 1 {
            Divider().opacity(0.15)
        }
    }
    // MARK: - Context Menu

    @ViewBuilder
    private func commitContextMenu(for commit: CommitInfo) -> some View {
        let refs = commit.refs
        let isCurrentBranchHead = refs.contains(where: { $0.contains("HEAD") })
        let branchRef = refs.first(where: { !$0.contains("tag:") && !$0.contains("HEAD ->") })
        let _ = refs.first(where: { $0.contains("HEAD ->") })
        let otherBranchName = branchRef.map(RefBadge.displayName)
        let isOtherBranchHead = otherBranchName != nil && !isCurrentBranchHead
        let _ = refs.contains(where: { $0.contains("origin/") })

        // Merge
        if let otherBranchName, isOtherBranchHead {
            Button("Merge \(otherBranchName) into \(viewModel.currentBranch)") {
                Task { await viewModel.performMerge(otherBranchName) }
            }
        }

        // Rebase
        if let otherBranchName, isOtherBranchHead {
            Button("Rebase \(viewModel.currentBranch) onto \(otherBranchName)") {
                Task { await viewModel.performRebase(onto: otherBranchName) }
            }
        }

        if isOtherBranchHead || isCurrentBranchHead {
            Divider()
        }

        // Checkout
        if isOtherBranchHead, let otherBranchName {
            Menu("Checkout") {
                Button("Checkout \(otherBranchName)") {
                    Task { await viewModel.performCheckoutBranch(otherBranchName) }
                }
                Button("Checkout commit \(commit.shortHash)") {
                    Task { await viewModel.performCheckoutCommit(commit.hash) }
                }
            }
        } else if !isCurrentBranchHead {
            Button("Checkout this commit") {
                Task { await viewModel.performCheckoutCommit(commit.hash) }
            }
        }

        if isCurrentBranchHead {
            // Set Upstream
            Button("Set Upstream") {
                contextCommit = commit
                upstreamBranch = viewModel.currentBranch
                upstreamRemote = "origin"
                showSetUpstreamSheet = true
            }
        }

        Divider()

        // Create branch here
        Button("Create branch here") {
            contextCommit = commit
            newBranchNameAtCommit = ""
            showCreateBranchSheet = true
        }

        // Cherry pick (not on current branch head)
        if !isCurrentBranchHead {
            Button("Cherry pick commit") {
                Task { await viewModel.performCherryPick(commit.hash) }
            }
        }

        // Reset
        Menu("Reset \(viewModel.currentBranch) to this commit") {
            Button("Soft – keep all changes staged") {
                Task { await viewModel.performReset(commit.hash, mode: .soft) }
            }
            Button("Mixed – keep changes unstaged") {
                Task { await viewModel.performReset(commit.hash, mode: .mixed) }
            }
            Button("Hard – discard all changes") {
                Task { await viewModel.performReset(commit.hash, mode: .hard) }
            }
        }

        // Edit commit message (only HEAD)
        if isCurrentBranchHead {
            Button("Edit commit message") {
                contextCommit = commit
                editedMessage = commit.message
                showEditMessageSheet = true
            }
        }

        // Revert
        Button("Revert commit") {
            Task { await viewModel.performRevert(commit.hash) }
        }

        Divider()

        // Delete branch
        if isOtherBranchHead, let otherBranchName {
            Button("Delete \(otherBranchName)", role: .destructive) {
                Task { await viewModel.performDeleteBranch(otherBranchName) }
            }
        }

        // Copy
        Button("Copy commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        }

        Divider()

        // Compare
        Button("Compare commit against working directory") {
            Task { await viewModel.performCompareWithWorkingDirectory(commit) }
        }

        // Create tag
        Button("Create tag here") {
            contextCommit = commit
            tagName = ""
            showCreateTagSheet = true
        }
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

// MARK: - Conditional View Modifier

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

// MARK: - Row

struct GraphRowView: View {
    let commit: CommitInfo
    let graphEntry: CommitGraphEntry?
    let isSelected: Bool
    let rowHeight: CGFloat
    let columnWidth: CGFloat
    let avatarSize: CGFloat
    let graphAreaWidth: CGFloat
    let refsColumnWidth: CGFloat
    let currentBranch: String
    var isRebaseConflict: Bool = false
    var graphHScroll: GraphHScrollState?

    var body: some View {
        if isRebaseConflict {
            conflictBannerRow
        } else {
            HStack(spacing: 0) {
                refsColumn
                    .frame(width: refsColumnWidth, height: rowHeight)

                graphColumn
                    .frame(width: graphAreaWidth, height: rowHeight)
                    .onHover { graphHScroll?.isHovering = $0 }

                messageColumn
                    .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .background(rowBackground)
        }
    }

    private var conflictBannerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 11))
            Text("A file conflict was found when attempting to merge into HEAD")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: rowHeight)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.85))
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color(.selectedContentBackgroundColor).opacity(0.2)
            } else if commit.isUncommitted {
                Color.orange.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Refs Column

    private var refsColumn: some View {
        HStack(spacing: 3) {
            if let firstRef = commit.refs.first {
                RefBadge(refName: firstRef, currentBranch: currentBranch)
            }
            if commit.refs.count > 1 {
                Menu {
                    ForEach(commit.refs.dropFirst(), id: \.self) { ref in
                        Button {
                        } label: {
                            Label {
                                Text(RefBadge.menuDisplayName(ref))
                            } icon: {
                                Image(systemName: RefBadge.iconName(for: ref))
                            }
                        }
                    }
                } label: {
                    Text("+\(commit.refs.count - 1)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
                                )
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .clipped()
    }

    // MARK: - Graph Column

    /// Canvas draws the lane lines + a background halo behind the avatar.
    /// The avatar itself is a SwiftUI overlay so `.help()` works for tooltip.
    /// Content is offset by the shared scroll state and clipped for horizontal scrolling.
    private var graphColumn: some View {
        let scrollX = graphHScroll?.offset ?? 0
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                guard let entry = graphEntry else { return }
                let h = size.height
                let midY = h / 2
                let lineWidth: CGFloat = 1.5

                for line in entry.lines {
                    let color = (entry.isUncommitted || line.isUncommittedLink)
                        ? Color.gray.opacity(0.5)
                        : GraphColors.color(for: line.colorIndex)

                    let fromX = CGFloat(line.from) * columnWidth - scrollX
                    let toX = CGFloat(line.to) * columnWidth - scrollX
                    let sourceY: CGFloat = line.upper ? 0 : h

                    var path = Path()
                    path.move(to: CGPoint(x: fromX, y: sourceY))
                    path.addLine(to: CGPoint(x: toX, y: midY))

                    if line.from != line.to {
                        context.stroke(
                            path, with: .color(Color(.textBackgroundColor)),
                            style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round)
                        )
                    }
                    context.stroke(
                        path, with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                }

                let dotX = CGFloat(entry.position) * columnWidth - scrollX
                if entry.isUncommitted {
                    let dotSize: CGFloat = 12
                    let dotRect = CGRect(
                        x: dotX - dotSize / 2, y: midY - dotSize / 2,
                        width: dotSize, height: dotSize
                    )
                    context.fill(
                        Path(ellipseIn: dotRect.insetBy(dx: -2, dy: -2)),
                        with: .color(Color(.textBackgroundColor))
                    )
                    context.stroke(
                        Path(ellipseIn: dotRect),
                        with: .color(.gray.opacity(0.5)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
                } else {
                    let haloSize = avatarSize + 2
                    let haloRect = CGRect(
                        x: dotX - haloSize / 2, y: midY - haloSize / 2,
                        width: haloSize, height: haloSize
                    )
                    context.fill(
                        Path(ellipseIn: haloRect),
                        with: .color(Color(.textBackgroundColor))
                    )
                }
            }

            if let entry = graphEntry, !commit.isUncommitted {
                CommitAvatar(
                    name: commit.authorName,
                    size: avatarSize,
                    borderColor: GraphColors.color(for: entry.dotColorIndex)
                )
                .offset(
                    x: CGFloat(entry.position) * columnWidth - avatarSize / 2 - scrollX,
                    y: (rowHeight - avatarSize) / 2
                )
                .help(commit.authorName)
            }
        }
        .clipped()
    }

    // MARK: - Message Column

    private var messageColumn: some View {
        HStack(spacing: 4) {
            if commit.isUncommitted {
                Text("Uncommitted Changes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Text(commit.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let dateStr = BriefDateFormatter.format(commit.date) {
                    Text(dateStr)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }
}

// MARK: - Commit Avatar

struct CommitAvatar: View {
    let name: String
    let size: CGFloat
    let borderColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(borderColor, lineWidth: 2))
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// Deterministic color based on the author name.
    private var backgroundColor: Color {
        var hash = 5381
        for char in name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(char.value)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.45)
    }
}

// MARK: - Ref Badge

struct RefBadge: View {
    let refName: String
    let currentBranch: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: Self.iconName(for: refName))
                .font(.system(size: 7))
            Text(cleanName)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(badgeColor.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(badgeColor.opacity(0.4), lineWidth: 0.5)
                )
        )
        .foregroundStyle(badgeColor)
    }

    /// Icon name based on ref type: tag, remote branch, or local branch
    static func iconName(for ref: String) -> String {
        if ref.contains("tag:") { return "tag.fill" }
        if ref.contains("/") && !ref.contains("HEAD") { return "cloud.fill" }
        return "arrow.triangle.branch"
    }

    /// Display name for the main badge (strips HEAD prefix only, keeps origin/ and tag:)
    static func displayName(_ ref: String) -> String {
        ref
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "origin/", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Display name for the dropdown menu — keeps remote prefix and adds type label
    static func menuDisplayName(_ ref: String) -> String {
        let stripped = ref.replacingOccurrences(of: "HEAD -> ", with: "")
        if ref.contains("tag:") {
            let tagName = ref.replacingOccurrences(of: "tag: ", with: "").trimmingCharacters(in: .whitespaces)
            return "🏷 \(tagName)"
        } else if stripped.contains("/") {
            // Remote branch: keep full name like "origin/main"
            return stripped.trimmingCharacters(in: .whitespaces)
        } else {
            // Local branch
            return stripped.trimmingCharacters(in: .whitespaces)
        }
    }

    private var cleanName: String {
        Self.displayName(refName)
    }

    private var badgeColor: Color {
        if refName.contains("HEAD") {
            return .green
        } else if refName.contains("tag:") {
            return .yellow
        } else if refName.contains("/") {
            return .blue
        } else {
            return .orange
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

    /// Returns `nil` for today's commits; brief relative string otherwise.
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

// MARK: - Graph Horizontal Scroll State

/// Observable reference type so the NSEvent monitor closure can read/write
/// the latest values via a captured reference (avoiding struct-copy issues).
@Observable
final class GraphHScrollState {
    var offset: CGFloat = 0
    var maxColumns: Int = 1
    var isHovering: Bool = false
    var monitor: Any?
}

// MARK: - Colors (gitx HSB palette)

enum GraphColors {
    /// 8 evenly-spaced hues with S=0.7, B=0.8, matching gitx's laneColors.
    static let colors: [Color] = (0..<8).map { i in
        Color(hue: Double(i) / 8.0, saturation: 0.7, brightness: 0.8)
    }

    static func color(for index: Int) -> Color {
        colors[abs(index) % colors.count]
    }
}

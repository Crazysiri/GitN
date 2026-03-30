import SwiftUI

struct DetailPanelView: View {
    enum StageDropArea: String {
        case staged
        case unstaged
    }

    private enum LayoutDefaults {
        static let uncommittedInputHeight: CGFloat = 240
        static let uncommittedInputMinHeight: CGFloat = 170
        static let splitHandleHeight: CGFloat = 12

        enum CommittedMessage {
            static let readOnlyDefaultHeight: CGFloat = 100
            static let editingDefaultHeight: CGFloat = 94
            static let readOnlyMinHeight: CGFloat = 84
            static let editingMinHeight: CGFloat = 116
            static let readOnlyContentMinHeight: CGFloat = 84
            static let editingDescriptionMinHeight: CGFloat = 56
        }
    }

    let viewModel: RepoViewModel

    private enum FocusTarget: Hashable {
        case fileList
    }

    @State private var isEditingMessage = false
    @State private var editedTitle = ""
    @State private var editedDescription = ""
    @State private var originalTitle = ""
    @State private var originalDescription = ""
    @State private var fullCommitMessage = ""
    @State private var isHoveringMessage = false
    @State private var discardConfirmPaths: [String] = []
    @State private var showDiscardConfirm = false
    @State private var committedHeaderHeight: CGFloat = LayoutDefaults.CommittedMessage.readOnlyDefaultHeight
    @State private var measuredCommittedMetadataHeight: CGFloat = 0
    @State private var uncommittedInputHeight: CGFloat = LayoutDefaults.uncommittedInputHeight
    @State private var hoveredReflogLinkID: String?

    // MARK: - Rubber-band selection (unstaged area)
    @State private var isRubberBanding = false
    @State private var rubberBandOrigin: CGPoint = .zero
    @State private var rubberBandCurrent: CGPoint = .zero
    @State private var unstagedRowFrames: [String: CGRect] = [:]
    @State private var unstagedSectionMinY: CGFloat?
    @State private var suppressNextFileListAutoScroll = false
    @State private var isResizingPane = false
    @State private var splitDragStartHeight: CGFloat?
    @FocusState private var focusedTarget: FocusTarget?

    private var supportsUnstagedRubberBandSelection: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion >= 16 { return true }
        if version.majorVersion == 15 {
            return version.minorVersion < 6
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isInConflict, let cType = viewModel.conflictType {
                conflictPanel(cType)
            } else if viewModel.isCompareMode, let commit = viewModel.selectedCommit {
                compareHeader(commit)
                Divider()
                compareFileList
            } else if let stash = viewModel.selectedStash {
                stashInfoHeader(stash)
                Divider()
                diffFileList
            } else if let commit = viewModel.selectedCommit {
                if commit.isUncommitted {
                    uncommittedDetailLayout
                } else {
                    committedDetailLayout(commit)
                }
            } else {
                emptyDetail
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .onChange(of: viewModel.selectedCommit?.hash) { oldValue, newValue in
            // Reset editing state when selecting a different commit (or switching to uncommitted)
            isEditingMessage = false
            editedTitle = ""
            editedDescription = ""
            originalTitle = ""
            originalDescription = ""
            fullCommitMessage = ""
            isHoveringMessage = false
            if let commit = viewModel.selectedCommit {
                if commit.isUncommitted {
                    uncommittedInputHeight = LayoutDefaults.uncommittedInputHeight
                } else {
                    committedHeaderHeight = LayoutDefaults.CommittedMessage.readOnlyDefaultHeight
                }
            }
            // Load full commit message when commit changes
            if let hash = newValue, let commit = viewModel.selectedCommit, !commit.isUncommitted {
                Task {
                    let fullMessage = await viewModel.getFullCommitMessage(hash: hash)
                    await MainActor.run {
                        fullCommitMessage = fullMessage
                    }
                }
            }
        }
        .onChange(of: viewModel.selectedStash?.id) { _, _ in
            // Reset editing state when selecting a different stash
            isEditingMessage = false
            editedTitle = ""
            editedDescription = ""
            originalTitle = ""
            originalDescription = ""
            isHoveringMessage = false
        }
        .onChange(of: isEditingMessage) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue {
                committedHeaderHeight = max(committedHeaderHeight, LayoutDefaults.CommittedMessage.editingDefaultHeight)
            } else {
                committedHeaderHeight = max(committedHeaderHeight, LayoutDefaults.CommittedMessage.readOnlyDefaultHeight)
            }
        }
        .alert(
            "Discard Changes",
            isPresented: $showDiscardConfirm
        ) {
            Button("Discard", role: .destructive) {
                let paths = discardConfirmPaths
                discardConfirmPaths = []
                Task { await viewModel.discardChanges(paths: paths) }
            }
            Button("Cancel", role: .cancel) {
                discardConfirmPaths = []
            }
        } message: {
            if discardConfirmPaths.count == 1 {
                Text("Are you sure you want to discard changes to \"\(discardConfirmPaths.first ?? "")\"? This cannot be undone.")
            } else {
                Text("Are you sure you want to discard changes to \(discardConfirmPaths.count) files? This cannot be undone.")
            }
        }
    }

    /// Only commits on the current branch (reachable from HEAD) can be edited
    private var isEditableCommit: Bool {
        guard let commit = viewModel.selectedCommit, !commit.isUncommitted else { return false }
        return viewModel.currentBranchHashes.contains(commit.hash)
    }

    /// Load full commit message when needed
    private func loadFullMessageIfNeeded(commit: CommitInfo) {
        if fullCommitMessage.isEmpty && !commit.isUncommitted {
            Task {
                let message = await viewModel.getFullCommitMessage(hash: commit.hash)
                await MainActor.run {
                    fullCommitMessage = message
                }
            }
        }
    }

    private var committedHeaderMinHeight: CGFloat {
        isEditingMessage
            ? LayoutDefaults.CommittedMessage.editingMinHeight
            : LayoutDefaults.CommittedMessage.readOnlyMinHeight
    }

    private var uncommittedInputMinHeight: CGFloat {
        LayoutDefaults.uncommittedInputMinHeight
    }

    private var splitHandleHeight: CGFloat {
        LayoutDefaults.splitHandleHeight
    }

    private func committedDetailLayout(_ commit: CommitInfo) -> some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let staticTopHeight: CGFloat = 42
            let metadataHeight = max(measuredCommittedMetadataHeight, 56)
            let maxHeaderHeight = max(committedHeaderMinHeight, totalHeight - metadataHeight - splitHandleHeight - 80 - staticTopHeight)
            let headerHeight = min(max(committedHeaderHeight, committedHeaderMinHeight), maxHeaderHeight)
            let bottomHeight = max(60, totalHeight - staticTopHeight - headerHeight - splitHandleHeight - metadataHeight)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    commitTitleBar(commit)
                    commitMessageSection(commit)
                        .frame(height: headerHeight, alignment: .top)

                    splitResizeHandle(
                        height: $committedHeaderHeight,
                        range: committedHeaderMinHeight...maxHeaderHeight,
                        axis: .top,
                        totalHeight: totalHeight
                    )

                    commitMetadataSection(commit)
                }
                .padding(10)

                Divider()

                diffFileList
                    .frame(height: bottomHeight, alignment: .top)
                    .clipped()
            }
            .coordinateSpace(name: "detailCommittedSplit")
        }
    }

    private var uncommittedDetailLayout: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let maxInputHeight = max(uncommittedInputMinHeight, totalHeight - 80)
            let inputHeight = min(max(uncommittedInputHeight, uncommittedInputMinHeight), maxInputHeight)
            let listHeight = max(60, totalHeight - inputHeight - splitHandleHeight)

            VStack(spacing: 0) {
                diffFileList
                    .frame(height: listHeight, alignment: .top)
                    .clipped()

                splitResizeHandle(
                    height: $uncommittedInputHeight,
                    range: uncommittedInputMinHeight...maxInputHeight,
                    axis: .bottom,
                    totalHeight: totalHeight
                )

                commitInputArea
                    .frame(height: inputHeight, alignment: .top)
                    .clipped()
            }
            .coordinateSpace(name: "detailUncommittedSplit")
        }
    }

    private func commitTitleBar(_ commit: CommitInfo) -> some View {
        let _ = loadFullMessageIfNeeded(commit: commit)
        return HStack(spacing: 6) {
            Text("commit:")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(commit.shortHash)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Spacer()
            if isEditableCommit && isEditingMessage {
                Button(action: {
                    Task {
                        if let result = await viewModel.generateAICommitMessageForCommit(hash: commit.hash) {
                            editedTitle = result.title
                            editedDescription = result.description
                        }
                    }
                }) {
                    HStack(spacing: 3) {
                        if viewModel.isGeneratingAICommit {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                        }
                        Text("AI")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.purple.opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGeneratingAICommit)
                .hoverTooltip("Regenerate commit message with AI")
            }
        }
    }

    @ViewBuilder
    private func commitMessageSection(_ commit: CommitInfo) -> some View {
        if isEditingMessage {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    CommitTitleField(
                        text: $editedTitle,
                        placeholder: "Title",
                        font: .systemFont(ofSize: 11, weight: .semibold)
                    )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)

                    Text("\(72 - editedTitle.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(editedTitle.count > 72 ? .red : .secondary)
                        .padding(.trailing, 6)
                }
                .frame(height: 24)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                )

                commitDescriptionField(
                    text: Binding(
                        get: { editedDescription },
                        set: { editedDescription = $0 }
                    ),
                    placeholder: "Description (optional)",
                    cornerRadius: 4
                )

                HStack(spacing: 8) {
                    Button(action: {
                        let title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        let description = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        let fullMessage = description.isEmpty ? title : title + "\n\n" + description
                        isEditingMessage = false
                        Task { await viewModel.performEditCommitMessage(hash: commit.hash, newMessage: fullMessage) }
                    }) {
                        Text("Update Message")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(
                        editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (editedTitle == originalTitle && editedDescription == originalDescription)
                    )

                    Button(action: {
                        isEditingMessage = false
                        editedTitle = originalTitle
                        editedDescription = originalDescription
                    }) {
                        Text("Cancel")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                Text(fullCommitMessage.isEmpty ? commit.message : fullCommitMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: LayoutDefaults.CommittedMessage.readOnlyContentMinHeight,
                maxHeight: .infinity,
                alignment: .top
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isHoveringMessage && isEditableCommit
                            ? Color.accentColor.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .onHover { hovering in
                isHoveringMessage = hovering
            }
            .onTapGesture {
                guard isEditableCommit else { return }
                let message = fullCommitMessage.isEmpty ? commit.message : fullCommitMessage
                let lines = message.components(separatedBy: .newlines)
                let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let description = lines.dropFirst()
                    .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                originalTitle = title
                originalDescription = description
                editedTitle = title
                editedDescription = description
                isEditingMessage = true
            }
            .hoverTooltip("Click to edit commit message", isEnabled: isEditableCommit)
        }
    }

    private func commitMetadataSection(_ commit: CommitInfo) -> some View {
        let reflogEntries = viewModel.reflogEntries(for: commit.hash)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(avatarColor(for: commit.authorName))
                        .frame(width: 28, height: 28)
                    Text(avatarInitial(commit.authorName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.authorName)
                        .font(.system(size: 11, weight: .medium))
                    Text("authored \(formattedDate(commit.date))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)

                Spacer()

                if !commit.parentHashes.isEmpty {
                    Text("parent: \(commit.parentHashes.map { String($0.prefix(7)) }.joined(separator: ", "))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.showReflogOverlay, !reflogEntries.isEmpty {
                commitReflogSection(reflogEntries)
            }

            if commit.isMerge {
                HStack(spacing: 4) {
                    Text("Merge")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.2))
                        )
                        .foregroundStyle(.purple)
                    Spacer()
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CommittedMetadataHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(CommittedMetadataHeightKey.self) { height in
            guard height > 0 else { return }
            measuredCommittedMetadataHeight = height
        }
    }
    
    private func stashInfoHeader(_ stash: StashInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("stash:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(stash.index)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
            }
            
            if !stash.message.isEmpty {
                Text(stash.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func commitReflogSection(_ entries: [ReflogEntryInfo]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Reflog")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.selectedReflogRef == "HEAD" ? "HEAD" : RefBadgeHelper.displayName(viewModel.selectedReflogRef))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            ForEach(entries.prefix(4)) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.kind.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: ReflogBadgeHelper.badgeColor(for: entry.kind)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: ReflogBadgeHelper.badgeColor(for: entry.kind)).opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                        reflogCommitLinkRow(entry)
                        if !entry.date.isEmpty {
                            Text(entry.date)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func reflogCommitLinkRow(_ entry: ReflogEntryInfo) -> some View {
        HStack(spacing: 4) {
            reflogCommitLink(
                hash: entry.oldOID,
                shortHash: entry.shortOldOID,
                isPrimary: false
            )

            Text("->")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)

            reflogCommitLink(
                hash: entry.newOID,
                shortHash: entry.shortNewOID,
                isPrimary: true
            )

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func reflogCommitLink(hash: String?, shortHash: String, isPrimary: Bool) -> some View {
        let canNavigate = viewModel.canNavigateToCommit(hash: hash)
        let linkID = "\(isPrimary ? "new" : "old"):\(hash ?? shortHash)"
        let isHovered = hoveredReflogLinkID == linkID

        if let hash, canNavigate {
            Button {
                Task { await viewModel.navigateToCommit(hash: hash) }
            } label: {
                Text(shortHash)
                    .font(.system(size: 9, weight: isPrimary ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(reflogLinkColor(isPrimary: isPrimary, isHovered: isHovered))
                    .underline(isHovered)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(reflogLinkBackgroundColor(isPrimary: isPrimary, isHovered: isHovered))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 3))
            .hoverTooltip("Jump to \(shortHash)")
            .onHover { hovering in
                hoveredReflogLinkID = hovering ? linkID : nil
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            Text(shortHash)
                .font(.system(size: 9, weight: isPrimary ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func reflogLinkColor(isPrimary: Bool, isHovered: Bool) -> Color {
        if isPrimary {
            return isHovered ? Color.accentColor : Color.accentColor.opacity(0.92)
        }
        return isHovered ? .primary : .secondary
    }

    private func reflogLinkBackgroundColor(isPrimary: Bool, isHovered: Bool) -> Color {
        guard isHovered else { return .clear }
        if isPrimary {
            return Color.accentColor.opacity(0.12)
        }
        return Color.secondary.opacity(0.12)
    }

    // MARK: - Avatar Helpers

    private func avatarInitial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.first!).uppercased()
    }

    private func avatarColor(for name: String) -> Color {
        var hash = 5381
        for char in name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(char.value)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.35, brightness: 0.45)
    }

    // MARK: - Compare mode

    private func compareHeader(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.purple)
                Text("Comparing commit against working directory")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Done") {
                    viewModel.exitCompareMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.shortHash)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.purple.opacity(0.15))
                        )
                    Text(commit.message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text("Working Directory")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.15))
                    )
            }

            Text("\(viewModel.diffFiles.count) file(s) changed")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var compareFileList: some View {
        fileListContainer(maxHeight: .infinity) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.diffFiles) { file in
                            DiffFileRow(
                                file: file,
                                isSelected: viewModel.selectedDiffFile?.path == file.path
                            )
                            .id(file.path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedTarget = .fileList
                                suppressNextFileListAutoScroll = true
                                Task {
                                    await viewModel.selectCompareFile(file)
                                    await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
                                }
                            }
                            .contextMenu { commitFileContextMenu(file) }
                        }
                    }
                }
                .onChange(of: viewModel.selectedDiffFile?.path) { _, path in
                    handleFileListSelectionChange(path, with: proxy)
                }
            }
        }
    }

    // MARK: - File list

    @ViewBuilder
    private var diffFileList: some View {
        if viewModel.selectedCommit?.isUncommitted == true {
            stagingFileList
        } else {
            plainFileList
        }
    }

    private var plainFileList: some View {
        fileListContainer(maxHeight: .infinity) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.diffFiles) { file in
                            DiffFileRow(
                                file: file,
                                isSelected: viewModel.selectedDiffFile?.path == file.path
                            )
                            .id(file.path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedTarget = .fileList
                                suppressNextFileListAutoScroll = true
                                Task {
                                    await viewModel.selectDiffFile(file)
                                    await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
                                }
                            }
                            .contextMenu { commitFileContextMenu(file) }
                        }
                    }
                }
                .onChange(of: viewModel.selectedDiffFile?.path) { _, path in
                    handleFileListSelectionChange(path, with: proxy)
                }
            }
        }
    }

    // MARK: - Commit File Context Menu

    @ViewBuilder
    private func commitFileContextMenu(_ file: DiffFile) -> some View {
        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path, context: .committed) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths([file.path]) }

        if let commit = viewModel.selectedCommit {
            Button("Copy commit diff") {
                Task {
                    do {
                        let diff = try await viewModel.getFileDiff(hash: commit.hash, path: file.path)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diff, forType: .string)
                        viewModel.showToast(title: "Diff copied", detail: file.path, style: .success)
                    } catch {
                        viewModel.showToast(title: "Failed to copy diff", detail: error.localizedDescription, style: .error)
                    }
                }
            }
        }

        Divider()

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }

        if file.path.isPreviewableFile {
            Button("Preview") {
                Task { await viewModel.openFilePreview(path: file.path, context: .committed) }
            }
        }
    }

    // MARK: - Staged / Unstaged split list

    private func selectedOrSingle(_ path: String) -> [String] {
        if viewModel.selectedFilePaths.contains(path) && viewModel.selectedFilePaths.count > 1 {
            return Array(viewModel.selectedFilePaths)
        }
        return [path]
    }

    private func confirmDiscard(_ paths: [String]) {
        discardConfirmPaths = paths
        showDiscardConfirm = true
    }

    private var stagingFileList: some View {
        let stagedList = stagedFiles
        let unstagedList = unstagedFiles
        let stagedPaths = stagedList.map(\.path)
        let unstagedPaths = unstagedList.map(\.path)

        return fileListContainer(maxHeight: .infinity) {
            GeometryReader { viewportGeo in
                let unstagedContentBottomY = unstagedRowFrames.values.map(\.maxY).max()
                    ?? (unstagedSectionMinY ?? viewportGeo.size.height)
                let unstagedBlankSelectionHeight = max(0, viewportGeo.size.height - unstagedContentBottomY)

                ScrollViewReader { proxy in
                    let scrollView = ScrollView {
                        LazyVStack(spacing: 0) {
                        // Staged section — entire area is a drop target (works even when empty)
                            LazyVStack(spacing: 0) {
                                stagingSectionHeader(
                                    title: "已暂存",
                                    count: stagedList.count,
                                    allSelected: !stagedList.isEmpty,
                                    onToggle: {
                                        Task {
                                            if stagedList.isEmpty {
                                                await viewModel.stageAllFiles()
                                            } else {
                                                await viewModel.unstageAllFiles()
                                            }
                                        }
                                    }
                                )

                                ForEach(stagedList) { file in
                                    StagingFileRow(
                                        file: file,
                                        isSelected: isStatusFileSelected(file.path, in: .staged),
                                        isStaged: true,
                                        onToggle: { Task { await viewModel.unstageFile(file.path) } },
                                        dragPayload: dragPayload(for: file.path, sourceArea: .staged)
                                    )
                                    .equatable()
                                    .id(fileRowID(for: file.path, context: .staged))
                                    .onTapGesture {
                                        focusedTarget = .fileList
                                        suppressNextFileListAutoScroll = true
                                        let flags = NSEvent.modifierFlags
                                        viewModel.toggleFileSelection(
                                            file.path,
                                            context: .staged,
                                            isMulti: flags.contains(.command),
                                            isRange: flags.contains(.shift),
                                            orderedPaths: stagedPaths
                                        )
                                        Task {
                                            let diffFile = matchingDiffFile(for: file)
                                            await viewModel.selectDiffFile(diffFile, context: .staged)
                                            await viewModel.openFileInspector(diffFile, context: .staged, preferredMode: .diff)
                                        }
                                    }
                                    .contextMenu { stagedFileContextMenu(file) }
                                }

                                if stagedList.isEmpty {
                                    Text("Drag files here to stage")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .frame(maxWidth: .infinity, minHeight: 28)
                                }
                            }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleDrop(providers: providers, to: .staged)
                            }

                            Divider().padding(.vertical, 2)

                            applyUnstagedSelectionGesture(to: LazyVStack(spacing: 0) {
                                stagingSectionHeader(
                                    title: "未暂存",
                                    count: unstagedList.count,
                                    allSelected: false,
                                    onToggle: {
                                        Task { await viewModel.stageAllFiles() }
                                    },
                                    onDiscard: {
                                        let selected = viewModel.selectedFilePaths
                                        let unstagedPathSet = Set(unstagedList.map(\.path))
                                        let targets = selected.filter { unstagedPathSet.contains($0) }
                                        if targets.count > 1 {
                                            confirmDiscard(Array(targets))
                                        } else {
                                            confirmDiscard(unstagedList.map(\.path))
                                        }
                                    }
                                )

                                ForEach(unstagedList) { file in
                                    StagingFileRow(
                                        file: file,
                                        isSelected: isStatusFileSelected(file.path, in: .unstaged),
                                        isStaged: false,
                                        onToggle: { Task { await viewModel.stageFile(file.path) } },
                                        dragPayload: isRubberBanding ? nil : dragPayload(for: file.path, sourceArea: .unstaged)
                                    )
                                    .equatable()
                                    .id(fileRowID(for: file.path, context: .unstaged))
                                    .modifier(UnstagedRowFrameReporter(
                                        isEnabled: supportsUnstagedRubberBandSelection,
                                        filePath: file.path
                                    ))
                                    .onTapGesture {
                                        guard !isRubberBanding else { return }
                                        focusedTarget = .fileList
                                        suppressNextFileListAutoScroll = true
                                        let flags = NSEvent.modifierFlags
                                        viewModel.toggleFileSelection(
                                            file.path,
                                            context: .unstaged,
                                            isMulti: flags.contains(.command),
                                            isRange: flags.contains(.shift),
                                            orderedPaths: unstagedPaths
                                        )
                                        Task {
                                            let diffFile = matchingDiffFile(for: file)
                                            await viewModel.selectDiffFile(diffFile, context: .unstaged)
                                            await viewModel.openFileInspector(diffFile, context: .unstaged, preferredMode: .diff)
                                        }
                                    }
                                    .contextMenu { unstagedFileContextMenu(file) }
                                }

                                if unstagedList.isEmpty {
                                    Text("Drag files here to unstage")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .frame(maxWidth: .infinity, minHeight: 28)
                                }
                            }
                            .modifier(UnstagedSectionBoundsReporter(
                                isEnabled: supportsUnstagedRubberBandSelection
                            ))
                            .overlay(alignment: .topLeading) {
                                if unstagedBlankSelectionHeight > 0,
                                   let unstagedSectionMinY {
                                    UnstagedBlankSelectionHitView(
                                        originY: unstagedContentBottomY,
                                        debugColor: .clear,
                                        onBegin: beginRubberBandSelection,
                                        onChange: updateRubberBandSelection,
                                        onEnd: endRubberBandSelection
                                    )
                                    .frame(
                                        width: viewportGeo.size.width,
                                        height: unstagedBlankSelectionHeight
                                    )
                                    .offset(y: unstagedContentBottomY - unstagedSectionMinY)
                                }
                            }
                            .onPreferenceChange(UnstagedRowFrameKey.self) { frames in
                                guard supportsUnstagedRubberBandSelection else { return }
                                unstagedRowFrames = frames
                            }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleDrop(providers: providers, to: .unstaged)
                            })
                        }
                    }
                    .coordinateSpace(name: "unstagedArea")
                    .onPreferenceChange(UnstagedSectionBoundsKey.self) { minY in
                        guard supportsUnstagedRubberBandSelection else { return }
                        unstagedSectionMinY = minY
                    }
                    .overlay(alignment: .topLeading) {
                        if supportsUnstagedRubberBandSelection && isRubberBanding {
                            rubberBandOverlay
                        }
                    }
                    .onChange(of: selectedStatusRowID) { _, rowID in
                        handleFileListSelectionChange(rowID, with: proxy)
                    }
                    scrollView
                }
            }
            .allowsHitTesting(!viewModel.isStageOperationInProgress)
            .overlay(alignment: .topTrailing) {
                if viewModel.isStageOperationInProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.windowBackgroundColor).opacity(0.72))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(.separatorColor).opacity(0.45), lineWidth: 0.5)
                    )
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private func applyUnstagedSelectionGesture<Content: View>(to content: Content) -> some View {
        if supportsUnstagedRubberBandSelection {
            content.simultaneousGesture(unstagedRubberBandGesture)
        } else {
            content
        }
    }

    private var unstagedRubberBandGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("unstagedArea")))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let drag?):
                    guard isValidRubberBandStart(drag.startLocation) else {
                        if isRubberBanding {
                            isRubberBanding = false
                        }
                        return
                    }
                    if !isRubberBanding {
                        isRubberBanding = true
                        rubberBandOrigin = drag.startLocation
                        viewModel.selectedFilePaths = []
                        viewModel.selectedFileListContext = .unstaged
                        viewModel.selectedDiffFile = nil
                    }
                    rubberBandCurrent = drag.location
                    updateRubberBandSelection()
                default:
                    break
                }
            }
            .onEnded { _ in
                isRubberBanding = false
            }
    }

    // MARK: - Conflict Staging File List (Staged / Unstaged during conflict resolution)

    private func conflictStagingFileList(conflictedFiles: [ConflictFile], resolvedFiles: [ConflictFile]) -> some View {
        let conflictPaths = Set(conflictedFiles.map(\.path))
        let resolvedPaths = Set(resolvedFiles.map(\.path))

        return fileListContainer(maxHeight: .infinity) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            stagingSectionHeader(
                                title: "已暂存",
                                count: conflictStagedFiles(excludingConflicts: conflictPaths).count,
                                allSelected: !conflictStagedFiles(excludingConflicts: conflictPaths).isEmpty,
                                onToggle: {
                                    Task {
                                        if conflictStagedFiles(excludingConflicts: conflictPaths).isEmpty {
                                            await viewModel.stageAllFiles()
                                        } else {
                                            await viewModel.unstageAllFiles()
                                        }
                                    }
                                }
                            )

                            ForEach(conflictStagedFiles(excludingConflicts: conflictPaths)) { file in
                                StagingFileRow(
                                    file: file,
                                    isSelected: isStatusFileSelected(file.path, in: .staged),
                                    isStaged: true,
                                    onToggle: { Task { await viewModel.unstageFile(file.path) } },
                                    dragPayload: dragPayload(for: file.path, sourceArea: .staged)
                                )
                                .id(fileRowID(for: file.path, context: .staged))
                                .onTapGesture {
                                    focusedTarget = .fileList
                                    suppressNextFileListAutoScroll = true
                                    let flags = NSEvent.modifierFlags
                                    viewModel.toggleFileSelection(
                                        file.path,
                                        context: .staged,
                                        isMulti: flags.contains(.command),
                                        isRange: flags.contains(.shift),
                                        orderedPaths: conflictStagedFiles(excludingConflicts: conflictPaths).map(\.path)
                                    )
                                    Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .staged) }
                                }
                                .contextMenu {
                                    conflictStagedFileContextMenu(file, wasConflicted: resolvedPaths.contains(file.path))
                                }
                            }

                            if conflictStagedFiles(excludingConflicts: conflictPaths).isEmpty {
                                Text("Drag files here to stage")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                        }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleDrop(providers: providers, to: .staged)
                        }

                        Divider().padding(.vertical, 2)

                        VStack(spacing: 0) {
                            stagingSectionHeader(
                                title: "未暂存",
                                count: conflictUnstagedFiles(excludingConflicts: conflictPaths).count,
                                allSelected: false,
                                onToggle: {
                                    Task { await viewModel.stageAllFiles() }
                                }
                            )

                            ForEach(conflictUnstagedFiles(excludingConflicts: conflictPaths)) { file in
                                StagingFileRow(
                                    file: file,
                                    isSelected: isStatusFileSelected(file.path, in: .unstaged),
                                    isStaged: false,
                                    onToggle: { Task { await viewModel.stageFile(file.path) } },
                                    dragPayload: dragPayload(for: file.path, sourceArea: .unstaged)
                                )
                                .id(fileRowID(for: file.path, context: .unstaged))
                                .onTapGesture {
                                    focusedTarget = .fileList
                                    suppressNextFileListAutoScroll = true
                                    let flags = NSEvent.modifierFlags
                                    viewModel.toggleFileSelection(
                                        file.path,
                                        context: .unstaged,
                                        isMulti: flags.contains(.command),
                                        isRange: flags.contains(.shift),
                                        orderedPaths: conflictUnstagedFiles(excludingConflicts: conflictPaths).map(\.path)
                                    )
                                    Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .unstaged) }
                                }
                                .contextMenu {
                                    conflictUnstagedFileContextMenu(file, wasConflicted: resolvedPaths.contains(file.path))
                                }
                            }

                            if conflictUnstagedFiles(excludingConflicts: conflictPaths).isEmpty {
                                Text("Drag files here to unstage")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                        }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleDrop(providers: providers, to: .unstaged)
                        }
                    }
                }
                .onChange(of: selectedStatusRowID) { _, rowID in
                    handleFileListSelectionChange(rowID, with: proxy)
                }
            }
        }
    }

    private func conflictStagedFiles(excludingConflicts conflictPaths: Set<String>) -> [FileStatus] {
        stagedFiles.filter { !conflictPaths.contains($0.path) }
    }

    private func conflictUnstagedFiles(excludingConflicts conflictPaths: Set<String>) -> [FileStatus] {
        unstagedFiles.filter { !conflictPaths.contains($0.path) }
    }

    // MARK: - Staged File Context Menu

    @ViewBuilder
    private func stagedFileContextMenu(_ file: FileStatus) -> some View {
        let paths = selectedOrSingle(file.path)

        Button("Unstage") {
            Task { await viewModel.unstageFiles(paths) }
        }

        Divider()

        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path, context: .staged) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths(paths) }

        Button("Create patch from file changes") {
            Task { await viewModel.createPatch(paths: paths) }
        }

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }

        if file.path.isPreviewableFile {
            Button("Preview") {
                Task { await viewModel.openFilePreview(path: file.path, context: .staged) }
            }
        }

        Divider()

        Button("Delete file", role: .destructive) {
            Task { await viewModel.deleteFiles(paths: paths) }
        }
    }

    // MARK: - Unstaged File Context Menu

    @ViewBuilder
    private func unstagedFileContextMenu(_ file: FileStatus) -> some View {
        let paths = selectedOrSingle(file.path)

        Button("Stage") {
            Task { await viewModel.stageFiles(paths) }
        }

        Button("Discard changes", role: .destructive) {
            confirmDiscard(paths)
        }

        Menu("Ignore") {
            Button("Ignore \(file.path)") {
                Task { await viewModel.addToGitignore(pattern: file.path) }
            }
            if let ext = file.path.split(separator: ".").last, ext.count < 10 {
                Button("Ignore *.\(ext)") {
                    Task { await viewModel.addToGitignore(pattern: "*.\(ext)") }
                }
            }
            if file.path.contains("/") {
                let dir = (file.path as NSString).deletingLastPathComponent
                Button("Ignore \(dir)/") {
                    Task { await viewModel.addToGitignore(pattern: "\(dir)/") }
                }
            }
        }

        Divider()

        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path, context: .unstaged) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths(paths) }

        Button("Create patch from file changes") {
            Task { await viewModel.createPatch(paths: paths) }
        }

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }

        if file.path.isPreviewableFile {
            Button("Preview") {
                Task { await viewModel.openFilePreview(path: file.path, context: .unstaged) }
            }
        }

        Divider()

        Button("Delete file", role: .destructive) {
            Task { await viewModel.deleteFiles(paths: paths) }
        }
    }

    // MARK: - Conflict File Context Menus

    @ViewBuilder
    private func conflictFileContextMenu(_ file: ConflictFile) -> some View {
        Button("Open Conflict Merge") {
            Task { await viewModel.openConflictMerge(file) }
        }

        Button("Mark as Resolved") {
            Task { await viewModel.markFileResolved(file) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths([file.path]) }

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }
    }

    @ViewBuilder
    private func conflictStagedFileContextMenu(_ file: FileStatus, wasConflicted: Bool) -> some View {
        let paths = selectedOrSingle(file.path)

        Button("Unstage") {
            Task { await viewModel.unstageFiles(paths) }
        }

        if wasConflicted {
            Button("Mark as Conflicted") {
                Task { await viewModel.markFileConflicted(path: file.path) }
            }
        }

        Divider()

        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path, context: .staged) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths(paths) }

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }

        Divider()

        Button("Delete file", role: .destructive) {
            Task { await viewModel.deleteFiles(paths: paths) }
        }
    }

    @ViewBuilder
    private func conflictUnstagedFileContextMenu(_ file: FileStatus, wasConflicted: Bool) -> some View {
        let paths = selectedOrSingle(file.path)

        Button("Stage") {
            Task { await viewModel.stageFiles(paths) }
        }

        Button("Discard changes", role: .destructive) {
            confirmDiscard(paths)
        }

        if wasConflicted {
            Button("Mark as Conflicted") {
                Task { await viewModel.markFileConflicted(path: file.path) }
            }
        }

        Divider()

        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path, context: .unstaged) }
        }

        Divider()

        Button("Show in Finder") { viewModel.showInFinder(path: file.path) }

        Button("Copy file path") { viewModel.copyFilePaths(paths) }

        Button("Open in Default Editor") {
            viewModel.openInEditor(path: file.path)
        }

        Divider()

        Button("Delete file", role: .destructive) {
            Task { await viewModel.deleteFiles(paths: paths) }
        }
    }

    private func stagingSectionHeader(title: String, count: Int, allSelected: Bool, onToggle: @escaping () -> Void, onDiscard: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(allSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text("\(title) (\(count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let onDiscard, count > 0 {
                Button(action: onDiscard) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .hoverTooltip("Discard all unstaged changes")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func matchingDiffFile(for status: FileStatus) -> DiffFile {
        viewModel.diffFiles.first(where: { $0.path == status.path })
            ?? DiffFile(additions: 0, deletions: 0, path: status.path, changeKind: status.diffChangeKind)
    }

    /// Build the drag payload for a file row.
    /// If the file is part of a multi-selection, all selected paths are included
    /// (newline-separated) so that the entire selection moves together.
    private func dragPayload(for filePath: String, sourceArea: StageDropArea) -> String {
        let selected = viewModel.selectedFilePaths
        let sourcePrefix = sourceArea.rawValue + ":"
        if selected.contains(filePath), selected.count > 1 {
            return selected.sorted()
                .map { sourcePrefix + $0 }
                .joined(separator: "\n")
        }
        return sourcePrefix + filePath
    }

    private func handleDrop(providers: [NSItemProvider], to destinationArea: StageDropArea) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let payload = item as? String else { return }
                let decoded = StageFileDragPayload.decode(payload)
                guard !decoded.paths.isEmpty else { return }
                guard decoded.sourceArea != destinationArea else { return }

                Task { @MainActor in
                    if destinationArea == .staged {
                        await viewModel.stageFiles(decoded.paths)
                    } else {
                        await viewModel.unstageFiles(decoded.paths)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Rubber-band selection helpers

    /// Overlay rectangle drawn while rubber-band selection is active.
    @ViewBuilder
    private var rubberBandOverlay: some View {
        let x = min(rubberBandOrigin.x, rubberBandCurrent.x)
        let y = min(rubberBandOrigin.y, rubberBandCurrent.y)
        let w = max(1, abs(rubberBandCurrent.x - rubberBandOrigin.x))
        let h = max(1, abs(rubberBandCurrent.y - rubberBandOrigin.y))
        Rectangle()
            .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
            .background(Color.accentColor.opacity(0.08))
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    /// Recalculates which unstaged rows intersect the current rubber-band rect
    /// and updates `viewModel.selectedFilePaths` accordingly.
    private func updateRubberBandSelection() {
        let selRect = CGRect(
            x: min(rubberBandOrigin.x, rubberBandCurrent.x),
            y: min(rubberBandOrigin.y, rubberBandCurrent.y),
            width: abs(rubberBandCurrent.x - rubberBandOrigin.x),
            height: abs(rubberBandCurrent.y - rubberBandOrigin.y)
        )
        var newSelection: Set<String> = []
        for file in unstagedFiles {
            if let frame = unstagedRowFrames[file.path], selRect.intersects(frame) {
                newSelection.insert(file.path)
            }
        }
        viewModel.selectedFilePaths = newSelection
    }

    private func beginRubberBandSelection(at location: CGPoint) {
        guard isValidRubberBandStart(location) else { return }
        isRubberBanding = true
        rubberBandOrigin = location
        rubberBandCurrent = location
        viewModel.selectedFilePaths = []
        viewModel.selectedFileListContext = .unstaged
        viewModel.selectedDiffFile = nil
    }

    private func updateRubberBandSelection(to location: CGPoint) {
        guard isRubberBanding else { return }
        rubberBandCurrent = location
        updateRubberBandSelection()
    }

    private func endRubberBandSelection() {
        isRubberBanding = false
    }

    private func isValidRubberBandStart(_ location: CGPoint) -> Bool {
        guard let unstagedSectionMinY else { return false }
        return location.y >= unstagedSectionMinY
    }

    // MARK: - Diff Content

    private var diffContentView: some View {
        Group {
            if viewModel.isFileTooLarge {
                fileTooLargeView
            } else if viewModel.selectedDiffFile?.isPureRename == true,
                      let oldPath = viewModel.selectedDiffFile?.oldPath,
                      let newPath = viewModel.selectedDiffFile?.path {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("File renamed — no content changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(oldPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(newPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff = viewModel.parsedDiff, !diff.hunks.isEmpty {
                let isUncommitted = viewModel.selectedCommit?.isUncommitted == true
                DiffHunkView(
                    diff: diff,
                    isUncommitted: isUncommitted,
                    diffContext: viewModel.currentDiffContext,
                    viewModel: viewModel,
                    onMoveSelection: { step in
                        focusedTarget = .fileList
                        handleFileListStep(step)
                    }
                )
            } else if let visualContent = viewModel.selectedDiffVisualContent,
                      viewModel.selectedDiffFile != nil {
                VisualFileContentView(
                    content: visualContent,
                    path: viewModel.selectedDiffFile?.path ?? "",
                    mode: .diff,
                    oldPath: viewModel.selectedDiffFile?.oldPath
                )
            } else if viewModel.selectedDiffFile != nil {
                if viewModel.isLoadingDiff {
                    ProgressView("Loading diff...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.fileDiffContent.isEmpty {
                    if viewModel.fileDiffContent == "Failed to load diff" {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Failed to load diff")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.fileDiffContent == "No changes in this file" {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No changes in this file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("No changes to display")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("No changes to display")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Select a file to view diff")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileTooLargeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("File too large to diff (\(viewModel.fileTooLargeSizeMB) MB)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: { Task { await viewModel.forceLoadFileDiff() } }) {
                    Label("Load anyway", systemImage: "eye")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button(action: { viewModel.openExternalDiffTool() }) {
                    Label("Open in External Diff Tool", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Text("Tip: 通过 `git config diff.tool <tool>` 配置外部 diff 工具")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - AI Commit Button

    private var aiCommitButton: some View {
        Button(action: {
            Task { await viewModel.generateAICommitMessage() }
        }) {
            HStack(spacing: 3) {
                if viewModel.isGeneratingAICommit {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                }
                Text("AI")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.purple.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.purple.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGeneratingAICommit)
        .hoverTooltip("Generate commit message with AI")
    }

    // MARK: - Commit Input (shown at bottom when uncommitted)

    private var commitInputArea: some View {
        VStack(spacing: 0) {
            // Header: "Commit Message" + Amend checkbox + AI button
            HStack {
                Text("Commit Message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle(isOn: Binding(
                    get: { viewModel.isAmend },
                    set: { newValue in
                        viewModel.isAmend = newValue
                        if newValue {
                            Task { await viewModel.loadHeadCommitMessage() }
                        } else {
                            viewModel.commitSummary = ""
                            viewModel.commitDescription = ""
                        }
                    }
                )) {
                    Text("Amend")
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                aiCommitButton
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Summary field with char count
            HStack(spacing: 0) {
                CommitTitleField(
                    text: Binding(
                        get: { viewModel.commitSummary },
                        set: { viewModel.commitSummary = $0 }
                    ),
                    placeholder: "Summary",
                    font: .systemFont(ofSize: 11)
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Text("\(72 - viewModel.commitSummary.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(viewModel.commitSummary.count > 72 ? .red : .secondary)
                    .padding(.trailing, 6)
            }
            .frame(height: 24)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal, 8)

            // Description field
            commitDescriptionField(
                text: Binding(
                    get: { viewModel.commitDescription },
                    set: { viewModel.commitDescription = $0 }
                ),
                placeholder: "Description",
                cornerRadius: 3
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Commit button
            if !viewModel.isAmend && stagedFiles.isEmpty && !unstagedFiles.isEmpty {
                Button(action: {
                    Task { await viewModel.stageAllFiles() }
                }) {
                    Text("Stage all changes to commit")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            } else {
                Button(action: {
                    Task { await viewModel.performCommit() }
                }) {
                    Text(viewModel.isAmend ? "Amend Commit" : "Commit")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.commitSummary.isEmpty)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func commitDescriptionField(text: Binding<String>, placeholder: String, cornerRadius: CGFloat) -> some View {
        CommitMessageEditor(text: text)
            .frame(minHeight: LayoutDefaults.CommittedMessage.editingDescriptionMinHeight, maxHeight: .infinity)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, CommitMessageEditor.horizontalInset)
                        .padding(.top, CommitMessageEditor.verticalInset + 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
    }

    // MARK: - Conflict Panel (Rebase / Merge / Stash)

    private func conflictPanel(_ type: ConflictType) -> some View {
        let conflictedFiles = viewModel.currentConflictedFiles
        let resolvedFiles = viewModel.currentResolvedFiles

        return VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14))
                    Text(type.title)
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                }

                conflictHeaderDetail(type)
            }
            .padding(10)

            Divider()

            // Conflicted Files
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                    Text("Conflicted Files (\(conflictedFiles.count))")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !conflictedFiles.isEmpty {
                        Button("Mark All Resolved") {
                            Task { await viewModel.markAllFilesResolved() }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                ForEach(conflictedFiles) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(file.path)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                    .background(Color(.controlBackgroundColor).opacity(0.3))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.openConflictMerge(file) }
                    }
                    .contextMenu { conflictFileContextMenu(file) }
                }
            }

            Divider().padding(.vertical, 2)

            // Staged Files
            conflictStagingFileList(conflictedFiles: conflictedFiles, resolvedFiles: resolvedFiles)

            Divider()

            // Diff content view
            diffContentView

            Divider()

            // Commit section
            conflictCommitSection(type, conflictedFiles: conflictedFiles)

            Divider()

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: { Task { await viewModel.conflictAbort() } }) {
                    Text(type.abortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                if case .rebase = type {
                    Button(action: { Task { await viewModel.rebaseSkip() } }) {
                        Text("Skip")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: { Task { await viewModel.conflictContinue() } }) {
                    Text(type.continueLabel)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!conflictedFiles.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func conflictHeaderDetail(_ type: ConflictType) -> some View {
        switch type {
        case .rebase:
            if let state = viewModel.rebaseState {
                HStack(spacing: 4) {
                    Text("Rebasing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(state.sourceBranch)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                    Text("onto")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(state.targetBranch)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.2)))
                        .foregroundStyle(.green)
                }
            }
        case .merge(let branch):
            HStack(spacing: 4) {
                Text("Merging")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(branch)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
                Text("into")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentBranch)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.2)))
                    .foregroundStyle(.green)
            }
        case .stashApply:
            HStack(spacing: 4) {
                Text("Applying stashed changes onto")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentBranch)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.2)))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func conflictCommitSection(_ type: ConflictType, conflictedFiles: [ConflictFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 10))
                Text("Commit")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }

            if case .rebase = type {
                Toggle(isOn: Binding(
                    get: { viewModel.isAmend },
                    set: { viewModel.isAmend = $0 }
                )) {
                    Text("Amend previous commit")
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                if let state = viewModel.rebaseState {
                    Text("Rebasing commit \(state.currentStep) out of \(state.totalSteps)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Commit message editor
            TextEditor(text: conflictMessageBinding(type))
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
            .frame(minHeight: 60, maxHeight: 100)

            if !conflictedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("# Conflicts:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(conflictedFiles) { file in
                        Text("#   \(file.path)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            DisclosureGroup("Commit options") {
                EmptyView()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func conflictMessageBinding(_ type: ConflictType) -> Binding<String> {
        switch type {
        case .rebase:
            return Binding(
                get: { viewModel.rebaseCommitMessage },
                set: { viewModel.rebaseCommitMessage = $0 }
            )
        case .merge, .stashApply:
            return Binding(
                get: { viewModel.mergeCommitMessage },
                set: { viewModel.mergeCommitMessage = $0 }
            )
        }
    }

    // MARK: - Empty

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a commit to view details")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var stagedFiles: [FileStatus] {
        viewModel.fileStatuses.filter(\.hasStagedChanges)
    }

    private var unstagedFiles: [FileStatus] {
        viewModel.fileStatuses.filter(\.hasUnstagedChanges)
    }

    private var selectedStatusRowID: String? {
        guard let path = viewModel.selectedDiffFile?.path else { return nil }
        switch viewModel.currentDiffContext {
        case .staged, .unstaged:
            return fileRowID(for: path, context: viewModel.currentDiffContext)
        case .committed:
            return nil
        }
    }

    private func fileRowID(for path: String, context: RepoViewModel.DiffContext) -> String {
        let prefix: String
        switch context {
        case .staged:
            prefix = "staged"
        case .unstaged:
            prefix = "unstaged"
        case .committed:
            prefix = "committed"
        }
        return "\(prefix)::\(path)"
    }

    private func isStatusFileSelected(_ path: String, in context: RepoViewModel.DiffContext) -> Bool {
        let isListContext = viewModel.selectedFileListContext == context
        if isListContext && !viewModel.selectedFilePaths.isEmpty {
            return viewModel.selectedFilePaths.contains(path)
        }

        let isDiffSelected = viewModel.selectedDiffFile?.path == path && viewModel.currentDiffContext == context
        return isDiffSelected
    }

    @ViewBuilder
    private func fileListContainer<Content: View>(maxHeight: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let shape = FileListContainerShape()
        let base = content()
            .frame(maxHeight: maxHeight)
            .clipShape(shape)
            .contentShape(Rectangle())
            .overlay {
                shape
                    .inset(by: 1)
                    .stroke(
                        focusedTarget == .fileList
                            ? Color.accentColor.opacity(0.9)
                            : Color.clear,
                        lineWidth: 1
                    )
            }
            .focusable()
            .focused($focusedTarget, equals: .fileList)
            .onMoveCommand(perform: handleFileListMove)
            .simultaneousGesture(TapGesture().onEnded {
                focusedTarget = .fileList
            })

        if #available(macOS 15.0, *) {
            base.focusEffectDisabled()
        } else {
            base
        }
    }

    private func handleFileListMove(_ direction: MoveCommandDirection) {
        guard focusedTarget == .fileList else { return }

        let step: Int
        switch direction {
        case .up:
            step = -1
        case .down:
            step = 1
        default:
            return
        }

        handleFileListStep(step)
    }

    private func handleFileListStep(_ step: Int) {
        guard step != 0 else { return }

        if viewModel.isInConflict {
            let conflictPaths = Set(viewModel.currentConflictedFiles.map(\.path))
            let files = viewModel.currentDiffContext == .staged
                ? conflictStagedFiles(excludingConflicts: conflictPaths)
                : conflictUnstagedFiles(excludingConflicts: conflictPaths)
            navigateStatusFiles(files, context: viewModel.currentDiffContext, step: step)
            return
        }

        if viewModel.selectedCommit?.isUncommitted == true {
            let files = viewModel.currentDiffContext == .staged ? stagedFiles : unstagedFiles
            navigateStatusFiles(files, context: viewModel.currentDiffContext, step: step)
            return
        }

        navigateDiffFiles(viewModel.diffFiles, step: step)
    }

    private func navigateDiffFiles(_ files: [DiffFile], step: Int) {
        guard let target = targetIndex(
            currentPath: viewModel.selectedDiffFile?.path,
            orderedPaths: files.map(\.path),
            step: step
        ) else { return }

        let file = files[target]
        Task {
            if viewModel.isCompareMode {
                await viewModel.selectCompareFile(file)
            } else {
                await viewModel.selectDiffFile(file)
            }
            await viewModel.openFileInspector(file, context: .committed, preferredMode: .diff)
        }
    }

    private func navigateStatusFiles(_ files: [FileStatus], context: RepoViewModel.DiffContext, step: Int) {
        let orderedPaths = files.map(\.path)
        let currentPath = viewModel.selectedDiffFile?.path
            ?? viewModel.selectedFilePaths.first

        guard let target = targetIndex(
            currentPath: currentPath,
            orderedPaths: orderedPaths,
            step: step
        ) else { return }

        let file = files[target]
        let diffFile = matchingDiffFile(for: file)
        viewModel.selectedFilePaths = [file.path]
        viewModel.selectedFileListContext = context
        Task {
            await viewModel.selectDiffFile(diffFile, context: context)
            await viewModel.openFileInspector(diffFile, context: context, preferredMode: .diff)
        }
    }

    private func targetIndex(currentPath: String?, orderedPaths: [String], step: Int) -> Int? {
        guard !orderedPaths.isEmpty else { return nil }

        let fallback = step > 0 ? 0 : orderedPaths.count - 1
        guard let currentPath, let currentIndex = orderedPaths.firstIndex(of: currentPath) else {
            return fallback
        }

        let nextIndex = currentIndex + step
        guard orderedPaths.indices.contains(nextIndex) else {
            return currentIndex
        }
        return nextIndex
    }

    private func scrollFileRow(_ rowID: String?, with proxy: ScrollViewProxy) {
        guard let rowID else { return }
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(rowID, anchor: .center)
            }
        }
    }

    private func handleFileListSelectionChange(_ rowID: String?, with proxy: ScrollViewProxy) {
        guard !isResizingPane else { return }
        if suppressNextFileListAutoScroll {
            suppressNextFileListAutoScroll = false
            return
        }
        scrollFileRow(rowID, with: proxy)
    }

    private enum SplitResizeAxis {
        case top
        case bottom
    }

    private func splitResizeHandle(
        height: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        axis: SplitResizeAxis,
        totalHeight: CGFloat
    ) -> some View {
        Rectangle()
            .fill(Color(.separatorColor).opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: splitHandleHeight)
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 36, height: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(axis == .top ? "detailCommittedSplit" : "detailUncommittedSplit")
                )
                    .onChanged { value in
                        isResizingPane = true
                        if splitDragStartHeight == nil {
                            splitDragStartHeight = height.wrappedValue
                        }
                        let baseHeight = splitDragStartHeight ?? height.wrappedValue
                        let delta: CGFloat
                        switch axis {
                        case .top:
                            delta = value.translation.height
                        case .bottom:
                            delta = -value.translation.height
                        }
                        let nextHeight = baseHeight + delta
                        height.wrappedValue = min(max(nextHeight, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isResizingPane = false
                        splitDragStartHeight = nil
                    }
            )
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }


    private func formattedDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: " ")
        guard parts.count >= 2 else { return dateStr }
        return "\(parts[0]) \(parts[1])"
    }
}

private struct FileListContainerShape: InsettableShape {
    private let topLeadingRadius: CGFloat = 6
    private let topTrailingRadius: CGFloat = 6
    private let bottomLeadingRadius: CGFloat = 6
    private let bottomTrailingRadius: CGFloat = 16
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path { path in
            let tl = min(min(topLeadingRadius, rect.width / 2), rect.height / 2)
            let tr = min(min(topTrailingRadius, rect.width / 2), rect.height / 2)
            let bl = min(min(bottomLeadingRadius, rect.width / 2), rect.height / 2)
            let br = min(min(bottomTrailingRadius, rect.width / 2), rect.height / 2)

            path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Preference Key for rubber-band row frames

private struct UnstagedRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct CommittedMetadataHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct UnstagedSectionBoundsKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

private struct UnstagedRowFrameReporter: ViewModifier {
    let isEnabled: Bool
    let filePath: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: UnstagedRowFrameKey.self,
                        value: [filePath: geo.frame(in: .named("unstagedArea"))]
                    )
                }
            )
        } else {
            content
        }
    }
}

private struct UnstagedSectionBoundsReporter: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: UnstagedSectionBoundsKey.self,
                        value: geo.frame(in: .named("unstagedArea")).minY
                    )
                }
            )
        } else {
            content
        }
    }
}

private struct UnstagedBlankSelectionHitView: NSViewRepresentable {
    let originY: CGFloat
    let debugColor: Color
    let onBegin: (CGPoint) -> Void
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> BlankSelectionNSView {
        let view = BlankSelectionNSView()
        view.onBegin = onBegin
        view.onChange = onChange
        view.onEnd = onEnd
        view.originY = originY
        view.debugColor = NSColor(debugColor)
        return view
    }

    func updateNSView(_ nsView: BlankSelectionNSView, context: Context) {
        nsView.onBegin = onBegin
        nsView.onChange = onChange
        nsView.onEnd = onEnd
        nsView.originY = originY
        nsView.debugColor = NSColor(debugColor)
        nsView.needsDisplay = true
    }
}

private struct StatusRowContentDragModifier: ViewModifier {
    let payload: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload)
        } else {
            content
        }
    }
}

struct StageFileDragPayload {
    let sourceArea: DetailPanelView.StageDropArea
    let paths: [String]

    static func decode(_ payload: String) -> StageFileDragPayload {
        let lines = payload.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return StageFileDragPayload(sourceArea: .unstaged, paths: [])
        }

        let decodedLines = lines.compactMap { line -> (DetailPanelView.StageDropArea, String)? in
            guard let separatorIndex = line.firstIndex(of: ":") else { return nil }
            let rawArea = String(line[..<separatorIndex])
            let pathStart = line.index(after: separatorIndex)
            let path = String(line[pathStart...])
            guard let area = DetailPanelView.StageDropArea(rawValue: rawArea), !path.isEmpty else { return nil }
            return (area, path)
        }

        if let firstArea = decodedLines.first?.0 {
            return StageFileDragPayload(
                sourceArea: firstArea,
                paths: decodedLines
                    .filter { $0.0 == firstArea }
                    .map(\.1)
            )
        }

        // Backward compatibility for older plain-path payloads:
        // treat them as unstaged-origin drags so existing drops degrade safely.
        return StageFileDragPayload(sourceArea: .unstaged, paths: lines)
    }
}

private final class BlankSelectionNSView: NSView {
    var onBegin: ((CGPoint) -> Void)?
    var onChange: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    var originY: CGFloat = 0
    var debugColor: NSColor = .clear

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        debugColor.setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        handleDragSequence(startingWith: event)
    }

    private func handleDragSequence(startingWith event: NSEvent) {
        onBegin?(translatedPoint(for: event))

        guard let window else {
            onEnd?()
            return
        }

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch nextEvent.type {
            case .leftMouseDragged:
                onChange?(translatedPoint(for: nextEvent))
            case .leftMouseUp:
                onEnd?()
                return
            default:
                break
            }
        }

        onEnd?()
    }

    private func translatedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: originY + point.y)
    }
}

// MARK: - Sub-components

struct DiffFileRow: View {
    let file: DiffFile
    let isSelected: Bool

    private var imageStatusLabel: String? { file.imageStatusText }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rowIconName)
                .font(.caption2)
                .foregroundStyle(iconColor)

            if file.isRenamed, let oldPath = file.oldPath {
                let oldName = (oldPath as NSString).lastPathComponent
                let newName = (file.path as NSString).lastPathComponent
                let oldDir = (oldPath as NSString).deletingLastPathComponent
                let newDir = (file.path as NSString).deletingLastPathComponent
                VStack(alignment: .leading, spacing: 1) {
                    if oldDir == newDir {
                        // Same directory — just show filenames inline
                        HStack(spacing: 3) {
                            Text(oldName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .strikethrough(true, color: .secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(newName)
                                .font(.system(size: 10))
                        }
                        .lineLimit(1)
                        if !newDir.isEmpty {
                            Text(newDir)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    } else {
                        // Different directories — show full paths
                        Text(file.path)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Text("← \(oldPath)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(file.path)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 3) {
                if let imageStatusLabel {
                    Text(imageStatusLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(imageStatusColor)
                } else if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.green)
                }
                if imageStatusLabel == nil && file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.red)
                }
                if file.showsRenamedBadge {
                    Text("renamed")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
    }

    private var rowIconName: String {
        if file.isRenamed { return "arrow.triangle.2.circlepath" }
        if file.path.isImageFile { return "photo" }
        return "doc"
    }

    private var iconColor: Color {
        if file.isRenamed { return Color.accentColor.opacity(0.8) }
        if file.path.isImageFile { return .secondary }
        return .secondary
    }

    private var imageStatusColor: Color {
        switch file.changeKind {
        case .added, .untracked:
            return .green
        case .deleted:
            return .red
        default:
            return .secondary
        }
    }
}

struct StagingFileRow: View, Equatable {
    let file: FileStatus
    let isSelected: Bool
    let isStaged: Bool
    let onToggle: () -> Void
    let dragPayload: String?

    static func == (lhs: StagingFileRow, rhs: StagingFileRow) -> Bool {
        lhs.file == rhs.file &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isStaged == rhs.isStaged &&
        lhs.dragPayload == rhs.dragPayload
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(file.path)
                    .font(.system(size: 10))
                    .lineLimit(1)

                Spacer()

                Text(isStaged ? file.stagedDescription : file.unstagedDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(StatusRowContentDragModifier(payload: dragPayload))

            Button(action: onToggle) {
                Image(systemName: isStaged ? "minus.circle" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .hoverTooltip(isStaged ? "取消暂存" : "暂存")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        let desc = isStaged ? file.stagedDescription : file.unstagedDescription
        switch desc {
        case "Modified": return .orange
        case "Added": return .green
        case "Deleted": return .red
        case "Untracked": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Commit Message Editor (NSTextView wrapper for reliable keyboard focus)

struct CommitMessageEditor: NSViewRepresentable {
    static let horizontalInset: CGFloat = 4
    static let verticalInset: CGFloat = 4

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ActivatingTextView()
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: Self.horizontalInset, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommitMessageEditor

        init(_ parent: CommitMessageEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

struct CommitTitleField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = ActivatingTextField(string: text)
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = font
        textField.isBordered = false
        textField.isBezeled = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }
        if textField.font != font {
            textField.font = font
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitTitleField

        init(_ parent: CommitTitleField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

/// NSTextView subclass that forces app activation on mouseDown,
/// ensuring keyboard events go to this window immediately.
final class ActivatingTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class ActivatingTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Diff Hunk View (with stage/discard buttons & line selection)

struct DiffHunkView: View {
    let diff: ParsedDiff
    let isUncommitted: Bool
    let diffContext: RepoViewModel.DiffContext
    let viewModel: RepoViewModel
    let onMoveSelection: ((Int) -> Void)?

    @State private var selectedLines: [Int: Set<Int>] = [:]

    private var allSelected: Set<Int> {
        selectedLines.values.reduce(into: Set<Int>()) { $0.formUnion($1) }
    }

    private var hasSelection: Bool { !allSelected.isEmpty }

    private var isStaged: Bool { diffContext == .staged }

    var body: some View {
        VStack(spacing: 0) {
            if isUncommitted {
                diffToolbar
            }

            SelectableDiffView(
                hunks: diff.hunks,
                filePath: viewModel.selectedDiffFile?.path,
                isUncommitted: isUncommitted,
                selectedLines: $selectedLines,
                onMoveSelection: onMoveSelection
            )
        }
    }

    // MARK: - Unified Toolbar

    private var diffToolbar: some View {
        HStack(spacing: 6) {
            Spacer()

            Button(action: {
                Task {
                    if isStaged {
                        if hasSelection {
                            for (hunkIdx, lines) in selectedLines where !lines.isEmpty {
                                await viewModel.unstageLines(hunkIdx, lineIndices: lines)
                            }
                        } else {
                            await viewModel.unstageAllHunks()
                        }
                    } else {
                        if hasSelection {
                            for (hunkIdx, lines) in selectedLines where !lines.isEmpty {
                                await viewModel.stageLines(hunkIdx, lineIndices: lines)
                            }
                        } else {
                            await viewModel.stageAllHunks()
                        }
                    }
                    selectedLines = [:]
                }
            }) {
                Text(isStaged
                     ? (hasSelection ? "取消暂存行" : "取消暂存区块")
                     : (hasSelection ? "暂存行" : "暂存区块"))
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button(action: {
                Task {
                    if hasSelection {
                        for (hunkIdx, lines) in selectedLines where !lines.isEmpty {
                            await viewModel.discardLines(hunkIdx, lineIndices: lines)
                        }
                    } else {
                        await viewModel.discardAllHunks()
                    }
                    selectedLines = [:]
                }
            }) {
                Text(hasSelection ? "放弃行" : "放弃区块")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.6))
    }

}

// MARK: - NSTextView subclass with full cross-line text selection

private final class DiffTextViewNS: NSTextView {
    struct LineInfo {
        let range: NSRange
        let hunkIdx: Int
        let lineId: Int
        let kind: HunkLine.Kind
        let bgColor: NSColor
    }

    var lineInfos: [LineInfo] = []
    var gutterEndX: CGFloat = 0
    var onGutterClick: ((Int, Int, HunkLine.Kind) -> Void)?
    var onMoveSelection: ((Int) -> Void)?

    /// Draw full-width line backgrounds *before* text is rendered.
    override func draw(_ dirtyRect: NSRect) {
        if let lm = layoutManager, let tc = textContainer {
            let containerDirtyRect = dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
            let visibleGlyphRange = lm.glyphRange(forBoundingRect: containerDirtyRect, in: tc)
            let visibleCharRange = lm.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

            for info in lineInfos where info.bgColor != .clear {
                if NSMaxRange(info.range) <= visibleCharRange.location { continue }
                if info.range.location >= NSMaxRange(visibleCharRange) { break }
                let gr = lm.glyphRange(forCharacterRange: info.range, actualCharacterRange: nil)
                var r = lm.boundingRect(forGlyphRange: gr, in: tc)
                r.origin.x = 0
                r.origin.y += textContainerOrigin.y
                r.size.width = bounds.width
                info.bgColor.setFill()
                r.fill()
            }
        }
        super.draw(dirtyRect)
    }

    /// Detect gutter-area clicks for staging toggle; always pass through to super for normal text selection.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let pt = convert(event.locationInWindow, from: nil)
        guard pt.x < gutterEndX,
              let lm = layoutManager,
              let tc = textContainer else { return }
        let tPt = NSPoint(x: pt.x - textContainerInset.width,
                          y: pt.y - textContainerInset.height)
        let charIdx = lm.characterIndex(for: tPt, in: tc,
                                        fractionOfDistanceBetweenInsertionPoints: nil)
        for info in lineInfos where NSLocationInRange(charIdx, info.range) {
            onGutterClick?(info.hunkIdx, info.lineId, info.kind)
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty {
            switch event.keyCode {
            case 125:
                onMoveSelection?(1)
                return
            case 126:
                onMoveSelection?(-1)
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    /// Copy selected text without gutter (line numbers + ±) to clipboard.
    override func copy(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard !ranges.isEmpty, let storage = textStorage else {
            super.copy(sender)
            return
        }
        let combined = ranges
            .map { storage.attributedSubstring(from: $0).string }
            .joined(separator: "\n")
        let clean = Self.stripDiffGutter(combined)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clean, forType: .string)
    }

    /// Strip the 12-char gutter prefix ("NNNN NNNN X ") from each diff line.
    /// Non-diff lines (hunk headers, file path) are returned unchanged.
    private static func stripDiffGutter(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            // Gutter layout: [4 digit/space] [space] [4 digit/space] [space] [+/-/space] [space]
            guard line.count >= 12 else { return line }
            let chars = Array(line)
            let isNumOrSpace: (Character) -> Bool = { $0.isNumber || $0 == " " }
            guard (0..<4).allSatisfy({ isNumOrSpace(chars[$0]) }),
                  chars[4] == " ",
                  (5..<9).allSatisfy({ isNumOrSpace(chars[$0]) }),
                  chars[9] == " ",
                  chars[10] == "+" || chars[10] == "-" || chars[10] == " ",
                  chars[11] == " "
            else { return line }
            return String(line.dropFirst(12))
        }.joined(separator: "\n")
    }
}

// MARK: - NSViewRepresentable wrapper

private struct SelectableDiffView: NSViewRepresentable {
    let hunks: [ParsedHunk]
    var filePath: String? = nil
    let isUncommitted: Bool
    @Binding var selectedLines: [Int: Set<Int>]
    let onMoveSelection: ((Int) -> Void)?

    final class Coordinator: NSObject {
        /// Live binding kept up-to-date in updateNSView so closures always write to current state.
        var selectedLines: Binding<[Int: Set<Int>]>?
        var isUncommitted: Bool = false
        var lastRenderState: RenderState?
    }

    struct RenderState: Equatable {
        let filePath: String?
        let contentFingerprint: Int
        let selectionFingerprint: Int
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.borderType = .noBorder
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false

        let tv = DiffTextViewNS(frame: NSRect(origin: .zero, size: sv.contentSize))
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.lineFragmentPadding = 8
        tv.autoresizingMask = [.width]
        tv.onMoveSelection = onMoveSelection

        let coordinator = context.coordinator
        tv.onGutterClick = { [weak coordinator] hunkIdx, lineId, kind in
            guard let coord = coordinator,
                  coord.isUncommitted,
                  kind == .addition || kind == .deletion else { return }
            var current = coord.selectedLines?.wrappedValue[hunkIdx] ?? []
            if current.contains(lineId) { current.remove(lineId) } else { current.insert(lineId) }
            coord.selectedLines?.wrappedValue[hunkIdx] = current
        }

        sv.documentView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? DiffTextViewNS else { return }

        // Keep coordinator in sync with latest values
        context.coordinator.selectedLines = $selectedLines
        context.coordinator.isUncommitted = isUncommitted
        tv.onMoveSelection = onMoveSelection

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let gutterSample = "0000 0000 + " as NSString
        // textContainerInset.width(4) + lineFragmentPadding(8) + gutter chars
        tv.gutterEndX = gutterSample.size(withAttributes: [.font: font]).width + 4 + 8

        let renderState = RenderState(
            filePath: filePath,
            contentFingerprint: contentFingerprint(),
            selectionFingerprint: selectionFingerprint()
        )
        guard context.coordinator.lastRenderState != renderState else { return }
        context.coordinator.lastRenderState = renderState

        // Rebuild attributed string only when diff content or line selection changes.
        let prevLen = tv.textStorage?.length ?? 0
        let prevSel = tv.selectedRanges

        let (attrStr, lineInfos) = buildContent(font: font)
        tv.lineInfos = lineInfos
        tv.textStorage?.setAttributedString(attrStr)

        if tv.textStorage?.length == prevLen, !prevSel.isEmpty {
            tv.setSelectedRanges(prevSel, affinity: .downstream, stillSelecting: false)
        }

        // Force synchronous layout after updating the attributed string.
        // Same root cause as the old NSTextView-based source inspector: NSLayoutManager is lazy, so when
        // the text container width is updated later (widthTracksTextView fires
        // once SwiftUI assigns the real frame), textContainerChangedGeometry has
        // no previous glyph positions to diff against and produces an empty dirty
        // set — causing parts of the view to stay invisible until rubber-band
        // selected.  numberOfGlyphs triggers a full layout pass now, giving the
        // geometry-change path a valid baseline.
        _ = tv.layoutManager?.numberOfGlyphs
    }

    private func contentFingerprint() -> Int {
        var hasher = Hasher()
        hasher.combine(filePath)
        hasher.combine(hunks.count)
        for hunk in hunks {
            hasher.combine(hunk.rawHeader)
            hasher.combine(hunk.lines.count)
        }
        return hasher.finalize()
    }

    private func selectionFingerprint() -> Int {
        var hasher = Hasher()
        for key in selectedLines.keys.sorted() {
            hasher.combine(key)
            for line in selectedLines[key, default: []].sorted() {
                hasher.combine(line)
            }
        }
        return hasher.finalize()
    }

    private func buildContent(font: NSFont) -> (NSAttributedString, [DiffTextViewNS.LineInfo]) {
        let result = NSMutableAttributedString()
        var lineInfos: [DiffTextViewNS.LineInfo] = []
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if let path = filePath {
            let pathBg = NSColor(white: isDark ? 0.10 : 0.94, alpha: 1.0)
            let pathFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: pathFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: pathBg,
            ]
            result.append(NSAttributedString(string: "  \(path)\n\n", attributes: attrs))
        }

        for (hunkIdx, hunk) in hunks.enumerated() {
            // Hunk header (full-width bg via backgroundColor attribute is fine here)
            let headerBg = NSColor(white: isDark ? 0.14 : 0.91, alpha: 1.0)
            result.append(NSAttributedString(
                string: "  块 \(hunkIdx + 1):  \(hunk.displayRange)\n",
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .backgroundColor: headerBg,
                ]
            ))

            let selected = selectedLines[hunkIdx] ?? []
            for line in hunk.lines {
                let fgColor: NSColor = switch line.kind {
                case .addition: .systemGreen
                case .deletion: .systemRed
                case .context:  .labelColor
                }
                let bgColor: NSColor
                if selected.contains(line.id) {
                    bgColor = NSColor.controlAccentColor.withAlphaComponent(0.18)
                } else {
                    switch line.kind {
                    case .addition: bgColor = NSColor.systemGreen.withAlphaComponent(0.06)
                    case .deletion: bgColor = NSColor.systemRed.withAlphaComponent(0.06)
                    case .context:  bgColor = .clear
                    }
                }
                let prefix: Character = switch line.kind {
                case .addition: "+"
                case .deletion: "-"
                case .context:  " "
                }
                let oldNum = line.oldLineNum.map { String(format: "%4d", $0) } ?? "    "
                let newNum = line.newLineNum.map { String(format: "%4d", $0) } ?? "    "
                let lineStr = "\(oldNum) \(newNum) \(prefix) \(line.content)\n"

                let startLoc = result.length
                result.append(NSAttributedString(
                    string: lineStr,
                    attributes: [.font: font, .foregroundColor: fgColor]
                ))
                lineInfos.append(.init(
                    range: NSRange(location: startLoc, length: result.length - startLoc),
                    hunkIdx: hunkIdx,
                    lineId: line.id,
                    kind: line.kind,
                    bgColor: bgColor
                ))
            }
        }

        return (result, lineInfos)
    }
}

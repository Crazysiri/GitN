import SwiftUI

struct DetailPanelView: View {
    let viewModel: RepoViewModel

    @State private var isEditingMessage = false
    @State private var editedMessage = ""
    @State private var isHoveringMessage = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isRebaseConflict, let state = viewModel.rebaseState {
                rebaseConflictPanel(state)
            } else if viewModel.isCompareMode, let commit = viewModel.selectedCommit {
                compareHeader(commit)
                Divider()
                compareFileList
                Divider()
                diffContentView
            } else if let commit = viewModel.selectedCommit {
                if !commit.isUncommitted {
                    commitInfoHeader(commit)
                    Divider()
                }
                diffFileList
                Divider()
                diffContentView

                if commit.isUncommitted {
                    Divider()
                    commitInputArea
                }
            } else {
                emptyDetail
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }

    /// Only commits on the current branch (reachable from HEAD) can be edited
    private var isEditableCommit: Bool {
        guard let commit = viewModel.selectedCommit, !commit.isUncommitted else { return false }
        return viewModel.currentBranchHashes.contains(commit.hash)
    }

    private func commitInfoHeader(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Commit hash + label
            HStack(spacing: 6) {
                Text("commit:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(commit.shortHash)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
            }

            if isEditingMessage {
                // Editable message area
                VStack(alignment: .leading, spacing: 6) {
                    // Summary field with char count
                    HStack(spacing: 0) {
                        TextField("Summary", text: $editedMessage, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .lineLimit(1...5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)

                        Text("\(72 - editedMessage.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(editedMessage.count > 72 ? .red : .secondary)
                            .padding(.trailing, 6)
                    }
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    )

                    // Description field
                    CommitMessageEditor(
                        text: .constant(""),
                        placeholder: "Description"
                    )
                    .frame(minHeight: 30, maxHeight: 50)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                    )

                    // Update / Cancel buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            let msg = editedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !msg.isEmpty else { return }
                            isEditingMessage = false
                            Task { await viewModel.performEditCommitMessage(hash: commit.hash, newMessage: msg) }
                        }) {
                            Text("Update Message")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.green)
                        .disabled(editedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(action: {
                            isEditingMessage = false
                            editedMessage = ""
                        }) {
                            Text("Cancel Amend")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                }
            } else {
                // Read-only message with hover border
                Text(commit.message)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
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
                        editedMessage = commit.message
                        isEditingMessage = true
                    }
                    .help(isEditableCommit ? "Click to edit commit message" : "")
            }

            // Author info and parent hash
            HStack(spacing: 0) {
                // Avatar
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

                if let parentHash = commit.parentHashes.first {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("parent: \(String(parentHash.prefix(6)))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Merge badge
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
        .padding(10)
        .onChange(of: viewModel.selectedCommit?.hash) { _, _ in
            // Reset editing state when selecting a different commit
            isEditingMessage = false
            editedMessage = ""
            isHoveringMessage = false
        }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.diffFiles) { file in
                    DiffFileRow(
                        file: file,
                        isSelected: viewModel.selectedDiffFile?.path == file.path
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.selectCompareFile(file) }
                    }
                    .contextMenu { commitFileContextMenu(file) }
                }
            }
        }
        .frame(maxHeight: 200)
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.diffFiles) { file in
                    DiffFileRow(
                        file: file,
                        isSelected: viewModel.selectedDiffFile?.path == file.path
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await viewModel.selectDiffFile(file) }
                    }
                    .contextMenu { commitFileContextMenu(file) }
                }
            }
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Commit File Context Menu

    @ViewBuilder
    private func commitFileContextMenu(_ file: DiffFile) -> some View {
        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path) }
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
    }

    // MARK: - Staged / Unstaged split list

    private func selectedOrSingle(_ path: String) -> [String] {
        if viewModel.selectedFilePaths.contains(path) && viewModel.selectedFilePaths.count > 1 {
            return Array(viewModel.selectedFilePaths)
        }
        return [path]
    }

    private var stagingFileList: some View {
        ScrollView {
            VStack(spacing: 0) {
                stagingSectionHeader(
                    title: "已暂存",
                    count: stagedFiles.count,
                    allSelected: !stagedFiles.isEmpty,
                    onToggle: {
                        Task {
                            if stagedFiles.isEmpty {
                                await viewModel.stageAllFiles()
                            } else {
                                await viewModel.unstageAllFiles()
                            }
                        }
                    }
                )

                ForEach(stagedFiles) { file in
                    StagingFileRow(
                        file: file,
                        isSelected: viewModel.selectedFilePaths.contains(file.path)
                            || (viewModel.selectedDiffFile?.path == file.path && viewModel.currentDiffContext == .staged),
                        isStaged: true,
                        onTap: { Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .staged) } },
                        onToggle: { Task { await viewModel.unstageFile(file.path) } }
                    )
                    .onTapGesture {
                        let isMulti = NSEvent.modifierFlags.contains(.command)
                        viewModel.toggleFileSelection(file.path, isMulti: isMulti)
                        Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .staged) }
                    }
                    .contextMenu { stagedFileContextMenu(file) }
                    .draggable(file.path)
                }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleDrop(providers: providers, toStaged: true)
                }

                Divider().padding(.vertical, 2)

                stagingSectionHeader(
                    title: "未暂存",
                    count: unstagedFiles.count,
                    allSelected: false,
                    onToggle: {
                        Task { await viewModel.stageAllFiles() }
                    }
                )

                ForEach(unstagedFiles) { file in
                    StagingFileRow(
                        file: file,
                        isSelected: viewModel.selectedFilePaths.contains(file.path)
                            || (viewModel.selectedDiffFile?.path == file.path && viewModel.currentDiffContext == .unstaged),
                        isStaged: false,
                        onTap: { Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .unstaged) } },
                        onToggle: { Task { await viewModel.stageFile(file.path) } }
                    )
                    .onTapGesture {
                        let isMulti = NSEvent.modifierFlags.contains(.command)
                        viewModel.toggleFileSelection(file.path, isMulti: isMulti)
                        Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .unstaged) }
                    }
                    .contextMenu { unstagedFileContextMenu(file) }
                    .draggable(file.path)
                }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleDrop(providers: providers, toStaged: false)
                }
            }
        }
        .frame(maxHeight: 240)
    }

    // MARK: - Rebase Staging File List (Staged / Unstaged during rebase)

    private func rebaseStagingFileList(state: RebaseState) -> some View {
        let conflictPaths = Set(state.conflictedFiles.map(\.path))
        let resolvedPaths = Set(state.resolvedFiles.map(\.path))

        return ScrollView {
            VStack(spacing: 0) {
                stagingSectionHeader(
                    title: "已暂存",
                    count: rebaseStagedFiles(excludingConflicts: conflictPaths).count,
                    allSelected: !rebaseStagedFiles(excludingConflicts: conflictPaths).isEmpty,
                    onToggle: {
                        Task {
                            if rebaseStagedFiles(excludingConflicts: conflictPaths).isEmpty {
                                await viewModel.stageAllFiles()
                            } else {
                                await viewModel.unstageAllFiles()
                            }
                        }
                    }
                )

                ForEach(rebaseStagedFiles(excludingConflicts: conflictPaths)) { file in
                    StagingFileRow(
                        file: file,
                        isSelected: viewModel.selectedFilePaths.contains(file.path)
                            || (viewModel.selectedDiffFile?.path == file.path && viewModel.currentDiffContext == .staged),
                        isStaged: true,
                        onTap: { Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .staged) } },
                        onToggle: { Task { await viewModel.unstageFile(file.path) } }
                    )
                    .onTapGesture {
                        let isMulti = NSEvent.modifierFlags.contains(.command)
                        viewModel.toggleFileSelection(file.path, isMulti: isMulti)
                        Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .staged) }
                    }
                    .contextMenu {
                        rebaseStagedFileContextMenu(file, wasConflicted: resolvedPaths.contains(file.path))
                    }
                }

                Divider().padding(.vertical, 2)

                stagingSectionHeader(
                    title: "未暂存",
                    count: rebaseUnstagedFiles(excludingConflicts: conflictPaths).count,
                    allSelected: false,
                    onToggle: {
                        Task { await viewModel.stageAllFiles() }
                    }
                )

                ForEach(rebaseUnstagedFiles(excludingConflicts: conflictPaths)) { file in
                    StagingFileRow(
                        file: file,
                        isSelected: viewModel.selectedFilePaths.contains(file.path)
                            || (viewModel.selectedDiffFile?.path == file.path && viewModel.currentDiffContext == .unstaged),
                        isStaged: false,
                        onTap: { Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .unstaged) } },
                        onToggle: { Task { await viewModel.stageFile(file.path) } }
                    )
                    .onTapGesture {
                        let isMulti = NSEvent.modifierFlags.contains(.command)
                        viewModel.toggleFileSelection(file.path, isMulti: isMulti)
                        Task { await viewModel.selectDiffFile(matchingDiffFile(for: file), context: .unstaged) }
                    }
                    .contextMenu {
                        rebaseUnstagedFileContextMenu(file, wasConflicted: resolvedPaths.contains(file.path))
                    }
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private func rebaseStagedFiles(excludingConflicts conflictPaths: Set<String>) -> [FileStatus] {
        stagedFiles.filter { !conflictPaths.contains($0.path) }
    }

    private func rebaseUnstagedFiles(excludingConflicts conflictPaths: Set<String>) -> [FileStatus] {
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
            Task { await viewModel.openFileHistory(path: file.path) }
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

        Button("Discard changes") {
            Task { await viewModel.discardChanges(paths: paths) }
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
            Task { await viewModel.openFileHistory(path: file.path) }
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

        Divider()

        Button("Delete file", role: .destructive) {
            Task { await viewModel.deleteFiles(paths: paths) }
        }
    }

    // MARK: - Rebase Conflict File Context Menus

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
    private func rebaseStagedFileContextMenu(_ file: FileStatus, wasConflicted: Bool) -> some View {
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
            Task { await viewModel.openFileHistory(path: file.path) }
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
    private func rebaseUnstagedFileContextMenu(_ file: FileStatus, wasConflicted: Bool) -> some View {
        let paths = selectedOrSingle(file.path)

        Button("Stage") {
            Task { await viewModel.stageFiles(paths) }
        }

        Button("Discard changes") {
            Task { await viewModel.discardChanges(paths: paths) }
        }

        if wasConflicted {
            Button("Mark as Conflicted") {
                Task { await viewModel.markFileConflicted(path: file.path) }
            }
        }

        Divider()

        Button("File History") {
            Task { await viewModel.openFileHistory(path: file.path) }
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

    private func stagingSectionHeader(title: String, count: Int, allSelected: Bool, onToggle: @escaping () -> Void) -> some View {
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func matchingDiffFile(for status: FileStatus) -> DiffFile {
        viewModel.diffFiles.first(where: { $0.path == status.path })
            ?? DiffFile(additions: 0, deletions: 0, path: status.path)
    }

    private func handleDrop(providers: [NSItemProvider], toStaged: Bool) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let path = item as? String else { return }
                Task { @MainActor in
                    if toStaged {
                        await viewModel.stageFile(path)
                    } else {
                        await viewModel.unstageFile(path)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Diff Content

    private var diffContentView: some View {
        Group {
            if let diff = viewModel.parsedDiff, !diff.hunks.isEmpty {
                let isUncommitted = viewModel.selectedCommit?.isUncommitted == true
                DiffHunkView(
                    diff: diff,
                    isUncommitted: isUncommitted,
                    diffContext: viewModel.currentDiffContext,
                    viewModel: viewModel
                )
            } else if viewModel.selectedDiffFile != nil {
                ProgressView("Loading diff...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a file to view diff")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Commit Input (shown at bottom when uncommitted)

    private var commitInputArea: some View {
        VStack(spacing: 0) {
            // Header: "Commit Message" + Amend checkbox
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
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Summary field with char count
            HStack(spacing: 0) {
                TextField("Summary", text: Binding(
                    get: { viewModel.commitSummary },
                    set: { viewModel.commitSummary = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Text("\(72 - viewModel.commitSummary.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(viewModel.commitSummary.count > 72 ? .red : .secondary)
                    .padding(.trailing, 6)
            }
            .background(Color(.textBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal, 8)

            // Description field
            CommitMessageEditor(
                text: Binding(
                    get: { viewModel.commitDescription },
                    set: { viewModel.commitDescription = $0 }
                ),
                placeholder: "Description"
            )
            .frame(minHeight: 36, maxHeight: 60)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
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
    }

    // MARK: - Rebase Conflict Panel

    private func rebaseConflictPanel(_ state: RebaseState) -> some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14))
                    Text("Rebase conflicts detected")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                }

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
            .padding(10)

            Divider()

            // Conflicted Files
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                    Text("Conflicted Files (\(state.conflictedFiles.count))")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if !state.conflictedFiles.isEmpty {
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

                ForEach(state.conflictedFiles) { file in
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
            rebaseStagingFileList(state: state)

            Divider()

            // Diff content view
            diffContentView

            Divider()

            // Commit section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 10))
                    Text("Commit")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }

                Toggle(isOn: Binding(
                    get: { viewModel.isAmend },
                    set: { viewModel.isAmend = $0 }
                )) {
                    Text("Amend previous commit")
                        .font(.system(size: 10))
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Text("Rebasing commit \(state.currentStep) out of \(state.totalSteps)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Commit message editor
                TextEditor(text: Binding(
                    get: { viewModel.rebaseCommitMessage },
                    set: { viewModel.rebaseCommitMessage = $0 }
                ))
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                )
                .frame(minHeight: 60, maxHeight: 100)

                if !state.conflictedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("# Conflicts:")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ForEach(state.conflictedFiles) { file in
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

            Divider()

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: { Task { await viewModel.rebaseAbort() } }) {
                    Text("Abort Rebase")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Button(action: { Task { await viewModel.rebaseContinue() } }) {
                    Text("Continue Rebase")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!state.conflictedFiles.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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


    private func formattedDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: " ")
        guard parts.count >= 2 else { return dateStr }
        return "\(parts[0]) \(parts[1])"
    }
}

// MARK: - Sub-components

struct DiffFileRow: View {
    let file: DiffFile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(file.path)
                .font(.system(size: 10))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 3) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
    }
}

struct StagingFileRow: View {
    let file: FileStatus
    let isSelected: Bool
    let isStaged: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
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

            Button(action: onToggle) {
                Image(systemName: isStaged ? "minus.circle" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isStaged ? "取消暂存" : "暂存")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isSelected ? Color(.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
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
    @Binding var text: String
    var placeholder: String

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
        textView.textContainerInset = NSSize(width: 4, height: 4)
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
        context.coordinator.updatePlaceholder(textView: textView, text: text, placeholder: placeholder)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommitMessageEditor
        private var placeholderLayer: CATextLayer?

        init(_ parent: CommitMessageEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder(textView: textView, text: textView.string, placeholder: parent.placeholder)
        }

        func updatePlaceholder(textView: NSTextView, text: String, placeholder: String) {
            if text.isEmpty {
                if placeholderLayer == nil {
                    let layer = CATextLayer()
                    layer.string = placeholder
                    layer.font = NSFont.systemFont(ofSize: 11)
                    layer.fontSize = 11
                    layer.foregroundColor = NSColor.tertiaryLabelColor.cgColor
                    layer.contentsScale = textView.window?.backingScaleFactor ?? 2.0
                    placeholderLayer = layer
                }
                if let layer = placeholderLayer, layer.superlayer == nil {
                    textView.layer?.addSublayer(layer)
                    layer.frame = CGRect(x: 5, y: 0, width: textView.bounds.width - 10, height: 16)
                }
            } else {
                placeholderLayer?.removeFromSuperlayer()
            }
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

// MARK: - Diff Hunk View (with stage/discard buttons & line selection)

struct DiffHunkView: View {
    let diff: ParsedDiff
    let isUncommitted: Bool
    let diffContext: RepoViewModel.DiffContext
    let viewModel: RepoViewModel

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

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.hunks.enumerated()), id: \.offset) { hunkIdx, hunk in
                            hunkHeaderLabel(hunkIndex: hunkIdx, hunk: hunk)
                            hunkBody(hunkIndex: hunkIdx, hunk: hunk)
                        }
                    }
                    .frame(minWidth: geo.size.width, alignment: .topLeading)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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

    // MARK: - Hunk Header (label only, no buttons)

    private func hunkHeaderLabel(hunkIndex: Int, hunk: ParsedHunk) -> some View {
        HStack {
            Text("块 \(hunkIndex + 1):  \(hunk.displayRange)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.controlBackgroundColor).opacity(0.35))
    }

    // MARK: - Hunk Body

    private func hunkBody(hunkIndex: Int, hunk: ParsedHunk) -> some View {
        let selected = selectedLines[hunkIndex] ?? []

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                let isSelected = selected.contains(line.id)
                let isChangeLine = line.kind == .addition || line.kind == .deletion

                HStack(spacing: 0) {
                    Text(line.oldLineNum.map(String.init) ?? "")
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(line.newLineNum.map(String.init) ?? "")
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Rectangle()
                        .fill(Color(.separatorColor).opacity(0.3))
                        .frame(width: 1)
                        .padding(.horizontal, 3)

                    Text(prefixChar(line.kind))
                        .frame(width: 12, alignment: .center)
                        .foregroundStyle(lineTextColor(line.kind))

                    Text(line.content)
                        .foregroundStyle(lineTextColor(line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.vertical, 0.5)
                .background(lineBackground(line.kind, selected: isSelected))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isChangeLine && isUncommitted else { return }
                    var current = selectedLines[hunkIndex] ?? []
                    if current.contains(line.id) {
                        current.remove(line.id)
                    } else {
                        current.insert(line.id)
                    }
                    selectedLines[hunkIndex] = current
                }
            }
        }
    }

    // MARK: - Helpers

    private func prefixChar(_ kind: HunkLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private func lineTextColor(_ kind: HunkLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .primary
        }
    }

    private func lineBackground(_ kind: HunkLine.Kind, selected: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.18)
        }
        switch kind {
        case .addition: return .green.opacity(0.06)
        case .deletion: return .red.opacity(0.06)
        case .context: return .clear
        }
    }
}

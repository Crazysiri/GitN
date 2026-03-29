import SwiftUI
import Combine

private enum DiffEditorDebugLog {
    static func emit(_ message: @autoclosure () -> String) {
        print("[DiffEditor] \(message())")
    }
}

private enum MonacoDebugLog {
    static func emit(_ message: @autoclosure () -> String) {
        print("[MonacoBridge] \(message())")
    }
}

@Observable @MainActor
final class RepoViewModel {
    private struct DiffLoadPayload: Sendable {
        let fileDiffContent: String
        let baseText: String
        let parsedDiff: ParsedDiff?
        let visualContent: VisualFileContent?
    }

    enum FileInspectorMode: String, CaseIterable {
        case preview
        case diff
        case history
    }

    enum FileInspectorChangeKind: Int, Sendable {
        case deletion = -1
        case addition = 1
    }

    struct FileInspectorLinePair: Sendable {
        let old: Int?
        let new: Int?
    }

    struct FileInspectorOverviewSegment: Identifiable, Sendable {
        let startLine: Int
        let endLine: Int
        let kind: FileInspectorChangeKind

        var id: String { "\(kind.rawValue)-\(startLine)-\(endLine)" }
    }

    struct FileInspectorInlineHighlight: Sendable {
        let range: NSRange
        let kind: FileInspectorChangeKind
    }

    struct FileInspectorBlameInfo: Sendable, Equatable {
        let author: String
        let date: String
        let shortCommitHash: String
        let summary: String

        var toolTipText: String {
            var parts: [String] = []
            if !author.isEmpty || !date.isEmpty {
                let head = [author, date].filter { !$0.isEmpty }.joined(separator: " · ")
                if !head.isEmpty {
                    parts.append(head)
                }
            }
            let tail = [shortCommitHash, summary].filter { !$0.isEmpty }.joined(separator: " ")
            if !tail.isEmpty {
                parts.append(tail)
            }
            return parts.joined(separator: "\n")
        }
    }

    struct DiffEditorRow: Identifiable, Sendable {
        enum Kind: Sendable {
            case context
            case addition
            case deletion
        }

        let id: UUID
        let kind: Kind
        let oldLine: Int?
        let newLine: Int?
        let oldText: String?
        var newText: String?
        let isEditable: Bool
        let contentRangeInNewText: NSRange?
    }

    struct DiffEditorDocument: Sendable {
        typealias RowID = UUID

        let rows: [DiffEditorRow]
        let renderedText: String
        let editableRanges: [NSRange: RowID]
        let renderedRowRanges: [NSRange]
    }

    private struct FileInspectorEditSnapshot {
        let content: String
        let selectedRange: NSRange
    }

    private struct FileInspectorEditSession {
        var lastEditAt: Date
    }

    private struct FileInspectorArtifacts: Sendable {
        let diffEditorDocument: DiffEditorDocument?
        let renderedText: String
        let totalLines: Int
        let lineHighlights: [Int: FileInspectorChangeKind]
        let inlineHighlights: [FileInspectorInlineHighlight]
        let linePairs: [Int: FileInspectorLinePair]
        let hunkControls: [Int: Int]
        let hunkToolTips: [Int: String]
        let overviewSegments: [FileInspectorOverviewSegment]
    }

    let repoPath: String
    let repoName: String
    private let git: GitService
    private let reflogLoader: RepoReflogLoader

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
    var showReflogOverlay = false {
        didSet {
            UserDefaults.standard.set(showReflogOverlay, forKey: "GitN.showReflogOverlay.\(repoPath)")
            guard !showReflogOverlay,
                  let selectedCommit,
                  !selectedCommit.isUncommitted,
                  !commits.contains(where: { $0.hash == selectedCommit.hash }) else { return }
            clearDetailSelection()
        }
    }
    var selectedReflogRef = "HEAD" {
        didSet {
            guard oldValue != selectedReflogRef else { return }
            UserDefaults.standard.set(selectedReflogRef, forKey: "GitN.selectedReflogRef.\(repoPath)")
            Task { await loadReflog() }
        }
    }
    var reflogEntries: [ReflogEntryInfo] = []
    var reflogEntriesByCommitHash: [String: [ReflogEntryInfo]] = [:]
    var reflogRecoveredCommits: [CommitInfo] = []
    var reflogRecoveryEntriesByCommitHash: [String: [ReflogEntryInfo]] = [:]

    var graphDisplayCommits: [CommitInfo] {
        reflogState.displayCommits
    }

    // MARK: - Pagination (pull-based via CommitWalker)
    private var commitWalker: CommitWalker?
    private(set) var allCommitsLoaded = false
    private(set) var isLoadingMore = false
    private let commitPageSize = 2000

    var selectedCommit: CommitInfo?
    var selectedStash: StashInfo?
    var diffFiles: [DiffFile] = []
    var fileDiffContent: String = ""
    var diffBaseText: String = ""
    var parsedDiff: ParsedDiff?
    var selectedDiffVisualContent: VisualFileContent?
    var selectedDiffFile: DiffFile?
    var isLoadingDiff = false
    /// True when the selected file exceeds maxDiffFileSize.
    var isFileTooLarge = false
    var fileTooLargeSizeMB: String = ""
    var isFileInspectorPresented = false
    var fileInspectorMode: FileInspectorMode = .diff
    var fileInspectorContext: DiffContext = .committed
    var fileInspectorPath: String = ""
    var fileInspectorContent: String = ""
    var fileInspectorInitialContent: String = ""
    var fileInspectorDisplayContent: String = ""
    var fileInspectorDiffBaseText: String = ""
    var fileInspectorVisualContent: VisualFileContent?
    var isSavingFileInspector = false
    var isFileInspectorEditable = true
    var fileInspectorEncodingName: String?
    var fileInspectorMessage: String?
    var fileInspectorTotalLines = 1
    var fileInspectorLineHighlights: [Int: FileInspectorChangeKind] = [:]
    var fileInspectorInlineHighlights: [FileInspectorInlineHighlight] = []
    var fileInspectorLinePairs: [Int: FileInspectorLinePair] = [:]
    var fileInspectorHunkControls: [Int: Int] = [:]
    var fileInspectorHunkToolTips: [Int: String] = [:]
    var fileInspectorOverviewSegments: [FileInspectorOverviewSegment] = []
    var fileInspectorLineBlames: [Int: FileInspectorBlameInfo] = [:]
    var fileInspectorDiffDocument: DiffEditorDocument?
    var fileInspectorSelectedRange: NSRange = NSRange(location: 0, length: 0)
    var isFileInspectorDiffEditing = false
    private var fileInspectorUndoStack: [FileInspectorEditSnapshot] = []
    private var fileInspectorRedoStack: [FileInspectorEditSnapshot] = []
    private var fileInspectorEditSession: FileInspectorEditSession?
    private var fileInspectorRebuildTask: Task<Void, Never>?
    private var fileInspectorBlameTask: Task<Void, Never>?
    private var committedDiffStatsTask: Task<Void, Never>?
    private var fileInspectorPreparedEditKeepsRenderedDiff = false
    private var fileInspectorBlameCache: [String: [Int: FileInspectorBlameInfo]] = [:]
    private static let fileInspectorEditGroupingInterval: TimeInterval = 0.8
    private static let fileInspectorRebuildDebounceInterval: UInt64 = 120_000_000

    var fileStatuses: [FileStatus] = []
    var isStageOperationInProgress = false
    var selectedFilePaths: Set<String> = []
    var selectedFileListContext: DiffContext?
    /// Anchor path for Shift+click range selection .
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

    var fileInspectorTitle: String {
        return (activeFileInspectorPath as NSString).lastPathComponent
    }

    var activeFileInspectorPath: String {
        if fileInspectorMode == .history, !fileHistoryPath.isEmpty {
            return fileHistoryPath
        }
        return fileInspectorPath
    }

    var isFileInspectorDirty: Bool {
        return isFileInspectorEditable && fileInspectorContent != fileInspectorInitialContent
    }

    func openFileInspector(
        _ file: DiffFile,
        context: DiffContext = .committed,
        preferredMode: FileInspectorMode = .diff
    ) async {
        await selectDiffFile(file, context: context)
        do {
            let loaded = try await loadInspectableFileContent(path: file.path, context: context)
            let loadedText = loaded.content.text ?? ""
            let canEditInspectorContent = loaded.isEditable && (
                context != .committed || selectedCommit?.isUncommitted == true || isInConflict
            )
            let inspectorDisplayContent: String
            let inspectorBaseText: String
            let usesRawDiffFallback = preferredMode == .diff && parsedDiff == nil
            let inspectorParsedDiff: ParsedDiff?
            if usesRawDiffFallback {
                let fallbackText = fileDiffContent.isEmpty ? loadedText : fileDiffContent
                let compactSubmoduleDiff = Self.compactSubmoduleDiff(fallbackText)
                inspectorDisplayContent = compactSubmoduleDiff?.baseText ?? Self.displayTextForRawDiffFallback(fallbackText)
                inspectorBaseText = compactSubmoduleDiff?.baseText ?? inspectorDisplayContent
                inspectorParsedDiff = compactSubmoduleDiff?.parsedDiff
            } else {
                inspectorDisplayContent = loadedText
                inspectorParsedDiff = preferredMode == .diff ? parsedDiff : nil
                inspectorBaseText = if let inspectorParsedDiff, preferredMode == .diff {
                    diffBaseText.isEmpty
                        ? Self.reconstructOldText(from: inspectorParsedDiff, newText: loadedText)
                        : diffBaseText
                } else {
                    inspectorDisplayContent
                }
            }
            fileInspectorPath = file.path
            fileInspectorContext = context
            fileInspectorContent = loadedText
            fileInspectorInitialContent = loadedText
            fileInspectorDiffBaseText = inspectorBaseText
            fileInspectorDisplayContent = inspectorDisplayContent
            fileInspectorVisualContent = preferredMode == .diff ? payloadVisualContent(for: inspectorParsedDiff) : loaded.visualContent
            fileInspectorSelectedRange = NSRange(location: 0, length: 0)
            isFileInspectorDiffEditing = false
            fileInspectorUndoStack.removeAll(keepingCapacity: false)
            fileInspectorRedoStack.removeAll(keepingCapacity: false)
            fileInspectorEditSession = nil
            fileInspectorRebuildTask?.cancel()
            fileInspectorRebuildTask = nil
            fileInspectorBlameTask?.cancel()
            fileInspectorBlameTask = nil
            isFileInspectorEditable = canEditInspectorContent
            fileInspectorEncodingName = loaded.content.encodingName
            fileInspectorMessage = loaded.message
            fileInspectorMode = preferredMode
            isFileInspectorPresented = true
            rebuildFileInspectorArtifacts(
                diffBaseText: fileInspectorDiffBaseText,
                currentText: fileInspectorContent,
                parsedDiff: inspectorParsedDiff
            )
        } catch {
            showToast(title: "Failed to open file", detail: error.localizedDescription, style: .error)
        }
    }

    func openFilePreview(path: String, context: DiffContext = .committed) async {
        let file = diffFiles.first(where: { $0.path == path }) ?? DiffFile(additions: 0, deletions: 0, path: path, changeKind: .unknown)
        await openFileInspector(file, context: context, preferredMode: .preview)
    }

    func closeFileInspector() {
        isFileInspectorPresented = false
        isFileInspectorDiffEditing = false
        fileInspectorVisualContent = nil
        fileInspectorUndoStack.removeAll(keepingCapacity: false)
        fileInspectorRedoStack.removeAll(keepingCapacity: false)
        fileInspectorEditSession = nil
        fileInspectorRebuildTask?.cancel()
        fileInspectorRebuildTask = nil
        fileInspectorBlameTask?.cancel()
        fileInspectorBlameTask = nil
        fileInspectorLineBlames = [:]
        closeFileHistory()
    }

    private func clearDetailSelection() {
        invalidateCommittedDiffLoading()
        closeFileInspector()
        selectedCommit = nil
        selectedStash = nil
        selectedDiffFile = nil
        fileDiffContent = ""
        diffBaseText = ""
        parsedDiff = nil
        selectedDiffVisualContent = nil
        selectedFilePaths = []
        selectedFileListContext = nil
    }

    func setFileInspectorMode(_ mode: FileInspectorMode) async {
        guard mode != fileInspectorMode || mode == .history else { return }
        if mode == .history {
            guard !fileInspectorPath.isEmpty else { return }
            await openFileHistory(path: fileInspectorPath, context: fileInspectorContext)
            return
        }
        if fileInspectorMode == .history {
            let file = diffFiles.first(where: { $0.path == fileInspectorPath })
                ?? DiffFile(additions: 0, deletions: 0, path: fileInspectorPath, changeKind: .unknown)
            await openFileInspector(file, context: fileInspectorContext, preferredMode: mode)
            return
        }
        fileInspectorMode = mode
        if mode != .diff {
            isFileInspectorDiffEditing = false
        }
        fileInspectorVisualContent = mode == .diff ? selectedDiffVisualContent : fileInspectorVisualContent
        rebuildFileInspectorArtifacts(
            diffBaseText: fileInspectorDiffBaseText,
            currentText: fileInspectorContent,
            parsedDiff: mode == .diff ? parsedDiff : nil
        )
    }

    func saveFileInspector() async -> Bool {
        guard !fileInspectorPath.isEmpty, !isSavingFileInspector, isFileInspectorEditable else { return false }
        isSavingFileInspector = true
        defer { isSavingFileInspector = false }

        do {
            try await git.saveWorkingTreeFile(path: fileInspectorPath, content: fileInspectorContent)
            fileInspectorInitialContent = fileInspectorContent
            isFileInspectorDiffEditing = false
            fileInspectorEditSession = nil
            fileInspectorRebuildTask?.cancel()
            fileInspectorRebuildTask = nil
            fileInspectorBlameTask?.cancel()
            fileInspectorBlameTask = nil
            await refreshAfterPatchAction()
            showToast(title: "Saved", detail: fileInspectorPath, style: .success)
            return true
        } catch {
            showToast(title: "Save Failed", detail: error.localizedDescription, style: .error)
            return false
        }
    }

    private struct LoadedInspectableContent {
        let content: GitService.DecodedFileContent
        let isEditable: Bool
        let message: String?
        let visualContent: VisualFileContent?
    }

    static func monacoLanguage(for language: SourceLanguage) -> String {
        switch language {
        case .swift, .python, .javascript, .typescript, .go, .rust, .c, .cpp, .java,
             .json, .yaml, .dart, .ruby, .php, .css, .html, .xml:
            return language.rawValue
        case .shell:
            return "shellscript"
        case .kotlin, .toml:
            return "plaintext"
        case .text:
            return "plaintext"
        }
    }

    private func loadInspectableFileContent(path: String, context: DiffContext) async throws -> LoadedInspectableContent {
        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        if context == .committed, let commit = selectedCommit, !commit.isUncommitted {
            if FileManager.default.fileExists(atPath: fullPath), await git.isDirectory(path: path) {
                let text = try await submoduleDisplayText(path: path)
                return LoadedInspectableContent(
                    content: .init(text: text, encodingName: "Submodule", isBinary: false),
                    isEditable: false,
                    message: "Submodule pointers are shown as commit values and can't be edited here.",
                    visualContent: nil
                )
            }
            let decoded = try await git.decodedFileContent(atCommit: commit.hash, path: path)
            let data = try await loadPreviewData(path: path, context: context)
            return LoadedInspectableContent(
                content: decoded,
                isEditable: decoded.text != nil,
                message: decoded.isBinary ? "Binary files can't be edited here." : nil,
                visualContent: visualContent(for: path, decoded: decoded, currentData: data)
            )
        }
        if FileManager.default.fileExists(atPath: fullPath) {
            if await git.isDirectory(path: path) {
                let text = try await submoduleDisplayText(path: path)
                return LoadedInspectableContent(
                    content: .init(text: text, encodingName: "Submodule", isBinary: false),
                    isEditable: false,
                    message: "Submodule pointers are shown as commit values and can't be edited here.",
                    visualContent: nil
                )
            }
            let decoded: GitService.DecodedFileContent
            switch context {
            case .staged:
                decoded = try await git.decodedStagedFileContent(path: path)
            case .unstaged, .committed:
                decoded = try await git.decodedWorkingTreeFileContent(path: path)
            }
            let data = try await loadPreviewData(path: path, context: context)
            return LoadedInspectableContent(
                content: decoded,
                isEditable: decoded.text != nil,
                message: decoded.isBinary ? "Binary files can't be edited here." : nil,
                visualContent: visualContent(for: path, decoded: decoded, currentData: data)
            )
        }
        return LoadedInspectableContent(
            content: .init(text: "", encodingName: "UTF-8", isBinary: false),
            isEditable: true,
            message: nil,
            visualContent: nil
        )
    }

    private func submoduleDisplayText(path: String) async throws -> String {
        let summary = Self.parseSubmoduleDiffSummary(fileDiffContent)
        var lines = ["Submodule", "path: \(path)"]

        if let old = summary.old {
            lines.append("old: \(old)")
        }
        if let new = summary.new {
            lines.append("new: \(new)")
        }

        if summary.old == nil && summary.new == nil {
            if let commit = selectedCommit, !commit.isUncommitted,
               let oid = try await git.treeEntryOID(atCommit: commit.hash, path: path) {
                lines.append("commit: \(oid)")
            } else if let status = try await git.submoduleStatus(path: path) {
                lines.append("status: \(status)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated static func parseSubmoduleDiffSummary(_ diff: String) -> (old: String?, new: String?) {
        var oldCommit: String?
        var newCommit: String?

        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("-Subproject commit ") {
                oldCommit = String(line.dropFirst("-Subproject commit ".count))
            } else if line.hasPrefix("+Subproject commit ") {
                newCommit = String(line.dropFirst("+Subproject commit ".count))
            }
        }

        return (oldCommit, newCommit)
    }

    private nonisolated static func displayTextForRawDiffFallback(_ diff: String) -> String {
        let lines = diff.components(separatedBy: "\n")
        let submoduleLines = lines.filter {
            $0.hasPrefix("-Subproject commit ") || $0.hasPrefix("+Subproject commit ")
        }
        if !submoduleLines.isEmpty {
            return submoduleLines.joined(separator: "\n")
        }
        return diff
    }

    private nonisolated static func compactSubmoduleDiff(_ diff: String) -> (baseText: String, parsedDiff: ParsedDiff)? {
        let lines = diff.components(separatedBy: "\n")
        let keptLines = lines.filter {
            $0.hasPrefix("-Subproject commit ") || $0.hasPrefix("+Subproject commit ")
        }
        guard !keptLines.isEmpty else { return nil }

        let compactPatch = """
@@ -1 +1 @@
\(keptLines.joined(separator: "\n"))
"""
        let baseText = keptLines.last.map { String($0.dropFirst()) } ?? ""
        return (baseText, DiffParserEngine.parse(compactPatch))
    }

    private func visualContent(
        for path: String,
        decoded: GitService.DecodedFileContent,
        currentData: Data?
    ) -> VisualFileContent? {
        guard decoded.text == nil else { return nil }
        if path.isImageFile, let currentData, NSImage(data: currentData) != nil {
            return VisualFileContent(kind: .image, oldData: nil, newData: currentData, message: nil)
        }
        if decoded.isBinary {
            return VisualFileContent(
                kind: .binary,
                oldData: nil,
                newData: currentData,
                message: "This binary file can't be rendered as text."
            )
        }
        return nil
    }

    private func loadPreviewData(path: String, context: DiffContext) async throws -> Data? {
        if let commit = selectedCommit, !commit.isUncommitted, context == .committed {
            return try await git.fileData(atCommit: commit.hash, path: path)
        }

        switch context {
        case .staged:
            return try await git.stagedFileData(path: path)
        case .unstaged, .committed:
            return try await git.workingTreeFileData(path: path)
        }
    }

    private nonisolated static func makeVisualDiffContent(
        path: String,
        oldData: Data?,
        newData: Data?
    ) -> VisualFileContent? {
        let hasRenderableImage = path.isImageFile && [oldData, newData].contains { data in
            guard let data else { return false }
            return NSImage(data: data) != nil
        }

        if hasRenderableImage {
            return VisualFileContent(kind: .image, oldData: oldData, newData: newData, message: nil)
        }

        if oldData != nil || newData != nil {
            return VisualFileContent(
                kind: .binary,
                oldData: oldData,
                newData: newData,
                message: "This binary file can't be rendered as text."
            )
        }

        return nil
    }

    private func payloadVisualContent(for parsedDiff: ParsedDiff?) -> VisualFileContent? {
        guard parsedDiff == nil else { return nil }
        return selectedDiffVisualContent
    }

    private func rebuildFileInspectorArtifacts(
        diffBaseText: String,
        currentText: String,
        parsedDiff: ParsedDiff? = nil
    ) {
        let artifacts = Self.buildFileInspectorArtifacts(
            parsedDiff: parsedDiff,
            diffBaseText: diffBaseText,
            currentText: currentText
        )
        fileInspectorDiffDocument = artifacts.diffEditorDocument
        fileInspectorDisplayContent = artifacts.renderedText
        fileInspectorTotalLines = artifacts.totalLines
        fileInspectorLineHighlights = artifacts.lineHighlights
        fileInspectorInlineHighlights = artifacts.inlineHighlights
        fileInspectorLinePairs = artifacts.linePairs
        fileInspectorHunkControls = artifacts.hunkControls
        fileInspectorHunkToolTips = artifacts.hunkToolTips
        fileInspectorOverviewSegments = artifacts.overviewSegments
        refreshFileInspectorLineBlames()
    }

    private func refreshFileInspectorLineBlames() {
        fileInspectorBlameTask?.cancel()

        guard fileInspectorMode == .diff,
              let file = selectedDiffFile,
              !fileInspectorLinePairs.isEmpty else {
            fileInspectorLineBlames = [:]
            return
        }

        let linePairs = fileInspectorLinePairs
        let lineHighlights = fileInspectorLineHighlights
        let context = currentDiffContext
        let selectedCommit = selectedCommit
        let cacheSnapshot = fileInspectorBlameCache
        let git = git

        fileInspectorBlameTask = Task { [weak self] in
            guard let self else { return }

            enum BlameSource {
                case revision(path: String, revision: String)
                case marker(RepoViewModel.FileInspectorBlameInfo)
                case unavailable
            }

            func makeMarker(author: String, summary: String) -> RepoViewModel.FileInspectorBlameInfo {
                RepoViewModel.FileInspectorBlameInfo(
                    author: author,
                    date: "",
                    shortCommitHash: "",
                    summary: summary
                )
            }

            let newSource: BlameSource
            let oldSource: BlameSource

            if let commit = selectedCommit, !commit.isUncommitted {
                newSource = .revision(path: file.path, revision: commit.hash)
                if let parentHash = commit.parentHashes.first {
                    oldSource = .revision(path: file.oldPath ?? file.path, revision: parentHash)
                } else {
                    oldSource = .marker(makeMarker(author: "Initial commit", summary: "No parent revision"))
                }
            } else {
                oldSource = .revision(path: file.oldPath ?? file.path, revision: "HEAD")
                switch context {
                case .staged:
                    newSource = .marker(makeMarker(author: "Staged change", summary: "Not committed yet"))
                case .unstaged, .committed:
                    newSource = .marker(makeMarker(author: "Uncommitted change", summary: "Not committed yet"))
                }
            }

            var cache = cacheSnapshot

            func loadBlames(for source: BlameSource) async -> [Int: RepoViewModel.FileInspectorBlameInfo] {
                switch source {
                case .marker, .unavailable:
                    return [:]
                case let .revision(path, revision):
                    let cacheKey = "\(revision)\u{1F}\(path)"
                    if let cached = cache[cacheKey] {
                        return cached
                    }
                    do {
                        let lines = try await git.blameLines(at: revision, path: path)
                        let mapped = Dictionary(uniqueKeysWithValues: lines.map { line, info in
                            (
                                line,
                                RepoViewModel.FileInspectorBlameInfo(
                                    author: info.author,
                                    date: info.date,
                                    shortCommitHash: info.shortCommitHash,
                                    summary: info.summary
                                )
                            )
                        })
                        cache[cacheKey] = mapped
                        return mapped
                    } catch {
                        cache[cacheKey] = [:]
                        return [:]
                    }
                }
            }

            let newBlames = await loadBlames(for: newSource)
            let oldBlames = await loadBlames(for: oldSource)

            var resolved: [Int: RepoViewModel.FileInspectorBlameInfo] = [:]
            for line in linePairs.keys.sorted() {
                let pair = linePairs[line]
                let highlight = lineHighlights[line]
                let blame: RepoViewModel.FileInspectorBlameInfo?

                switch highlight {
                case .deletion:
                    blame = pair?.old.flatMap { oldLine in
                        switch oldSource {
                        case let .marker(info): return info
                        case .unavailable: return nil
                        case .revision: return oldBlames[oldLine]
                        }
                    }
                case .addition:
                    blame = pair?.new.flatMap { newLine in
                        switch newSource {
                        case let .marker(info): return info
                        case .unavailable: return nil
                        case .revision: return newBlames[newLine]
                        }
                    } ?? {
                        switch newSource {
                        case let .marker(info): return info
                        case .unavailable, .revision: return nil
                        }
                    }()
                case nil:
                    if let commit = selectedCommit, !commit.isUncommitted {
                        blame = pair?.new.flatMap { newBlames[$0] }
                    } else {
                        blame = pair?.old.flatMap { oldBlames[$0] }
                    }
                }

                if let blame, !blame.toolTipText.isEmpty {
                    resolved[line] = blame
                }
            }

            guard !Task.isCancelled else { return }
            self.fileInspectorBlameCache = cache
            self.fileInspectorLineBlames = resolved
        }
    }

    private nonisolated static func buildFileInspectorArtifacts(
        parsedDiff: ParsedDiff?,
        diffBaseText: String,
        currentText: String
    ) -> FileInspectorArtifacts {
        let currentLines = textLines(currentText)
        let normalizedTotalLines = max(currentLines.count, 1)
        let effectiveDiff = parsedDiff.map { _ in TextDiffEngine.diff(old: diffBaseText, new: currentText) }
        let lineRangesInCurrentText = lineContentRanges(for: currentLines)

        guard let diff = effectiveDiff ?? parsedDiff else {
            let rows = currentLines.enumerated().map { index, line in
                DiffEditorRow(
                    id: UUID(),
                    kind: .context,
                    oldLine: index + 1,
                    newLine: index + 1,
                    oldText: line,
                    newText: line,
                    isEditable: true,
                    contentRangeInNewText: lineRangesInCurrentText[index]
                )
            }
            let renderedRowRanges = lineContentRanges(for: currentLines)
            let editableRanges = Dictionary(uniqueKeysWithValues: zip(rows, renderedRowRanges).map { row, range in
                (range, row.id)
            })
            let linePairs = Dictionary(uniqueKeysWithValues: (1...normalizedTotalLines).map {
                ($0, FileInspectorLinePair(old: $0, new: $0))
            })
            return FileInspectorArtifacts(
                diffEditorDocument: DiffEditorDocument(
                    rows: rows,
                    renderedText: currentText,
                    editableRanges: editableRanges,
                    renderedRowRanges: renderedRowRanges
                ),
                renderedText: currentText,
                totalLines: normalizedTotalLines,
                lineHighlights: [:],
                inlineHighlights: [],
                linePairs: linePairs,
                hunkControls: [:],
                hunkToolTips: [:],
                overviewSegments: []
            )
        }

        var rows: [DiffEditorRow] = []
        var highlights: [Int: FileInspectorChangeKind] = [:]
        var linePairs: [Int: FileInspectorLinePair] = [:]
        var hunkControls: [Int: Int] = [:]
        var hunkToolTips: [Int: String] = [:]
        var oldLine = 1
        var newLine = 1
        var baseIndex = 1

        func appendRow(
            kind: DiffEditorRow.Kind,
            old: Int?,
            new: Int?,
            oldText: String?,
            newText: String?,
            editableRange: NSRange?
        ) {
            rows.append(
                DiffEditorRow(
                    id: UUID(),
                    kind: kind,
                    oldLine: old,
                    newLine: new,
                    oldText: oldText,
                    newText: newText,
                    isEditable: new != nil,
                    contentRangeInNewText: editableRange
                )
            )
            let rowNumber = rows.count
            linePairs[rowNumber] = FileInspectorLinePair(old: old, new: new)
            switch kind {
            case .context:
                break
            case .addition:
                highlights[rowNumber] = .addition
            case .deletion:
                highlights[rowNumber] = .deletion
            }
        }

        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            while newLine < hunk.newStart && baseIndex <= currentLines.count {
                let lineText = currentLines[baseIndex - 1]
                appendRow(
                    kind: .context,
                    old: oldLine,
                    new: newLine,
                    oldText: lineText,
                    newText: lineText,
                    editableRange: lineRangesInCurrentText[baseIndex - 1]
                )
                oldLine += 1
                newLine += 1
                baseIndex += 1
            }

            let hunkStartRow = rows.count + 1
            var firstChangedRow: Int?
            for line in hunk.lines {
                switch line.kind {
                case .context:
                    let lineText = baseIndex <= currentLines.count ? currentLines[baseIndex - 1] : line.content
                    appendRow(
                        kind: .context,
                        old: oldLine,
                        new: newLine,
                        oldText: line.content,
                        newText: lineText,
                        editableRange: baseIndex <= lineRangesInCurrentText.count ? lineRangesInCurrentText[baseIndex - 1] : nil
                    )
                    oldLine += 1
                    newLine += 1
                    baseIndex += 1
                case .addition:
                    let lineText = baseIndex <= currentLines.count ? currentLines[baseIndex - 1] : line.content
                    appendRow(
                        kind: .addition,
                        old: nil,
                        new: newLine,
                        oldText: nil,
                        newText: lineText,
                        editableRange: baseIndex <= lineRangesInCurrentText.count ? lineRangesInCurrentText[baseIndex - 1] : nil
                    )
                    if firstChangedRow == nil { firstChangedRow = rows.count }
                    newLine += 1
                    baseIndex += 1
                case .deletion:
                    appendRow(
                        kind: .deletion,
                        old: oldLine,
                        new: nil,
                        oldText: line.content,
                        newText: nil,
                        editableRange: nil
                    )
                    if firstChangedRow == nil { firstChangedRow = rows.count }
                    oldLine += 1
                }
            }
            if rows.count >= hunkStartRow {
                let anchorRow = firstChangedRow ?? hunkStartRow
                hunkControls[anchorRow] = hunkIndex
                hunkToolTips[anchorRow] = hunk.changeDisplayRange
            }
        }

        while baseIndex <= currentLines.count {
            let lineText = currentLines[baseIndex - 1]
            appendRow(
                kind: .context,
                old: oldLine,
                new: newLine,
                oldText: lineText,
                newText: lineText,
                editableRange: lineRangesInCurrentText[baseIndex - 1]
            )
            oldLine += 1
            newLine += 1
            baseIndex += 1
        }

        let renderedText = rows.map { $0.newText ?? $0.oldText ?? "" }.joined(separator: "\n")
        let renderedRowRanges = lineContentRanges(for: rows.map { $0.newText ?? $0.oldText ?? "" })
        let editableRanges = Dictionary(uniqueKeysWithValues: zip(rows, renderedRowRanges).compactMap { row, range in
            row.isEditable ? (range, row.id) : nil
        })
        let inlineHighlights = buildInlineHighlights(rows: rows, renderedRowRanges: renderedRowRanges)
        let overviewSegments = buildOverviewSegments(from: highlights)
        return FileInspectorArtifacts(
            diffEditorDocument: DiffEditorDocument(
                rows: rows,
                renderedText: renderedText,
                editableRanges: editableRanges,
                renderedRowRanges: renderedRowRanges
            ),
            renderedText: renderedText,
            totalLines: max(rows.count, 1),
            lineHighlights: highlights,
            inlineHighlights: inlineHighlights,
            linePairs: linePairs,
            hunkControls: hunkControls,
            hunkToolTips: hunkToolTips,
            overviewSegments: overviewSegments
        )
    }

    private nonisolated static func buildOverviewSegments(
        from highlights: [Int: FileInspectorChangeKind]
    ) -> [FileInspectorOverviewSegment] {
        var segments: [FileInspectorOverviewSegment] = []

        for kind in [FileInspectorChangeKind.deletion, .addition] {
            let sortedLines = highlights
                .filter { $0.value == kind }
                .map(\.key)
                .sorted()

            guard let first = sortedLines.first else { continue }

            var start = first
            var end = first
            for line in sortedLines.dropFirst() {
                if line == end + 1 {
                    end = line
                } else {
                    segments.append(FileInspectorOverviewSegment(startLine: start, endLine: end, kind: kind))
                    start = line
                    end = line
                }
            }
            segments.append(FileInspectorOverviewSegment(startLine: start, endLine: end, kind: kind))
        }

        return segments.sorted { lhs, rhs in
            if lhs.startLine == rhs.startLine {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.startLine < rhs.startLine
        }
    }

    private nonisolated static func buildInlineHighlights(
        rows: [DiffEditorRow],
        renderedRowRanges: [NSRange]
    ) -> [FileInspectorInlineHighlight] {
        guard rows.count == renderedRowRanges.count else { return [] }

        var highlights: [FileInspectorInlineHighlight] = []
        var index = 0

        while index < rows.count {
            guard rows[index].kind == .deletion else {
                index += 1
                continue
            }

            let deletionStart = index
            while index < rows.count, rows[index].kind == .deletion {
                index += 1
            }
            let deletionEnd = index

            let additionStart = index
            while index < rows.count, rows[index].kind == .addition {
                index += 1
            }
            let additionEnd = index

            guard additionStart < additionEnd else { continue }

            let pairCount = min(deletionEnd - deletionStart, additionEnd - additionStart)
            guard pairCount > 0 else { continue }

            for pairOffset in 0..<pairCount {
                let deletionIndex = deletionStart + pairOffset
                let additionIndex = additionStart + pairOffset
                guard let oldText = rows[deletionIndex].oldText,
                      let newText = rows[additionIndex].newText else {
                    continue
                }

                if let oldRange = changedUTF16Range(in: oldText, comparedTo: newText) {
                    let renderedRange = renderedRowRanges[deletionIndex]
                    highlights.append(
                        FileInspectorInlineHighlight(
                            range: NSRange(location: renderedRange.location + oldRange.location, length: oldRange.length),
                            kind: .deletion
                        )
                    )
                }

                if let newRange = changedUTF16Range(in: newText, comparedTo: oldText) {
                    let renderedRange = renderedRowRanges[additionIndex]
                    highlights.append(
                        FileInspectorInlineHighlight(
                            range: NSRange(location: renderedRange.location + newRange.location, length: newRange.length),
                            kind: .addition
                        )
                    )
                }
            }
        }

        return highlights
    }

    private nonisolated static func changedUTF16Range(in source: String, comparedTo other: String) -> NSRange? {
        guard source != other else { return nil }

        let sourceChars = Array(source)
        let otherChars = Array(other)
        var prefixLength = 0
        while prefixLength < sourceChars.count,
              prefixLength < otherChars.count,
              sourceChars[prefixLength] == otherChars[prefixLength] {
            prefixLength += 1
        }

        var sourceSuffix = sourceChars.count
        var otherSuffix = otherChars.count
        while sourceSuffix > prefixLength,
              otherSuffix > prefixLength,
              sourceChars[sourceSuffix - 1] == otherChars[otherSuffix - 1] {
            sourceSuffix -= 1
            otherSuffix -= 1
        }

        let startIndex = sourceChars.index(sourceChars.startIndex, offsetBy: prefixLength)
        let endIndex = sourceChars.index(sourceChars.startIndex, offsetBy: sourceSuffix)
        let sourceString = source as NSString
        let utf16Start = String(sourceChars[..<startIndex]).utf16.count
        let utf16Length = String(sourceChars[startIndex..<endIndex]).utf16.count

        if utf16Length > 0 {
            return NSRange(location: utf16Start, length: utf16Length)
        }

        if utf16Start <= sourceString.length {
            return NSRange(location: utf16Start, length: 0)
        }
        return nil
    }

    func prepareFileInspectorDiffEdit(affectedRange: NSRange, replacementString: String?) -> String? {
        DiffEditorDebugLog.emit(
            "prepare affectedRange=\(NSStringFromRange(affectedRange)) replacement=\(String(reflecting: replacementString)) selected=\(NSStringFromRange(fileInspectorSelectedRange)) contentLength=\((fileInspectorContent as NSString).length) displayLength=\((fileInspectorDisplayContent as NSString).length) editing=\(isFileInspectorDiffEditing)"
        )
        guard fileInspectorMode == .diff,
              isFileInspectorEditable,
              let document = fileInspectorDiffDocument,
              let newTextRange = Self.mapRenderedEditRange(affectedRange, in: document)
        else {
            DiffEditorDebugLog.emit("prepare rejected")
            return nil
        }

        fileInspectorPreparedEditKeepsRenderedDiff = Self.rowKindForRenderedLocation(
            affectedRange.location,
            in: document
        ) == .addition

        let current = fileInspectorContent as NSString
        DiffEditorDebugLog.emit(
            "prepare mappedRange=\(NSStringFromRange(newTextRange)) keepsRenderedDiff=\(fileInspectorPreparedEditKeepsRenderedDiff)"
        )
        return current.replacingCharacters(in: newTextRange, with: replacementString ?? "")
    }

    func applyPreparedFileInspectorDiffEdit(content: String, renderedSelection: NSRange) {
        DiffEditorDebugLog.emit(
            "apply renderedSelection=\(NSStringFromRange(renderedSelection)) currentSelected=\(NSStringFromRange(fileInspectorSelectedRange)) newContentLength=\((content as NSString).length) oldContentLength=\((fileInspectorContent as NSString).length)"
        )
        guard content != fileInspectorContent || renderedSelection != fileInspectorSelectedRange else { return }
        beginOrExtendFileInspectorEditSession()
        fileInspectorRedoStack.removeAll(keepingCapacity: false)
        let preEditDocument = fileInspectorDiffDocument
        let newTextSelection = preEditDocument.flatMap {
            Self.mapRenderedSelectionToNewTextSelection(renderedSelection, in: $0)
        } ?? renderedSelection
        DiffEditorDebugLog.emit(
            "apply mappedNewSelection=\(NSStringFromRange(newTextSelection)) hadDocument=\(preEditDocument != nil)"
        )
        fileInspectorContent = content
        if fileInspectorPreparedEditKeepsRenderedDiff {
            isFileInspectorDiffEditing = false
            fileInspectorSelectedRange = newTextSelection
            rebuildFileInspectorArtifacts(
                diffBaseText: fileInspectorDiffBaseText,
                currentText: fileInspectorContent,
                parsedDiff: parsedDiff
            )
            if let document = fileInspectorDiffDocument,
               let remappedSelection = Self.mapNewTextSelectionToRenderedSelection(newTextSelection, in: document) {
                fileInspectorSelectedRange = remappedSelection
                DiffEditorDebugLog.emit(
                    "apply remappedRenderedSelection=\(NSStringFromRange(remappedSelection)) after rebuild"
                )
            }
        } else {
            isFileInspectorDiffEditing = true
            fileInspectorSelectedRange = newTextSelection
            applyImmediateFileInspectorEditingArtifacts()
            scheduleFileInspectorDiffRebuild()
        }
        DiffEditorDebugLog.emit(
            "apply finalSelected=\(NSStringFromRange(fileInspectorSelectedRange)) editing=\(isFileInspectorDiffEditing) displayLength=\((fileInspectorDisplayContent as NSString).length)"
        )
        fileInspectorPreparedEditKeepsRenderedDiff = false
    }

    func restoreFileInspectorDiffState(content: String, renderedSelection: NSRange) {
        DiffEditorDebugLog.emit(
            "restore contentLength=\((content as NSString).length) renderedSelection=\(NSStringFromRange(renderedSelection))"
        )
        isFileInspectorDiffEditing = false
        fileInspectorEditSession = nil
        fileInspectorRebuildTask?.cancel()
        fileInspectorRebuildTask = nil
        fileInspectorContent = content
        fileInspectorSelectedRange = renderedSelection
        rebuildFileInspectorArtifacts(
            diffBaseText: fileInspectorDiffBaseText,
            currentText: fileInspectorContent,
            parsedDiff: parsedDiff
        )
    }

    func undoFileInspectorDiffEdit() {
        fileInspectorEditSession = nil
        guard let snapshot = fileInspectorUndoStack.popLast() else { return }
        DiffEditorDebugLog.emit(
            "undo currentSelected=\(NSStringFromRange(fileInspectorSelectedRange)) restoringSelected=\(NSStringFromRange(snapshot.selectedRange)) undoRemaining=\(fileInspectorUndoStack.count) redoCount=\(fileInspectorRedoStack.count)"
        )
        fileInspectorRedoStack.append(
            FileInspectorEditSnapshot(content: fileInspectorContent, selectedRange: fileInspectorSelectedRange)
        )
        restoreFileInspectorDiffState(content: snapshot.content, renderedSelection: snapshot.selectedRange)
    }

    func redoFileInspectorDiffEdit() {
        fileInspectorEditSession = nil
        guard let snapshot = fileInspectorRedoStack.popLast() else { return }
        DiffEditorDebugLog.emit(
            "redo currentSelected=\(NSStringFromRange(fileInspectorSelectedRange)) restoringSelected=\(NSStringFromRange(snapshot.selectedRange)) undoCount=\(fileInspectorUndoStack.count) redoRemaining=\(fileInspectorRedoStack.count)"
        )
        fileInspectorUndoStack.append(
            FileInspectorEditSnapshot(content: fileInspectorContent, selectedRange: fileInspectorSelectedRange)
        )
        restoreFileInspectorDiffState(content: snapshot.content, renderedSelection: snapshot.selectedRange)
    }

    private func beginOrExtendFileInspectorEditSession() {
        let now = Date()
        if var session = fileInspectorEditSession,
           now.timeIntervalSince(session.lastEditAt) <= Self.fileInspectorEditGroupingInterval {
            session.lastEditAt = now
            fileInspectorEditSession = session
            return
        }

        let snapshot = FileInspectorEditSnapshot(
            content: fileInspectorContent,
            selectedRange: fileInspectorSelectedRange
        )
        DiffEditorDebugLog.emit(
            "beginEditSession snapshotSelected=\(NSStringFromRange(snapshot.selectedRange)) undoCountBefore=\(fileInspectorUndoStack.count)"
        )
        fileInspectorUndoStack.append(snapshot)
        if fileInspectorUndoStack.count > 200 {
            fileInspectorUndoStack.removeFirst(fileInspectorUndoStack.count - 200)
        }
        fileInspectorEditSession = FileInspectorEditSession(
            lastEditAt: now
        )
    }

    private func applyImmediateFileInspectorEditingArtifacts() {
        let artifacts = Self.buildFileInspectorArtifacts(
            parsedDiff: nil,
            diffBaseText: fileInspectorDiffBaseText,
            currentText: fileInspectorContent
        )
        fileInspectorDiffDocument = artifacts.diffEditorDocument
        fileInspectorDisplayContent = artifacts.renderedText
        fileInspectorTotalLines = artifacts.totalLines
        fileInspectorLineHighlights = artifacts.lineHighlights
        fileInspectorInlineHighlights = artifacts.inlineHighlights
        fileInspectorLinePairs = artifacts.linePairs
        fileInspectorHunkControls = [:]
        fileInspectorHunkToolTips = [:]
        fileInspectorOverviewSegments = artifacts.overviewSegments
    }

    private func scheduleFileInspectorDiffRebuild() {
        fileInspectorRebuildTask?.cancel()
        let diffBaseText = fileInspectorDiffBaseText
        let currentText = fileInspectorContent
        let parsedDiff = parsedDiff
        let currentSelection = fileInspectorSelectedRange
        DiffEditorDebugLog.emit(
            "scheduleRebuild currentSelection=\(NSStringFromRange(currentSelection)) currentLength=\((currentText as NSString).length)"
        )
        fileInspectorRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.fileInspectorRebuildDebounceInterval)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.fileInspectorContent == currentText else { return }
            self.rebuildFileInspectorArtifacts(
                diffBaseText: diffBaseText,
                currentText: currentText,
                parsedDiff: parsedDiff
            )
            if let document = self.fileInspectorDiffDocument,
               let renderedSelection = Self.mapNewTextSelectionToRenderedSelection(currentSelection, in: document) {
                self.fileInspectorSelectedRange = renderedSelection
                DiffEditorDebugLog.emit(
                    "scheduleRebuild remappedSelection=\(NSStringFromRange(renderedSelection))"
                )
            }
            self.isFileInspectorDiffEditing = false
            self.fileInspectorRebuildTask = nil
        }
    }

    private nonisolated static func reconstructOldText(from diff: ParsedDiff, newText: String) -> String {
        let newLines = textLines(newText)
        var oldLines: [String] = []
        var newLine = 1
        var currentIndex = 1

        for hunk in diff.hunks {
            while newLine < hunk.newStart && currentIndex <= newLines.count {
                oldLines.append(newLines[currentIndex - 1])
                newLine += 1
                currentIndex += 1
            }

            for line in hunk.lines {
                switch line.kind {
                case .context:
                    oldLines.append(line.content)
                    newLine += 1
                    currentIndex += 1
                case .addition:
                    newLine += 1
                    currentIndex += 1
                case .deletion:
                    oldLines.append(line.content)
                }
            }
        }

        while currentIndex <= newLines.count {
            oldLines.append(newLines[currentIndex - 1])
            currentIndex += 1
        }

        return oldLines.joined(separator: "\n")
    }

    private nonisolated static func textLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private nonisolated static func lineContentRanges(for lines: [String]) -> [NSRange] {
        guard !lines.isEmpty else { return [NSRange(location: 0, length: 0)] }

        var ranges: [NSRange] = []
        var location = 0
        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            ranges.append(NSRange(location: location, length: length))
            location += length
            if index < lines.count - 1 {
                location += 1
            }
        }
        return ranges
    }

    private nonisolated static func mapRenderedEditRange(
        _ range: NSRange,
        in document: DiffEditorDocument
    ) -> NSRange? {
        guard isRenderedEditRangeEditable(range, in: document),
              let startLocation = mapRenderedCaretOffset(range.location, in: document),
              let endLocation = mapRenderedCaretOffset(NSMaxRange(range), in: document)
        else {
            return nil
        }

        let lowerBound = min(startLocation, endLocation)
        let upperBound = max(startLocation, endLocation)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private nonisolated static func rowKindForRenderedLocation(
        _ location: Int,
        in document: DiffEditorDocument
    ) -> DiffEditorRow.Kind? {
        for (index, renderedRange) in document.renderedRowRanges.enumerated() where index < document.rows.count {
            let rowEnd = NSMaxRange(renderedRange)
            if location >= renderedRange.location && location <= rowEnd {
                return document.rows[index].kind
            }
        }
        return nil
    }

    private nonisolated static func mapRenderedSelectionToNewTextSelection(
        _ selection: NSRange,
        in document: DiffEditorDocument
    ) -> NSRange? {
        mapRenderedEditRange(selection, in: document)
    }

    private nonisolated static func mapRenderedCaretOffset(
        _ offset: Int,
        in document: DiffEditorDocument
    ) -> Int? {
        let renderedLength = (document.renderedText as NSString).length
        let clampedOffset = min(max(offset, 0), renderedLength)

        if document.rows.isEmpty {
            return clampedOffset == 0 ? 0 : nil
        }

        for (index, row) in document.rows.enumerated() {
            let renderedRange = document.renderedRowRanges[index]
            let renderedLineStart = renderedRange.location
            let renderedLineEnd = NSMaxRange(renderedRange)

            if clampedOffset < renderedLineStart || clampedOffset > renderedLineEnd {
                continue
            }

            guard row.isEditable,
                  let contentRange = row.contentRangeInNewText else {
                return nil
            }

            return contentRange.location + (clampedOffset - renderedLineStart)
        }

        if clampedOffset == renderedLength,
           let lastRow = document.rows.last,
           lastRow.isEditable,
           let contentRange = lastRow.contentRangeInNewText {
            return NSMaxRange(contentRange)
        }

        return nil
    }

    private nonisolated static func isRenderedEditRangeEditable(
        _ range: NSRange,
        in document: DiffEditorDocument
    ) -> Bool {
        let renderedLength = (document.renderedText as NSString).length
        let clampedLocation = min(max(range.location, 0), renderedLength)
        let clampedEnd = min(max(NSMaxRange(range), 0), renderedLength)
        let normalizedRange = NSRange(location: min(clampedLocation, clampedEnd), length: abs(clampedEnd - clampedLocation))

        for (index, row) in document.rows.enumerated() {
            let renderedRange = document.renderedRowRanges[index]
            if normalizedRange.intersection(renderedRange) != nil && !row.isEditable {
                return false
            }

            let isLastRow = index == document.rows.count - 1
            guard !isLastRow else { continue }

            let newlineRange = NSRange(location: NSMaxRange(renderedRange), length: 1)
            guard normalizedRange.intersection(newlineRange) != nil else { continue }

            let nextRow = document.rows[index + 1]
            guard row.isEditable,
                  nextRow.isEditable,
                  let currentContentRange = row.contentRangeInNewText,
                  let nextContentRange = nextRow.contentRangeInNewText,
                  nextContentRange.location == NSMaxRange(currentContentRange) + 1
            else {
                return false
            }
        }

        return true
    }

    private nonisolated static func mapNewTextSelectionToRenderedSelection(
        _ selection: NSRange,
        in document: DiffEditorDocument
    ) -> NSRange? {
        guard let start = mapNewTextCaretOffset(selection.location, in: document),
              let end = mapNewTextCaretOffset(NSMaxRange(selection), in: document) else {
            return nil
        }

        let lowerBound = min(start, end)
        let upperBound = max(start, end)
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private nonisolated static func mapNewTextCaretOffset(
        _ offset: Int,
        in document: DiffEditorDocument
    ) -> Int? {
        let newTextLength = document.rows.compactMap(\.contentRangeInNewText).map { NSMaxRange($0) }.max() ?? 0
        let clampedOffset = min(max(offset, 0), newTextLength)

        for (index, row) in document.rows.enumerated() {
            guard row.isEditable,
                  let contentRange = row.contentRangeInNewText else {
                continue
            }

            if clampedOffset >= contentRange.location && clampedOffset < NSMaxRange(contentRange) {
                let renderedRange = document.renderedRowRanges[index]
                return renderedRange.location + (clampedOffset - contentRange.location)
            }

            if clampedOffset == NSMaxRange(contentRange) {
                let renderedRange = document.renderedRowRanges[index]
                return NSMaxRange(renderedRange)
            }
        }

        if clampedOffset == 0,
           let firstEditableIndex = document.rows.firstIndex(where: \.isEditable) {
            return document.renderedRowRanges[firstEditableIndex].location
        }

        return nil
    }

    private nonisolated static func lineCount(for text: String) -> Int {
        max(text.components(separatedBy: "\n").count, 1)
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
            ?? DiffFile(additions: 0, deletions: 0, path: firstStatus.path, changeKind: firstStatus.diffChangeKind)
        selectedFilePaths = [firstStatus.path]
        selectedFileListContext = .unstaged
        await selectDiffFile(diffFile, context: .unstaged)
    }

    /// - Parameters:
    ///   - path: The file path that was clicked.
    ///   - isMulti: `true` when ⌘ is held (toggle individual item).
    ///   - isRange: `true` when ⇧ is held (select range from anchor).
    ///   - orderedPaths: The full ordered list of visible paths in the
    ///     section (staged / unstaged) so we can compute the range.
    func toggleFileSelection(
        _ path: String,
        context: DiffContext,
        isMulti: Bool,
        isRange: Bool = false,
        orderedPaths: [String] = []
    ) {
        if selectedFileListContext != context {
            selectedFilePaths = []
        }
        selectedFileListContext = context

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
    var isLoadingFileHistory = false
    var fileHistoryPath: String = ""
    var fileHistoryCommits: [CommitInfo] = []
    var fileHistorySelectedCommit: CommitInfo?
    var fileHistoryDiff: String = ""
    var fileHistoryParsedDiff: ParsedDiff?

    func openFileHistory(path: String, context: DiffContext = .committed) async {
        fileInspectorPath = path
        fileInspectorContext = context
        fileInspectorMode = .history
        isFileInspectorPresented = true
        showFileHistory = false
        isLoadingFileHistory = true
        fileHistoryPath = path
        fileHistoryCommits = []
        fileHistorySelectedCommit = nil
        fileHistoryDiff = ""
        fileHistoryParsedDiff = nil
        defer { isLoadingFileHistory = false }
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
        isLoadingFileHistory = false
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
        let gitService = GitService(repoPath: path)
        self.git = gitService
        self.reflogLoader = RepoReflogLoader(git: gitService)
        // 恢复上次 terminal 的打开状态
        self.showTerminal = UserDefaults.standard.bool(forKey: "GitN.showTerminal.\(path)")
        self.showReflogOverlay = UserDefaults.standard.bool(forKey: "GitN.showReflogOverlay.\(path)")
        self.selectedReflogRef = UserDefaults.standard.string(forKey: "GitN.selectedReflogRef.\(path)") ?? "HEAD"
        loadCollapsedSections()
    }

    private func applyReflogSnapshot(_ snapshot: RepoReflogSnapshot) {
        reflogEntries = snapshot.entries
        reflogEntriesByCommitHash = snapshot.entriesByCommitHash
        reflogRecoveredCommits = snapshot.recoveredCommits
        reflogRecoveryEntriesByCommitHash = snapshot.recoveryEntriesByCommitHash
    }

    private var reflogState: RepoReflogState {
        RepoReflogState(
            currentBranch: currentBranch,
            commits: commits,
            recoveredCommits: reflogRecoveredCommits,
            visibleEntriesByCommitHash: reflogEntriesByCommitHash,
            recoveryEntriesByCommitHash: reflogRecoveryEntriesByCommitHash,
            showReflogOverlay: showReflogOverlay,
            allCommitsLoaded: allCommitsLoaded
        )
    }

    var reflogSourceOptions: [ReflogSourceOption] {
        reflogState.sourceOptions
    }

    var reflogMergedEntriesByCommitHash: [String: [ReflogEntryInfo]] {
        reflogState.mergedEntriesByCommitHash
    }

    var reflogBadgeEntriesByCommitHash: [String: [ReflogEntryInfo]] {
        reflogState.badgeEntriesByCommitHash
    }

    func reflogEntries(for commitHash: String) -> [ReflogEntryInfo] {
        reflogState.mergedEntries(for: commitHash)
    }

    func reflogBadgeEntries(for commitHash: String) -> [ReflogEntryInfo] {
        reflogState.badgeEntries(for: commitHash)
    }

    func selectRecoveredCommit(_ commit: CommitInfo) async {
        if let existing = commits.first(where: { $0.hash == commit.hash }) {
            await revealCommit(hash: existing.hash)
            return
        }
        scrollToCommitHash = commit.hash
        await selectCommit(commit)
    }

    func canNavigateToCommit(hash: String?) -> Bool {
        reflogState.canNavigateToCommit(hash: hash)
    }

    func navigateToCommit(hash: String) async {
        guard !hash.isEmpty else { return }

        if let commit = reflogState.displayCommit(matching: hash) {
            if reflogState.isRecoveredCommit(commit) {
                await selectRecoveredCommit(commit)
            } else {
                await revealCommit(hash: commit.hash)
            }
            return
        }

        await revealCommit(hash: hash)
    }

    func loadReflog() async {
        do {
            let snapshot = try await reflogLoader.load(refName: selectedReflogRef)
            applyReflogSnapshot(snapshot)
        } catch {
            applyReflogSnapshot(.empty)
        }
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
            if selectedReflogRef != "HEAD", selectedReflogRef != "refs/heads/\(cb)" {
                selectedReflogRef = "HEAD"
            }
            await loadReflog()

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
        invalidateCommittedDiffLoading()
        let committedDiffGeneration = committedDiffGeneration
        selectedCommit = commit
        selectedStash = nil
        selectedDiffFile = nil
        fileDiffContent = ""
        parsedDiff = nil
        selectedFilePaths = []
        selectedFileListContext = nil
        do {
            if commit.isUncommitted {
                refreshUncommittedDiffFiles()
                // Auto-select the first unstaged file, falling back to the first staged file
                let firstStatus = fileStatuses.first(where: \.hasUnstagedChanges)
                    ?? fileStatuses.first(where: \.hasStagedChanges)
                if let status = firstStatus {
                    let context: DiffContext = status.hasUnstagedChanges ? .unstaged : .staged
                    let diffFile = diffFiles.first(where: { $0.path == status.path })
                        ?? DiffFile(additions: 0, deletions: 0, path: status.path, changeKind: status.diffChangeKind)
                    selectedFilePaths = [status.path]
                    selectedFileListContext = context
                    await selectDiffFile(diffFile, context: context)
                }
            } else {
                diffFiles = try await git.committedDiffPreview(hash: commit.hash)
                if let first = diffFiles.first {
                    await selectDiffFile(first, context: .committed)
                }
                scheduleCommittedDiffStatsLoad(hash: commit.hash, generation: committedDiffGeneration)
            }
        } catch {
            diffFiles = []
        }
    }

    private func refreshUncommittedDiffFiles() {
        diffFiles = fileStatuses.map { status in
            DiffFile(additions: 0, deletions: 0, path: status.path, changeKind: status.diffChangeKind)
        }
    }

    enum DiffContext { case staged, unstaged, committed }
    var currentDiffContext: DiffContext = .committed
    private var diffLoadGeneration = 0
    private var committedDiffGeneration = 0

    private func invalidateCommittedDiffLoading() {
        committedDiffGeneration += 1
        committedDiffStatsTask?.cancel()
        committedDiffStatsTask = nil
    }

    private func scheduleCommittedDiffStatsLoad(hash: String, generation: Int) {
        committedDiffStatsTask?.cancel()
        committedDiffStatsTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let files: [DiffFile]
            do {
                files = try await self.git.diffDetail(hash: hash)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  generation == self.committedDiffGeneration,
                  self.selectedCommit?.hash == hash,
                  self.selectedStash == nil,
                  !self.isCompareMode
            else { return }

            self.diffFiles = files
            if let selectedPath = self.selectedDiffFile?.path,
               let updatedSelection = files.first(where: { $0.path == selectedPath }) {
                self.selectedDiffFile = updatedSelection
            }
            self.committedDiffStatsTask = nil
        }
    }

    /// Max file size (in bytes) for which we compute a full diff.
    /// Files larger than this get a placeholder to avoid OOM on huge files
    /// (e.g. Xcode project.pbxproj). Configurable via Settings (default 3 MB).
    static let maxDiffFileSizeKey = "GitN.maxDiffFileSizeMB"
    static let defaultMaxDiffFileSizeMB = 3

    static var maxDiffFileSizeMB: Int {
        let stored = UserDefaults.standard.integer(forKey: maxDiffFileSizeKey)
        return stored > 0 ? stored : defaultMaxDiffFileSizeMB
    }

    private static var maxDiffFileSize: Int {
        maxDiffFileSizeMB * 1_048_576
    }

    func selectDiffFile(_ file: DiffFile, context: DiffContext = .committed, ignoreSize: Bool = false) async {
        let isUncommitted = selectedCommit?.isUncommitted == true || isInConflict
        guard selectedCommit != nil || selectedStash != nil || isInConflict else { return }
        diffLoadGeneration += 1
        let generation = diffLoadGeneration
        selectedDiffFile = file
        currentDiffContext = context
        isLoadingDiff = true
        isFileTooLarge = false
        fileTooLargeSizeMB = ""
        fileDiffContent = ""
        parsedDiff = nil
        selectedDiffVisualContent = nil
        do {
            if isUncommitted {
                // Guard against huge files that would blow up memory
                if !ignoreSize {
                    let fullPath = (repoPath as NSString).appendingPathComponent(file.path)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int, size > Self.maxDiffFileSize {
                        let sizeMB = String(format: "%.1f", Double(size) / 1_048_576.0)
                        isFileTooLarge = true
                        fileTooLargeSizeMB = sizeMB
                        isLoadingDiff = false
                        return
                    }
                }
            }

            let path = file.path
            let statusCode = fileStatuses.first(where: { $0.path == path })?.statusCode ?? "M "
            let stashIndex = selectedStash?.index
            let commitHash = selectedCommit?.hash
            let parentCommitHash = selectedCommit?.parentHashes.first
            let oldPath = file.oldPath
            let git = self.git
            let payloadTask = Task.detached(priority: .userInitiated) { () throws -> DiffLoadPayload in
                try await Self.loadDiffPayload(
                    git: git,
                    path: path,
                    oldPath: oldPath,
                    context: context,
                    isUncommitted: isUncommitted,
                    stashIndex: stashIndex,
                    commitHash: commitHash,
                    parentCommitHash: parentCommitHash,
                    statusCode: statusCode
                )
            }
            let payload = try await payloadTask.value

            guard generation == diffLoadGeneration,
                  selectedDiffFile?.path == path,
                  currentDiffContext == context
            else { return }

            fileDiffContent = payload.fileDiffContent
            diffBaseText = payload.baseText
            parsedDiff = payload.parsedDiff
            selectedDiffVisualContent = payload.visualContent
            MonacoDebugLog.emit(
                "selectDiffFile path=\(path) context=\(String(describing: context)) status=\(statusCode) baseLines=\(Self.lineCount(for: payload.baseText)) modifiedLines=\(Self.lineCount(for: fileInspectorPath == path && isFileInspectorPresented ? fileInspectorContent : "")) parsedHunks=\(payload.parsedDiff?.hunks.count ?? 0) diffBytes=\(payload.fileDiffContent.utf8.count)"
            )
            if isFileInspectorPresented, fileInspectorPath == path {
                fileInspectorDiffBaseText = payload.parsedDiff != nil ? payload.baseText : fileInspectorContent
                fileInspectorVisualContent = fileInspectorMode == .diff ? payload.visualContent : fileInspectorVisualContent
                rebuildFileInspectorArtifacts(
                    diffBaseText: fileInspectorDiffBaseText,
                    currentText: fileInspectorContent,
                    parsedDiff: fileInspectorMode == .diff ? payload.parsedDiff : nil
                )
            }
        } catch {
            guard generation == diffLoadGeneration,
                  selectedDiffFile?.path == file.path
            else { return }
            fileDiffContent = "Failed to load diff"
            diffBaseText = ""
            parsedDiff = nil
            selectedDiffVisualContent = nil
        }
        if generation == diffLoadGeneration {
            isLoadingDiff = false
        }
    }

    private static func loadDiffPayload(
        git: GitService,
        path: String,
        oldPath: String?,
        context: DiffContext,
        isUncommitted: Bool,
        stashIndex: String?,
        commitHash: String?,
        parentCommitHash: String?,
        statusCode: String
    ) async throws -> DiffLoadPayload {
        let content: String
        let baseText: String
        let newTextForFallback: String?
        let oldBinaryData: Data?
        let newBinaryData: Data?

        let isStaged = {
            let idx = statusCode.first ?? " "
            return idx != " " && idx != "?"
        }()
        let priorPath = oldPath ?? path

        if let stashIndex {
            content = try await git.stashFileDiff(stashIndex, path: path)
            baseText = ""
            newTextForFallback = nil
            oldBinaryData = nil
            newBinaryData = nil
        } else if isUncommitted {
            switch context {
            case .staged:
                content = try await git.stagedFileDiff(path: path)
                baseText = try await git.headFileContent(path: path)
                newTextForFallback = try await git.stagedFileContent(path: path)
                oldBinaryData = try await git.headFileData(path: priorPath)
                newBinaryData = try await git.stagedFileData(path: path)
            case .unstaged:
                if statusCode == "??" {
                    content = try await git.readFullFileContent(path: path)
                    baseText = ""
                } else {
                    content = try await git.unstagedFileDiff(path: path)
                    baseText = try await git.stagedFileContent(path: path)
                }
                newTextForFallback = try await git.workingTreeFileContent(path: path)
                oldBinaryData = statusCode == "??" ? nil : try await git.stagedFileData(path: priorPath)
                newBinaryData = try await git.workingTreeFileData(path: path)
            case .committed:
                content = try await git.uncommittedFileDiff(path: path, statusCode: statusCode)
                if statusCode == "??" {
                    baseText = ""
                } else {
                    baseText = try await git.headFileContent(path: path)
                }
                if isStaged {
                    newTextForFallback = try await git.workingTreeFileContent(path: path)
                } else if statusCode == "??" {
                    newTextForFallback = try await git.workingTreeFileContent(path: path)
                } else {
                    newTextForFallback = try await git.workingTreeFileContent(path: path)
                }
                oldBinaryData = statusCode == "??" ? nil : try await git.headFileData(path: priorPath)
                newBinaryData = try await git.workingTreeFileData(path: path)
            }
        } else if let commitHash {
            content = try await git.fileDiff(hash: commitHash, path: path)
            baseText = ""
            newTextForFallback = nil
            newBinaryData = try await git.fileData(atCommit: commitHash, path: path)
            oldBinaryData = if let parentCommitHash {
                try await git.fileData(atCommit: parentCommitHash, path: priorPath)
            } else {
                nil
            }
        } else {
            return DiffLoadPayload(fileDiffContent: "", baseText: "", parsedDiff: nil, visualContent: nil)
        }

        if content.isEmpty {
            let visualContent = Self.makeVisualDiffContent(path: path, oldData: oldBinaryData, newData: newBinaryData)
            if visualContent != nil {
                return DiffLoadPayload(
                    fileDiffContent: "No changes in this file",
                    baseText: baseText,
                    parsedDiff: nil,
                    visualContent: visualContent
                )
            }
            if let newTextForFallback, !baseText.isEmpty || !newTextForFallback.isEmpty {
                let synthetic = TextDiffEngine.diff(old: baseText, new: newTextForFallback)
                if !synthetic.hunks.isEmpty {
                    return DiffLoadPayload(
                        fileDiffContent: "No changes in this file",
                        baseText: baseText,
                        parsedDiff: synthetic,
                        visualContent: nil
                    )
                }
            }
            return DiffLoadPayload(
                fileDiffContent: "No changes in this file",
                baseText: baseText,
                parsedDiff: nil,
                visualContent: nil
            )
        }

        let parsed = DiffParserEngine.parse(content)
        if parsed.hunks.isEmpty, let newTextForFallback {
            let synthetic = TextDiffEngine.diff(old: baseText, new: newTextForFallback)
            if !synthetic.hunks.isEmpty {
                MonacoDebugLog.emit(
                    "synthetic diff path=\(path) context=\(String(describing: context)) status=\(statusCode) baseLines=\(lineCount(for: baseText)) modifiedLines=\(lineCount(for: newTextForFallback)) hunks=\(synthetic.hunks.count)"
                )
                return DiffLoadPayload(fileDiffContent: content, baseText: baseText, parsedDiff: synthetic, visualContent: nil)
            }
        }
        let visualContent = parsed.hunks.isEmpty ? Self.makeVisualDiffContent(path: path, oldData: oldBinaryData, newData: newBinaryData) : nil
        return DiffLoadPayload(
            fileDiffContent: content,
            baseText: baseText,
            parsedDiff: parsed.hunks.isEmpty ? nil : parsed,
            visualContent: visualContent
        )
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
            clearDetailSelection()
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

    func unstageHunk(_ hunkIndex: Int) async {
        guard let diff = parsedDiff, let file = selectedDiffFile else { return }
        if diff.isNewFile {
            await unstageFile(file.path)
        } else {
            let patch = diff.patchForHunk(hunkIndex)
            guard !patch.isEmpty else { return }
            do {
                try await git.applyPatch(patch, cached: true, reverse: true)
            } catch { print("Unstage hunk failed: \(error)"); return }
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

    enum ToolbarOperation {
        case fetch
        case pull
        case push
    }

    var activeToolbarOperation: ToolbarOperation?

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
        await performRemoteOperation(toolbarOperation: .fetch) { try await $0.git.fetch() }
    }

    /// Execute pull using the current default mode.
    func performPull() async {
        await performPull(mode: defaultPullMode)
    }

    func performPull(mode: PullMode) async {
        activeToolbarOperation = .pull
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .pull {
                activeToolbarOperation = nil
            }
        }
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
    }

    func performForcePull() async {
        activeToolbarOperation = .pull
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .pull {
                activeToolbarOperation = nil
            }
        }
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
        activeToolbarOperation = .push
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .push {
                activeToolbarOperation = nil
            }
        }
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
    }

    func performForcePush() async {
        activeToolbarOperation = .push
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .push {
                activeToolbarOperation = nil
            }
        }
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
    }

    func performPushWithUpstream(remote: String, branch: String) async {
        showPushUpstreamPrompt = false
        activeToolbarOperation = .push
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .push {
                activeToolbarOperation = nil
            }
        }
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
    }

    func cancelPushUpstreamPrompt() {
        showPushUpstreamPrompt = false
    }

    func performStashSave(message: String? = nil) async {
        await performRemoteOperation { try await $0.git.stashSave(message: message) }
    }

    func performStashPop() async {
        activeToolbarOperation = .pull
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == .pull {
                activeToolbarOperation = nil
            }
        }
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
        let selectedCommitIndex = commits.firstIndex(where: { $0.hash == hash })
        let previouslySelectedFilePath = selectedDiffFile?.path
        let previousDiffContext = currentDiffContext

        operationInProgress = true
        operationError = nil
        defer { operationInProgress = false }

        do {
            if hash == headCommitHash {
                try await git.amendCommitMessage(newMessage)
            } else {
                // Non-HEAD commit: use interactive rebase to reword.
                try await git.rewordCommitMessage(hash: hash, newMessage: newMessage)
            }

            await loadAll()

            let rewrittenCommit: CommitInfo? = {
                if let selectedCommitIndex, commits.indices.contains(selectedCommitIndex) {
                    let commit = commits[selectedCommitIndex]
                    if !commit.isUncommitted {
                        return commit
                    }
                }
                if let hash = headCommitHash {
                    return commits.first(where: { $0.hash == hash })
                }
                return nil
            }()

            if let rewrittenCommit {
                scrollToCommitHash = rewrittenCommit.hash
                await selectCommit(rewrittenCommit)
                if previousDiffContext == .committed,
                   let previouslySelectedFilePath,
                   let file = diffFiles.first(where: { $0.path == previouslySelectedFilePath }) {
                    await selectDiffFile(file, context: .committed)
                }
            }

            showToast(title: "Message Updated", style: .success)
        } catch {
            await checkForRebaseConflict(errorMessage: error.localizedDescription)
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
        invalidateCommittedDiffLoading()
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
        invalidateCommittedDiffLoading()
        isCompareMode = false
        compareBaseHash = nil
        diffFiles = []
        fileDiffContent = ""
        parsedDiff = nil
        selectedDiffFile = nil
    }

    private func revealCommit(hash: String) async {
        scrollToCommitHash = hash

        if let commit = commits.first(where: { $0.hash == hash || $0.hash.hasPrefix(hash) || hash.hasPrefix($0.hash) }) {
            await selectCommit(commit)
            return
        }

        while !allCommitsLoaded {
            await loadMoreCommits()
            if let commit = commits.first(where: { $0.hash == hash || $0.hash.hasPrefix(hash) || hash.hasPrefix($0.hash) }) {
                scrollToCommitHash = commit.hash
                await selectCommit(commit)
                return
            }
        }
    }

    func scrollToCommitForBranch(_ branch: BranchInfo) async {
        if let commit = commits.first(where: { $0.shortHash == branch.shortHash || $0.hash.hasPrefix(branch.shortHash) }) {
            await revealCommit(hash: commit.hash)
            return
        }

        do {
            let fullHash = try await git.branchCommitHash(branch.name, isRemote: branch.isRemote)
            await revealCommit(hash: fullHash)
        } catch {}
    }

    func scrollToCommitForTag(_ tagName: String) async {
        // 查找 refs 中包含该 tag 的 commit
        if let commit = commits.first(where: { commit in
            commit.refs.contains { ref in
                ref.contains("tag:") && ref.contains(tagName)
            }
        }) {
            await revealCommit(hash: commit.hash)
            return
        }

        do {
            let fullHash = try await git.tagCommitHash(name: tagName)
            await revealCommit(hash: fullHash)
        } catch {}
    }
    
    func scrollToCommitForStash(_ stash: StashInfo) async {
        await selectStash(stash)
    }
    
    func selectStash(_ stash: StashInfo) async {
        if isCompareMode { exitCompareMode() }
        invalidateCommittedDiffLoading()
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

    private func performRemoteOperation(
        toolbarOperation: ToolbarOperation? = nil,
        _ op: @escaping (RepoViewModel) async throws -> Void
    ) async {
        activeToolbarOperation = toolbarOperation
        operationInProgress = true
        operationError = nil
        defer {
            operationInProgress = false
            if activeToolbarOperation == toolbarOperation {
                activeToolbarOperation = nil
            }
        }
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
            } else {
                operationError = errorMessage
            }
        } catch {
            operationError = errorMessage
        }
        // Always refresh after any failed stash/merge operation so the file list
        // reflects whatever partial state libgit2 left in the working directory.
        await loadAll()
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

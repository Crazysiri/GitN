import SwiftUI
import AppKit

enum SourceLanguage: String {
    case swift, python, javascript, typescript, go, rust, c, cpp, java, shell
    case json, yaml, dart, kotlin, ruby, php, css, html, xml, toml, markdown, text

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .go: return "Go"
        case .rust: return "Rust"
        case .c: return "C"
        case .cpp: return "C++"
        case .java: return "Java"
        case .shell: return "Shell"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .dart: return "Dart"
        case .kotlin: return "Kotlin"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .css: return "CSS"
        case .html: return "HTML"
        case .xml: return "XML"
        case .toml: return "TOML"
        case .markdown: return "Markdown"
        case .text: return "Plain Text"
        }
    }
}

extension String {
    var isPreviewableFile: Bool { true }

    var sourceLanguage: SourceLanguage {
        let ext = (self as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "py": return .python
        case "js", "mjs", "cjs": return .javascript
        case "ts", "tsx", "jsx": return .typescript
        case "go": return .go
        case "rs": return .rust
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "java": return .java
        case "sh", "bash", "zsh", "fish": return .shell
        case "json", "jsonc": return .json
        case "yml", "yaml": return .yaml
        case "md", "markdown": return .markdown
        case "dart": return .dart
        case "kt", "kts": return .kotlin
        case "rb", "rake", "gemspec": return .ruby
        case "php": return .php
        case "css", "scss", "sass", "less": return .css
        case "html", "htm", "xhtml": return .html
        case "xml", "plist", "svg": return .xml
        case "toml": return .toml
        default: return .text
        }
    }
}

struct FileInspectorOverlayView: View {
    private struct PendingHunkAction {
        let path: String
        let hunkIndex: Int
        let lineIDs: [Int]
        let action: String
    }

    @Environment(\.colorScheme) private var colorScheme
    let viewModel: RepoViewModel

    private var inspectorSourceIdentity: String {
        let revision = viewModel.selectedCommit?.hash ?? viewModel.selectedStash?.oid ?? "working"
        return "\(viewModel.repoPath)|\(viewModel.fileInspectorContext)|\(revision)"
    }

    @State private var targetLine: Int?
    @State private var showCloseConfirmation = false
    @State private var pendingModeSwitch: RepoViewModel.FileInspectorMode?
    @State private var pendingHunkAction: PendingHunkAction?
    @State private var showDiscardHunkConfirm = false
    @State private var commandBridge = MonacoCommandBridge()

    private var supportsHunkActions: Bool {
        viewModel.fileInspectorMode == .diff &&
        !viewModel.isFileInspectorDiffEditing &&
        !viewModel.isFileInspectorDirty &&
        (viewModel.currentDiffContext == .staged || viewModel.currentDiffContext == .unstaged)
    }

    private var primaryHunkAction: String? {
        switch viewModel.currentDiffContext {
        case .staged:
            return "unstage"
        case .unstaged:
            return "stage"
        case .committed:
            return nil
        }
    }

    private var monacoHunkControls: [MonacoDiffHunkControlPayload] {
        guard supportsHunkActions else { return [] }

        return viewModel.fileInspectorHunkControls.keys.sorted().compactMap { row in
            guard let control = viewModel.fileInspectorHunkControls[row] else { return nil }
            let linePair = viewModel.fileInspectorLinePairs[row]
            return MonacoDiffHunkControlPayload(
                row: row,
                hunkIndex: control.actionHunkIndex,
                lineIDs: control.actionLineIDs,
                tooltip: viewModel.fileInspectorHunkToolTips[row],
                anchorKind: control.anchorKind,
                oldLineNumber: linePair?.old,
                newLineNumber: linePair?.new,
                oldStartLine: control.oldStartLine,
                oldEndLine: control.oldEndLine,
                newStartLine: control.newStartLine,
                newEndLine: control.newEndLine,
                hasDeletionLines: control.hasDeletionLines
            )
        }
    }

    private var monacoLineBlames: [MonacoLineBlamePayload] {
        viewModel.fileInspectorLineBlames.keys.sorted().compactMap { row in
            guard let blame = viewModel.fileInspectorLineBlames[row],
                  !blame.toolTipText.isEmpty else {
                return nil
            }
            let pair = viewModel.fileInspectorLinePairs[row]
            return MonacoLineBlamePayload(
                oldLineNumber: pair?.old,
                newLineNumber: pair?.new,
                tooltip: blame.toolTipText
            )
        }
    }

    private var inspectorBackgroundColor: Color {
        ChromePalette.panelBackground
    }

    private var showsModePicker: Bool {
        !viewModel.isWorkingTreeFilesInspectorSelection
    }

    private var monacoIsDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ZStack {
            ChromePalette.panelOverlay
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .zIndex(1)
                Divider().overlay(Color.white.opacity(0.08))

                inspectorContent
                    .clipped()
            }
            .background(inspectorBackgroundColor)
            .overlay(
                Rectangle()
                    .strokeBorder(ChromePalette.panelBorder, lineWidth: 1)
            )
        }
        .onChange(of: viewModel.fileInspectorPath) { _, _ in
            targetLine = nil
        }
        .alert("Save Changes?", isPresented: $showCloseConfirmation) {
            Button("Save") {
                Task {
                    if await viewModel.saveFileInspector() {
                        handleConfirmedInspectorDismissal()
                    }
                }
            }
            Button("Don't Save", role: .destructive) {
                handleConfirmedInspectorDismissal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes in \(viewModel.fileInspectorTitle).")
        }
        .alert("File Changed Externally", isPresented: Binding(
            get: { viewModel.showFileInspectorExternalChangePrompt },
            set: { if !$0 { viewModel.keepFileInspectorLocalContent() } }
        )) {
            Button("Keep Mine") {
                viewModel.keepFileInspectorLocalContent()
            }
            Button("Reload") {
                viewModel.reloadFileInspectorFromExternalChange()
            }
        } message: {
            Text("\(viewModel.fileInspectorTitle) changed outside GitN. Keep your local edits, or reload the file from disk.")
        }
        .alert("Discard Hunk", isPresented: $showDiscardHunkConfirm) {
            Button("Discard", role: .destructive) {
                guard let pending = pendingHunkAction else { return }
                pendingHunkAction = nil
                Task { await performHunkAction(pending) }
            }
            Button("Cancel", role: .cancel) {
                pendingHunkAction = nil
            }
        } message: {
            let fileName = pendingHunkAction.map { ($0.path as NSString).lastPathComponent } ?? "this file"
            Text("Are you sure you want to discard this hunk in \"\(fileName)\"? This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(viewModel.fileInspectorTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if showsModePicker {
                        modePicker
                    }
                }

                HStack(spacing: 8) {
                    Text(viewModel.activeFileInspectorPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if viewModel.isFileInspectorEditable && viewModel.fileInspectorMode != .history {
                        saveHint
                    }
                }
            }

            Spacer()

            if viewModel.isFileInspectorDirty {
                Text("Edited")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
            }

            if viewModel.fileInspectorMode == .diff && showsModePicker {
                HStack(spacing: 0) {
                    Button {
                        commandBridge.navigateDiff(next: false)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .hoverTooltip("Previous change")

                    Button {
                        commandBridge.navigateDiff(next: true)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .hoverTooltip("Next change")
                }
            }

            Button {
                pendingModeSwitch = nil
                if viewModel.isFileInspectorDirty {
                    showCloseConfirmation = true
                } else {
                    viewModel.closeFileInspector()
                }
            } label: {
                Group {
                    if viewModel.isSavingFileInspector {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isSavingFileInspector)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(ChromePalette.panelMutedBackground)
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.fileInspectorMode },
            set: { mode in
                if viewModel.fileInspectorMode != .history &&
                    mode == .history &&
                    viewModel.isFileInspectorDirty {
                    pendingModeSwitch = mode
                    showCloseConfirmation = true
                } else {
                    Task { await viewModel.setFileInspectorMode(mode) }
                }
            }
        )) {
            Label("Preview", systemImage: "doc.text")
                .tag(RepoViewModel.FileInspectorMode.preview)
            Label("Diff", systemImage: "square.split.2x1")
                .tag(RepoViewModel.FileInspectorMode.diff)
            Label("History", systemImage: "clock.arrow.circlepath")
                .tag(RepoViewModel.FileInspectorMode.history)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 270)
    }

    @ViewBuilder
    private var monacoDiffContent: some View {
        MonacoInspectorView(
            mode: .diff,
            isDark: monacoIsDark,
            preview: nil,
            items: [
                MonacoDiffPayload(
                    path: viewModel.fileInspectorPath,
                    language: RepoViewModel.monacoLanguage(for: viewModel.fileInspectorPath.sourceLanguage),
                    originalText: viewModel.fileInspectorDiffBaseText,
                    modifiedText: viewModel.fileInspectorContent,
                    isEditable: viewModel.isFileInspectorEditable,
                    primaryHunkAction: primaryHunkAction,
                    showsDiscardAction: supportsHunkActions,
                    hunkControls: monacoHunkControls,
                    lineBlames: monacoLineBlames
                )
            ],
            commandBridge: commandBridge,
            onContentChange: { _, content in
                viewModel.fileInspectorContent = content
                viewModel.fileInspectorDisplayContent = content
                viewModel.isFileInspectorDiffEditing = false
            },
            onHunkAction: { _, hunkIndex, lineIDs, action in
                let pending = PendingHunkAction(
                    path: viewModel.fileInspectorPath,
                    hunkIndex: hunkIndex,
                    lineIDs: lineIDs,
                    action: action
                )
                if action == "discard" {
                    pendingHunkAction = pending
                    showDiscardHunkConfirm = true
                } else {
                    Task { await performHunkAction(pending) }
                }
            },
            onSaveRequest: {
                Task { _ = await viewModel.saveFileInspector() }
            },
            sourceIdentity: inspectorSourceIdentity
        )
    }

    @MainActor
    private func performHunkAction(_ pending: PendingHunkAction) async {
        let lineIDs = Set(pending.lineIDs)
        switch pending.action {
        case "stage":
            if lineIDs.isEmpty {
                await viewModel.stageHunk(pending.hunkIndex)
            } else {
                await viewModel.stageLines(pending.hunkIndex, lineIndices: lineIDs)
            }
        case "unstage":
            if lineIDs.isEmpty {
                await viewModel.unstageHunk(pending.hunkIndex)
            } else {
                await viewModel.unstageLines(pending.hunkIndex, lineIndices: lineIDs)
            }
        case "discard":
            if lineIDs.isEmpty {
                await viewModel.discardHunk(pending.hunkIndex)
            } else {
                await viewModel.discardLines(pending.hunkIndex, lineIndices: lineIDs)
            }
        default:
            break
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        ZStack {
            switch viewModel.fileInspectorMode {
            case .history:
                FileHistoryPanelContent(viewModel: viewModel, showsToolbar: false)
            case .diff:
                if viewModel.isFileTooLarge {
                    fileTooLargeState
                } else if let visualContent = viewModel.fileInspectorVisualContent {
                    VisualFileContentView(
                        content: visualContent,
                        path: viewModel.fileInspectorPath,
                        mode: .diff,
                        oldPath: viewModel.fileInspectorOldPath
                    )
                } else {
                    monacoDiffContent
                }
            case .preview:
                if let visualContent = viewModel.fileInspectorVisualContent {
                    VisualFileContentView(
                        content: visualContent,
                        path: viewModel.fileInspectorPath,
                        mode: .preview
                    )
                } else if !viewModel.isFileInspectorEditable && viewModel.fileInspectorContent.isEmpty {
                    // R2.7: a Markdown (or any) file whose contents could not be decoded as
                    // UTF-8 / read from disk surfaces the existing unreadable-file placeholder
                    // and never enters either Markdown rendering path.
                    unsupportedContentState
                } else if viewModel.fileInspectorPath.isMarkdownFile {
                    MarkdownInspectorContentView(
                        filePath: viewModel.fileInspectorPath,
                        text: Bindable(viewModel).fileInspectorContent,
                        isEditable: viewModel.isFileInspectorEditable
                    )
                } else {
                    MonacoInspectorView(
                        mode: .preview,
                        isDark: monacoIsDark,
                        preview: MonacoPreviewPayload(
                            path: viewModel.fileInspectorPath,
                            language: RepoViewModel.monacoLanguage(for: viewModel.fileInspectorPath.sourceLanguage),
                            content: viewModel.fileInspectorContent,
                            isEditable: viewModel.isFileInspectorEditable
                        ),
                        items: [],
                        commandBridge: nil,
                        onContentChange: { _, content in
                            viewModel.fileInspectorContent = content
                        },
                        onHunkAction: nil,
                        onSaveRequest: {
                            Task { _ = await viewModel.saveFileInspector() }
                        },
                        sourceIdentity: inspectorSourceIdentity
                    )
                }
            }

            if viewModel.fileInspectorMode == .diff && viewModel.isFileInspectorLoading {
                loadingOverlay
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            ChromePalette.panelBackground.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading diff...")
                    .font(.system(size: 13, weight: .medium))
                if !viewModel.fileInspectorPath.isEmpty {
                    Text(viewModel.fileInspectorPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 480)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ChromePalette.panelBorder, lineWidth: 1)
            )
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private var saveHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 8, weight: .medium))
            Text("Cmd+S")
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(ChromePalette.chromeButtonFill, in: Capsule())
        .foregroundStyle(.secondary)
    }

    private func handleConfirmedInspectorDismissal() {
        if let mode = pendingModeSwitch {
            pendingModeSwitch = nil
            Task { await viewModel.setFileInspectorMode(mode) }
        } else {
            viewModel.closeFileInspector()
        }
    }

    private var fileTooLargeState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Diff is too large to render")
                .font(.system(size: 13, weight: .medium))
            Text("\(viewModel.fileTooLargeSizeMB) MB")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Switch To Preview") {
                viewModel.fileInspectorMode = .preview
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedContentState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.zipper")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("This file can't be displayed as editable text")
                .font(.system(size: 13, weight: .medium))
            if let encoding = viewModel.fileInspectorEncodingName {
                Text("Detected encoding: \(encoding)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("Binary file or unsupported text encoding")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Editing is disabled for this file.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let message = viewModel.fileInspectorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum VisualFileContentMode {
    case preview
    case diff
}

struct VisualFileContentView: View {
    let content: VisualFileContent
    let path: String
    let mode: VisualFileContentMode
    var changeKind: DiffChangeKind? = nil
    /// The original path before a rename, used as the subtitle of the "Before" image card.
    var oldPath: String? = nil

    var body: some View {
        Group {
            if content.isImage {
                ImageDiffContentView(content: content, path: path, mode: mode, changeKind: changeKind, oldPath: oldPath)
            } else if content.isVideo {
                VideoDiffContentView(content: content, path: path)
            } else {
                BinaryFilePlaceholderView(
                    title: mode == .diff ? "Binary diff is not readable" : "Binary file preview is not readable",
                    message: content.message ?? "This file can't be displayed as text."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChromePalette.panelBackground)
    }
}

struct ImageDiffContentView: View {
    let content: VisualFileContent
    let path: String
    let mode: VisualFileContentMode
    var changeKind: DiffChangeKind? = nil
    /// The original path before a rename. When set, the "Before" card uses this as its
    /// subtitle so the user can see which path the old image came from.
    var oldPath: String? = nil

    // Overhead = outer padding (40) + card header rows (60) + card inner padding (24)
    private static let cardOverhead: CGFloat = 124

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    if mode == .preview {
                        ImageCardView(
                            title: previewTitle,
                            subtitle: path,
                            data: content.currentData,
                            availableSize: imageSize(in: geo)
                        )
                    } else if content.oldData != nil && content.newData != nil {
                        ImageCardView(
                            title: "Before",
                            subtitle: oldPath ?? path,
                            data: content.oldData,
                            availableSize: imageSize(in: geo)
                        )
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("to")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(height: 30)
                        ImageCardView(
                            title: "After",
                            subtitle: path,
                            data: content.newData,
                            availableSize: imageSize(in: geo)
                        )
                    } else if content.newData != nil {
                        ImageCardView(
                            title: "+ Added",
                            subtitle: path,
                            data: content.newData,
                            availableSize: imageSize(in: geo)
                        )
                    } else {
                        ImageCardView(
                            title: oldOnlyTitle,
                            subtitle: path,
                            data: content.oldData,
                            availableSize: imageSize(in: geo)
                        )
                    }
                }
                .padding(20)
                .frame(width: geo.size.width)
            }
        }
    }

    private func imageSize(in geo: GeometryProxy) -> CGSize {
        CGSize(
            width: max(60, geo.size.width - 64),   // outer padding 40 + card padding 24
            height: max(180, geo.size.height - Self.cardOverhead)
        )
    }

    private var oldOnlyTitle: String {
        changeKind == .deleted ? "- Deleted" : "Before"
    }

    private var previewTitle: String {
        if content.newData != nil && content.oldData == nil { return "+ Added" }
        if content.newData == nil && content.oldData != nil { return "- Deleted" }
        return "Current"
    }
}

struct ImageCardView: View {
    let title: String
    let subtitle: String
    let data: Data?
    /// Maximum space available for the image itself (excluding card chrome).
    var availableSize: CGSize = CGSize(width: CGFloat.infinity, height: 600)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Group {
                CachedDataImageView(
                    data: data,
                    viewID: "\(title)\u{1F}\(subtitle)\u{1F}\((data.map { DecodedImageCache.shared.cacheKey(for: $0) }) ?? "nil")",
                    availableSize: availableSize
                )
            }
            .padding(12)
            .background(ChromePalette.panelMutedBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(ChromePalette.panelBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BinaryFilePlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.zipper")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

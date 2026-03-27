import SwiftUI
import AppKit

enum SourceLanguage: String {
    case swift, python, javascript, typescript, go, rust, c, cpp, java, shell
    case json, yaml, dart, kotlin, ruby, php, css, html, xml, toml, text

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
    @Environment(ThemeManager.self) private var theme
    let viewModel: RepoViewModel

    @State private var targetLine: Int?
    @State private var showCloseConfirmation = false
    @State private var pendingModeSwitch: RepoViewModel.FileInspectorMode?

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
            guard let hunkIndex = viewModel.fileInspectorHunkControls[row] else { return nil }
            let linePair = viewModel.fileInspectorLinePairs[row]
            let hunk = viewModel.parsedDiff?.hunks.indices.contains(hunkIndex) == true
                ? viewModel.parsedDiff?.hunks[hunkIndex]
                : nil
            let anchorKind: String
            switch hunk?.lines.first(where: { $0.kind != .context })?.kind {
            case .addition:
                anchorKind = "addition"
            case .deletion:
                anchorKind = "deletion"
            default:
                anchorKind = "addition"
            }
            return MonacoDiffHunkControlPayload(
                row: row,
                hunkIndex: hunkIndex,
                tooltip: viewModel.fileInspectorHunkToolTips[row],
                anchorKind: anchorKind,
                oldLineNumber: linePair?.old,
                newLineNumber: linePair?.new,
                oldStartLine: hunk.map { $0.oldCount > 0 ? $0.oldStart : nil } ?? nil,
                oldEndLine: hunk.map { $0.oldCount > 0 ? ($0.oldStart + $0.oldCount - 1) : nil } ?? nil,
                newStartLine: hunk.map { $0.newCount > 0 ? $0.newStart : nil } ?? nil,
                newEndLine: hunk.map { $0.newCount > 0 ? ($0.newStart + $0.newCount - 1) : nil } ?? nil,
                hasDeletionLines: hunk?.lines.contains(where: { $0.kind == .deletion }) ?? false
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
        Color(nsColor: theme.isDark
            ? NSColor(red: 0.118, green: 0.125, blue: 0.145, alpha: 1)
            : .windowBackgroundColor)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.34 : 0.12)
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
                    .strokeBorder(theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(viewModel.fileInspectorTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    modePicker
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
        .padding(.vertical, 10)
        .background(theme.isDark ? Color.black.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
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
        .scaleEffect(0.92)
        .frame(width: 380)
    }

    @ViewBuilder
    private var monacoDiffContent: some View {
        MonacoInspectorView(
            mode: .diff,
            isDark: theme.isDark,
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
            onContentChange: { _, content in
                viewModel.fileInspectorContent = content
                viewModel.fileInspectorDisplayContent = content
                viewModel.isFileInspectorDiffEditing = false
            },
            onHunkAction: { _, hunkIndex, action in
                Task {
                    switch action {
                    case "stage":
                        await viewModel.stageHunk(hunkIndex)
                    case "unstage":
                        await viewModel.unstageHunk(hunkIndex)
                    case "discard":
                        await viewModel.discardHunk(hunkIndex)
                    default:
                        break
                    }
                }
            },
            onSaveRequest: {
                Task { _ = await viewModel.saveFileInspector() }
            }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch viewModel.fileInspectorMode {
        case .history:
            FileHistoryPanelContent(viewModel: viewModel, showsToolbar: false)
        case .diff:
            if viewModel.isFileTooLarge {
                fileTooLargeState
            } else {
                monacoDiffContent
            }
        case .preview:
            if !viewModel.isFileInspectorEditable && viewModel.fileInspectorContent.isEmpty {
                unsupportedContentState
            } else {
                MonacoInspectorView(
                    mode: .preview,
                    isDark: theme.isDark,
                    preview: MonacoPreviewPayload(
                        path: viewModel.fileInspectorPath,
                        language: RepoViewModel.monacoLanguage(for: viewModel.fileInspectorPath.sourceLanguage),
                        content: viewModel.fileInspectorContent,
                        isEditable: viewModel.isFileInspectorEditable
                    ),
                    items: [],
                    onContentChange: { _, content in
                        viewModel.fileInspectorContent = content
                    },
                    onHunkAction: nil,
                    onSaveRequest: {
                        Task { _ = await viewModel.saveFileInspector() }
                    }
                )
            }
        }
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
        .background(theme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), in: Capsule())
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

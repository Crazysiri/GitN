import SwiftUI

struct ConflictMergeView: View {
    let viewModel: RepoViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentConflictIndex = 0
    @State private var navigationID = 0
    @State private var sessionID = UUID().uuidString
    @State private var isResolvingDeleteModify = false

    private var file: ConflictFile? { viewModel.conflictMergeFile }
    private var sides: ConflictSides? { viewModel.conflictSides }
    private var document: ConflictEditorDocument? { viewModel.conflictEditorDocument }
    private var fallbackMessage: String? { viewModel.conflictFallbackMessage }
    private var isFallbackMode: Bool { fallbackMessage != nil && document == nil }
    private var totalConflicts: Int { document?.blocks.count ?? 0 }
    private var currentBlock: ConflictEditorBlock? {
        guard let document, document.blocks.indices.contains(currentConflictIndex) else { return nil }
        return document.blocks[currentConflictIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.conflictMissingSide != nil {
                deleteModifyContent
            } else if isFallbackMode {
                fallbackContent
            } else if let sides, let document, let path = file?.path {
                HStack {
                    conflictNavigator
                    Button("Keep Base") {
                        if let id = currentBlock?.id { viewModel.keepConflictAncestor(id) }
                    }
                    .disabled(currentBlock == nil)
                    Spacer()
                    Button("Undo") { viewModel.undoConflictAction() }.disabled(!viewModel.canUndoConflictAction)
                    Button("Redo") { viewModel.redoConflictAction() }.disabled(!viewModel.canRedoConflictAction)
                    Button("Reset") { viewModel.resetConflictChoices() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(6)
                MonacoInspectorView(
                    mode: .preview, isDark: colorScheme == .dark, preview: nil, items: [], commandBridge: nil,
                    onContentChange: { changedPath, text in
                        guard changedPath == path else { return }
                        viewModel.updateConflictOutputText(text)
                    },
                    onHunkAction: { changedPath, block, lines, action in
                        guard changedPath == path else { return }
                        switch action {
                        case "ours": viewModel.toggleOurs(block)
                        case "theirs": viewModel.toggleTheirs(block)
                        case "oursLine":
                            if let line = lines.first { viewModel.toggleConflictLine(block, side: .current, line: line) }
                        case "theirsLine":
                            if let line = lines.first { viewModel.toggleConflictLine(block, side: .incoming, line: line) }
                        case "allOurs": viewModel.setAllOursSelected(!viewModel.allOursSelected)
                        case "allTheirs": viewModel.setAllTheirsSelected(!viewModel.allTheirsSelected)
                        case "undo": viewModel.undoConflictAction()
                        case "redo": viewModel.redoConflictAction()
                        default: break
                        }
                    },
                    onSaveRequest: { Task { await viewModel.saveConflictResolution() } },
                    sourceIdentity: sessionID,
                    conflict: MonacoConflictPayload(path: path, sides: sides, document: document,
                        externalRevision: viewModel.conflictOutputExternalRevision,
                        navigationID: navigationID, currentBlock: currentConflictIndex)
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onChange(of: file?.id) { _, _ in
            currentConflictIndex = 0; navigationID = 0; sessionID = UUID().uuidString
            isResolvingDeleteModify = false
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 13))
                Text(file?.path ?? "")
                    .font(.system(size: 14, weight: .semibold))
                if totalConflicts > 0 {
                    Text("(\(totalConflicts) conflict\(totalConflicts == 1 ? "" : "s"))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if let remaining = document?.unresolvedBlockIDs.count, remaining > 0 {
                        Text("\(remaining) unresolved")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Divider().frame(height: 16)

            Button(action: { Task { await viewModel.saveConflictResolution() } }) {
                HStack(spacing: 3) {
                    Image(systemName: isFallbackMode ? "checkmark.circle" : "square.and.arrow.down")
                        .font(.system(size: 12))
                    Text("Mark Resolved")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.conflictMissingSide != nil || isResolvingDeleteModify)

            Button(action: { viewModel.closeConflictMerge() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var deleteModifyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modify / delete conflict")
                .font(.system(size: 16, weight: .semibold))
            Text(viewModel.conflictMissingSide == .current
                ? "The current side deleted this file; the incoming side modified it."
                : "The incoming side deleted this file; the current side modified it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack {
                Button("Keep Modified") { resolveDeleteModify(.modified) }
                Button("Delete File") { resolveDeleteModify(.deleted) }
                Button("Keep Ancestor") { resolveDeleteModify(.ancestor) }
            }
            .buttonStyle(.bordered)
            .disabled(isResolvingDeleteModify)
            if let sides, let path = file?.path {
                Text("Modified version")
                    .font(.system(size: 12, weight: .medium))
                MonacoInspectorView(
                    mode: .preview, isDark: colorScheme == .dark,
                    preview: MonacoPreviewPayload(
                        path: path, language: RepoViewModel.monacoLanguage(for: path.sourceLanguage),
                        content: (viewModel.conflictMissingSide == .current
                            ? sides.theirsLines : sides.oursLines).joined(separator: "\n"),
                        isEditable: false
                    ),
                    items: [], commandBridge: nil, onContentChange: { _, _ in },
                    onHunkAction: nil, onSaveRequest: nil, sourceIdentity: sessionID
                )
            } else if let fallbackMessage {
                Text("Preview unavailable: \(fallbackMessage)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.textBackgroundColor))
    }

    private func resolveDeleteModify(_ choice: DeleteModifyResolution) {
        guard !isResolvingDeleteModify else { return }
        let selectedSession = sessionID
        isResolvingDeleteModify = true
        Task {
            await viewModel.resolveDeleteModifyConflict(choice)
            if sessionID == selectedSession { isResolvingDeleteModify = false }
        }
    }

    private var fallbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("This conflict can't be edited as text in GitN.", systemImage: "doc.fill.badge.ellipsis")
                .font(.system(size: 16, weight: .semibold))

            Text("Resolve the file externally, then return here and choose `Mark Resolved` to stage the current working tree version.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if let fallbackMessage, !fallbackMessage.isEmpty {
                Text(fallbackMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor).opacity(0.55))
                    )
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.textBackgroundColor))
    }

    private var conflictNavigator: some View {
        HStack(spacing: 8) {
            Text("conflict")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: { navigateConflict(-1) }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(currentConflictIndex <= 0)

            Text("\(totalConflicts == 0 ? 0 : currentConflictIndex + 1) / \(totalConflicts)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)

            Button(action: { navigateConflict(1) }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(currentConflictIndex >= totalConflicts - 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func navigateConflict(_ delta: Int) {
        let next = currentConflictIndex + delta
        guard next >= 0, next < totalConflicts else { return }
        currentConflictIndex = next
        navigationID += 1
    }
}
